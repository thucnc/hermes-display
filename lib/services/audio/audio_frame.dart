import 'dart:math';
import 'dart:typed_data';

import '../../core/constants/app_constants.dart';

/// One chunk of mono PCM16 audio in both wire and float form.
final class AudioFrame {
  AudioFrame(this.pcm) : samples = _toFloat(pcm);

  /// Little-endian PCM16, always an even number of bytes.
  final Uint8List pcm;

  /// Same audio as floats in -1..1, the format sherpa-onnx expects.
  final Float32List samples;

  Duration get duration => Duration(
    microseconds:
        samples.length * Duration.microsecondsPerSecond ~/ AudioSpec.sampleRate,
  );

  double get rms {
    if (samples.isEmpty) {
      return 0;
    }
    var sum = 0.0;
    for (final sample in samples) {
      sum += sample * sample;
    }
    return sqrt(sum / samples.length);
  }

  static Float32List _toFloat(Uint8List pcm) {
    final view = ByteData.sublistView(pcm);
    final count = pcm.length ~/ AudioSpec.bytesPerSample;
    final out = Float32List(count);
    for (var i = 0; i < count; i++) {
      final value = view.getInt16(i * AudioSpec.bytesPerSample, Endian.little);
      out[i] = value / AudioSpec.int16Max;
    }
    return out;
  }
}

/// Re-aligns an arbitrary byte stream onto 16-bit sample boundaries.
final class Pcm16Aligner {
  int? _carry;

  AudioFrame? push(Uint8List chunk) {
    final carry = _carry;
    final total = chunk.length + (carry == null ? 0 : 1);
    final usable = total - total % AudioSpec.bytesPerSample;
    if (usable == 0) {
      _carry = chunk.isEmpty ? carry : chunk.first;
      return null;
    }
    final out = Uint8List(usable);
    var offset = 0;
    if (carry != null) {
      out[0] = carry;
      offset = 1;
    }
    final take = usable - offset;
    out.setRange(offset, usable, chunk);
    _carry = total == usable ? null : chunk[take];
    return AudioFrame(out);
  }

  void reset() => _carry = null;
}
