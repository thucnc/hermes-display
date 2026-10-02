import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import '../../core/constants/app_constants.dart';

/// Short audible confirmation that the wake word was heard.
abstract interface class CuePlayer {
  /// Completes once the cue has finished, so capture does not record it.
  Future<void> play();

  Future<void> dispose();
}

/// Synthesizes the cue as an in-memory WAV, so no asset is needed.
abstract final class ToneSynth {
  static const List<double> chirpHz = [880, 1320];
  static const Duration noteLength = Duration(milliseconds: 90);
  static const double amplitude = 0.35;
  static const double fadeFraction = 0.15;

  static const int _headerBytes = 44;
  static const int _fmtChunkBytes = 16;
  static const int _pcmFormat = 1;
  static const int _bitsPerSample = 16;
  static const int _riffOverhead = 36;
  static const int _int16Peak = 32767;
  static const String _riffId = 'RIFF';
  static const String _waveId = 'WAVE';
  static const String _fmtId = 'fmt ';
  static const String _dataId = 'data';

  static Duration get length => noteLength * chirpHz.length;

  static Uint8List chirpWav() => wav(sineSamples());

  static Int16List sineSamples() {
    final perNote =
        AudioSpec.sampleRate *
        noteLength.inMicroseconds ~/
        Duration.microsecondsPerSecond;
    final out = Int16List(perNote * chirpHz.length);
    final fade = max(1, (perNote * fadeFraction).round());
    for (var n = 0; n < chirpHz.length; n++) {
      final step = 2 * pi * chirpHz[n] / AudioSpec.sampleRate;
      for (var i = 0; i < perNote; i++) {
        final edge = min(i, perNote - 1 - i);
        final gain = edge >= fade ? 1.0 : edge / fade;
        final value = sin(step * i) * amplitude * gain * _int16Peak;
        out[n * perNote + i] = value.round();
      }
    }
    return out;
  }

  static Uint8List wav(
    Int16List samples, {
    int sampleRate = AudioSpec.sampleRate,
  }) {
    final dataBytes = samples.length * AudioSpec.bytesPerSample;
    final frameBytes = AudioSpec.channels * AudioSpec.bytesPerSample;
    final header = _LeWriter(_headerBytes)
      ..id(_riffId)
      ..u32(_riffOverhead + dataBytes)
      ..id(_waveId)
      ..id(_fmtId)
      ..u32(_fmtChunkBytes)
      ..u16(_pcmFormat)
      ..u16(AudioSpec.channels)
      ..u32(sampleRate)
      ..u32(sampleRate * frameBytes)
      ..u16(frameBytes)
      ..u16(_bitsPerSample)
      ..id(_dataId)
      ..u32(dataBytes);
    final pcm = samples.buffer.asUint8List(samples.offsetInBytes, dataBytes);
    return (BytesBuilder(copy: false)
          ..add(header.bytes)
          ..add(pcm))
        .takeBytes();
  }
}

/// Sequential little-endian writer for the RIFF header.
final class _LeWriter {
  _LeWriter(int size) : _data = ByteData(size);

  static const int _u16Bytes = 2;
  static const int _u32Bytes = 4;

  final ByteData _data;
  int _offset = 0;

  Uint8List get bytes => _data.buffer.asUint8List();

  /// Four-character chunk ids are stored as ASCII, big-endian.
  void id(String fourCc) {
    for (final unit in fourCc.codeUnits) {
      _data.setUint8(_offset++, unit);
    }
  }

  void u16(int value) {
    _data.setUint16(_offset, value, Endian.little);
    _offset += _u16Bytes;
  }

  void u32(int value) {
    _data.setUint32(_offset, value, Endian.little);
    _offset += _u32Bytes;
  }
}

final class ToneCuePlayer implements CuePlayer {
  ToneCuePlayer({AudioPlayer? player}) : _player = player ?? AudioPlayer();

  static const String _mime = 'audio/wav';

  /// Never block the voice flow on a stuck audio backend.
  static const Duration _slack = Duration(milliseconds: 400);

  final AudioPlayer _player;
  late final Uint8List _wav = ToneSynth.chirpWav();

  @override
  Future<void> play() async {
    try {
      final done = _player.onPlayerComplete.first;
      await _player.play(
        BytesSource(_wav, mimeType: _mime),
        ctx: AudioContextConfig(
          focus: AudioContextConfigFocus.mixWithOthers,
        ).build(),
      );
      await done.timeout(ToneSynth.length + _slack);
    } on Object catch (error) {
      debugPrint('Cue playback failed: $error');
    }
  }

  @override
  Future<void> dispose() => _player.dispose();
}
