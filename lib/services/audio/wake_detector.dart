import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../../core/constants/app_constants.dart';
import 'audio_frame.dart';
import 'keyword_tokens.dart';
import 'wake_model_installer.dart';

/// What to listen for. [sensitivity] is the user-facing 0..1 slider.
final class WakeConfig {
  const WakeConfig({
    required this.keyword,
    required this.sensitivity,
    this.confirmBlanks = WakeTuning.defaultTrailingBlanks,
  });

  final String keyword;
  final double sensitivity;

  /// Blank frames sherpa needs after a match before it reports it.
  final int confirmBlanks;

  int get trailingBlanks {
    return confirmBlanks.clamp(
      WakeTuning.minTrailingBlanks,
      WakeTuning.maxTrailingBlanks,
    );
  }

  /// Spotter threshold: high sensitivity triggers on weaker matches.
  double get threshold {
    final s = sensitivity.clamp(
      SettingsLimits.minSensitivity,
      SettingsLimits.maxSensitivity,
    );
    const span = WakeTuning.strictThreshold - WakeTuning.looseThreshold;
    return WakeTuning.strictThreshold - s * span;
  }

  @override
  bool operator ==(Object other) {
    return other is WakeConfig &&
        other.keyword == keyword &&
        other.sensitivity == sensitivity &&
        other.confirmBlanks == confirmBlanks;
  }

  @override
  int get hashCode => Object.hash(keyword, sensitivity, confirmBlanks);
}

/// Keyword spotter contract; the real one needs native libs and a model.
abstract interface class WakeDetector {
  /// Returns false when the model is missing or fails to load.
  Future<bool> load(WakeConfig config);

  /// Feeds audio; true exactly when the keyword fires.
  bool accept(AudioFrame frame);

  void reset();

  /// Whether [keyword] can be spotted; uses the vocabulary from the last
  /// successful model lookup.
  KeywordCheck check(String keyword);

  void dispose();
}

/// On-device keyword spotting via sherpa-onnx. The keyword line is built
/// from the installed `tokens.txt` and written to `keywords.txt` on load.
final class SherpaWakeDetector implements WakeDetector {
  SherpaWakeDetector({required Future<KwsModelDir?> Function() locate})
    : _locate = locate;

  static const String _modelType = 'zipformer2';
  static const String _newline = '\n';

  static bool _bindingsReady = false;

  final Future<KwsModelDir?> Function() _locate;
  sherpa.KeywordSpotter? _spotter;
  sherpa.OnlineStream? _stream;
  KwsVocab? _vocab;

  @override
  Future<bool> load(WakeConfig config) async {
    dispose();
    try {
      final files = await _locate();
      if (files == null) {
        return false;
      }
      final vocab = KwsVocab.parse(await File(files.tokens).readAsString());
      _vocab = vocab;
      final line = keywordLine(config.keyword, vocab);
      await File(files.keywords).writeAsString('$line$_newline', flush: true);
      _ensureBindings();
      _build(files, config);
      return true;
    } on KeywordException catch (error) {
      debugPrint('Wake keyword not in model vocabulary: $error');
      return false;
    } on Object catch (error) {
      debugPrint('Wake detector unavailable: $error');
      dispose();
      return false;
    }
  }

  void _build(KwsModelDir files, WakeConfig config) {
    final spotter = sherpa.KeywordSpotter(
      sherpa.KeywordSpotterConfig(
        model: sherpa.OnlineModelConfig(
          transducer: sherpa.OnlineTransducerModelConfig(
            encoder: files.encoder,
            decoder: files.decoder,
            joiner: files.joiner,
          ),
          tokens: files.tokens,
          numThreads: WakeTuning.numThreads,
          debug: false,
          modelType: _modelType,
        ),
        keywordsFile: files.keywords,
        keywordsScore: WakeTuning.keywordsScore,
        keywordsThreshold: config.threshold,
        numTrailingBlanks: config.trailingBlanks,
      ),
    );
    _spotter = spotter;
    _stream = spotter.createStream();
  }

  @override
  KeywordCheck check(String keyword) => checkKeyword(keyword, _vocab);

  static void _ensureBindings() {
    if (_bindingsReady) {
      return;
    }
    sherpa.initBindings();
    _bindingsReady = true;
  }

  @override
  bool accept(AudioFrame frame) {
    final spotter = _spotter;
    final stream = _stream;
    if (spotter == null || stream == null) {
      return false;
    }
    stream.acceptWaveform(
      samples: frame.samples,
      sampleRate: AudioSpec.sampleRate,
    );
    var fired = false;
    while (spotter.isReady(stream)) {
      spotter.decode(stream);
      if (spotter.getResult(stream).keyword.isEmpty) {
        continue;
      }
      // Reset right away so one utterance cannot fire twice.
      spotter.reset(stream);
      fired = true;
    }
    return fired;
  }

  @override
  void reset() {
    final spotter = _spotter;
    final stream = _stream;
    if (spotter == null || stream == null) {
      return;
    }
    spotter.reset(stream);
  }

  @override
  void dispose() {
    _stream?.free();
    _stream = null;
    _spotter?.free();
    _spotter = null;
  }
}
