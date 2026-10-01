import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../../core/constants/app_constants.dart';
import 'audio_frame.dart';

/// What to listen for. [sensitivity] is the user-facing 0..1 slider.
final class WakeConfig {
  const WakeConfig({required this.keyword, required this.sensitivity});

  final String keyword;
  final double sensitivity;

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
        other.sensitivity == sensitivity;
  }

  @override
  int get hashCode => Object.hash(keyword, sensitivity);
}

/// Keyword spotter contract; the real one needs native libs and a model.
abstract interface class WakeDetector {
  /// Returns false when the model is missing or fails to load.
  Future<bool> load(WakeConfig config);

  /// Feeds audio; true exactly when the keyword fires.
  bool accept(AudioFrame frame);

  void reset();

  void dispose();
}

/// Files of a sherpa-onnx streaming transducer KWS model, e.g.
/// `sherpa-onnx-kws-zipformer-gigaspeech-3.3M-2024-01-01`, unpacked into
/// `<app support>/kws/`.
final class KwsModelFiles {
  const KwsModelFiles({
    required this.encoder,
    required this.decoder,
    required this.joiner,
    required this.tokens,
    this.bpeVocab,
    this.keywordsFile,
  });

  static const String dirName = 'kws';
  static const String _onnx = '.onnx';
  static const String _int8 = '.int8.onnx';
  static const String _encoder = 'encoder';
  static const String _decoder = 'decoder';
  static const String _joiner = 'joiner';
  static const String _tokens = 'tokens.txt';
  static const String _bpeVocab = 'bpe.vocab';
  static const String _keywords = 'keywords.txt';

  final String encoder;
  final String decoder;
  final String joiner;
  final String tokens;

  /// Present: free-text keywords are tokenized on device.
  final String? bpeVocab;

  /// Fallback when there is no vocab: pre-tokenized keyword list.
  final String? keywordsFile;

  static Future<KwsModelFiles?> locate() async {
    final base = await getApplicationSupportDirectory();
    return scan(Directory('${base.path}/$dirName'));
  }

  /// Picks model parts by name, preferring int8 weights.
  static KwsModelFiles? scan(Directory dir) {
    if (!dir.existsSync()) {
      return null;
    }
    final paths = dir.listSync().whereType<File>().map((f) => f.path).toList();
    final encoder = _pick(paths, _encoder);
    final decoder = _pick(paths, _decoder);
    final joiner = _pick(paths, _joiner);
    final tokens = _named(paths, _tokens);
    if (encoder == null || decoder == null || joiner == null) {
      return null;
    }
    if (tokens == null) {
      return null;
    }
    return KwsModelFiles(
      encoder: encoder,
      decoder: decoder,
      joiner: joiner,
      tokens: tokens,
      bpeVocab: _named(paths, _bpeVocab),
      keywordsFile: _named(paths, _keywords),
    );
  }

  static String? _pick(List<String> paths, String role) {
    final matches = paths.where((p) {
      final name = p.split(Platform.pathSeparator).last;
      return name.startsWith(role) && name.endsWith(_onnx);
    }).toList();
    if (matches.isEmpty) {
      return null;
    }
    return matches.firstWhere(
      (p) => p.endsWith(_int8),
      orElse: () => matches.first,
    );
  }

  static String? _named(List<String> paths, String name) {
    for (final path in paths) {
      if (path.split(Platform.pathSeparator).last == name) {
        return path;
      }
    }
    return null;
  }
}

/// On-device keyword spotting via sherpa-onnx.
final class SherpaWakeDetector implements WakeDetector {
  SherpaWakeDetector({Future<KwsModelFiles?> Function()? locate})
    : _locate = locate ?? KwsModelFiles.locate;

  static const String _bpeUnit = 'bpe';
  static const String _thresholdTag = '#';
  static const String _labelTag = '@';
  static const String _space = ' ';
  static const String _underscore = '_';

  static bool _bindingsReady = false;

  final Future<KwsModelFiles?> Function() _locate;
  sherpa.KeywordSpotter? _spotter;
  sherpa.OnlineStream? _stream;

  @override
  Future<bool> load(WakeConfig config) async {
    dispose();
    try {
      final files = await _locate();
      if (files == null) {
        return false;
      }
      _ensureBindings();
      return _build(files, config);
    } on Object catch (error) {
      debugPrint('Wake detector unavailable: $error');
      dispose();
      return false;
    }
  }

  bool _build(KwsModelFiles files, WakeConfig config) {
    final vocab = files.bpeVocab;
    final keywordsFile = files.keywordsFile;
    if (vocab == null && keywordsFile == null) {
      return false;
    }
    final line = vocab == null ? '' : _keywordLine(config);
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
          modelingUnit: vocab == null ? '' : _bpeUnit,
          bpeVocab: vocab ?? '',
        ),
        keywordsFile: vocab == null ? keywordsFile ?? '' : '',
        keywordsBuf: line,
        keywordsBufSize: utf8.encode(line).length,
        keywordsThreshold: config.threshold,
      ),
    );
    _spotter = spotter;
    _stream = spotter.createStream();
    return true;
  }

  /// `HEY SEN #0.28 @HEY_SEN`: free text, per-keyword threshold, label.
  static String _keywordLine(WakeConfig config) {
    final words = config.keyword.trim().toUpperCase();
    final label = words.replaceAll(_space, _underscore);
    final threshold = config.threshold.toStringAsFixed(2);
    return '$words $_thresholdTag$threshold $_labelTag$label';
  }

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
