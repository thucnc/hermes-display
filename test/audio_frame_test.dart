import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_display/core/constants/app_constants.dart';
import 'package:hermes_display/services/audio/audio_frame.dart';
import 'package:hermes_display/services/audio/cue_player.dart';

void main() {
  test('decodes PCM16 little-endian to floats', () {
    final pcm = Uint8List.fromList([0x00, 0x40, 0x00, 0xC0]);
    final frame = AudioFrame(pcm);
    expect(frame.samples, [0.5, -0.5]);
    expect(frame.rms, closeTo(0.5, 1e-9));
  });

  test('aligner carries odd bytes across chunks', () {
    final aligner = Pcm16Aligner();
    expect(aligner.push(Uint8List.fromList([0x00])), isNull);
    final first = aligner.push(Uint8List.fromList([0x40, 0x00]))!;
    expect(first.samples, [0.5]);
    final second = aligner.push(Uint8List.fromList([0xC0]))!;
    expect(second.samples, [-0.5]);
  });

  test('cue is a valid mono 16 kHz WAV', () {
    final wav = ToneSynth.chirpWav();
    final header = ByteData.sublistView(wav);
    expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
    expect(header.getUint16(22, Endian.little), AudioSpec.channels);
    expect(header.getUint32(24, Endian.little), AudioSpec.sampleRate);
    final dataBytes = header.getUint32(40, Endian.little);
    expect(wav.length, 44 + dataBytes);
    final samples = ToneSynth.sineSamples();
    expect(samples.first, 0, reason: 'fade-in avoids a click');
    expect(samples.reduce((a, b) => a > b ? a : b), greaterThan(0));
  });
}
