import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_display/core/constants/app_constants.dart';
import 'package:hermes_display/services/audio/pcm_player.dart';

import 'support/fake_tts_player.dart';

void main() {
  const rate = 24000;
  const bytesPerMs = rate * AudioSpec.bytesPerSample ~/ 1000;
  final startMs = GeminiLiveDefaults.startBuffer.inMilliseconds;
  late FakeTtsPlayer clips;
  late SegmentPcmPlayer player;
  late int completions;

  Uint8List pcm(int ms) => Uint8List(ms * bytesPerMs);

  int dataBytes(Uint8List wav) {
    return ByteData.sublistView(wav).getUint32(40, Endian.little);
  }

  int wavRate(Uint8List wav) {
    return ByteData.sublistView(wav).getUint32(24, Endian.little);
  }

  setUp(() {
    clips = FakeTtsPlayer();
    player = SegmentPcmPlayer(clips: clips);
    completions = 0;
    player.onComplete.listen((_) => completions++);
  });

  tearDown(() => player.dispose());

  test('buffers until the start threshold, then plays a WAV', () async {
    player.add(pcm(startMs ~/ 2), rate);
    expect(clips.played, isEmpty);
    expect(player.isPlaying, isTrue);

    player.add(pcm(startMs ~/ 2), rate);
    final wav = clips.played.single;
    expect(ascii.decode(wav.sublist(0, 4)), 'RIFF');
    expect(wavRate(wav), rate);
    expect(dataBytes(wav), startMs * bytesPerMs);
  });

  test('chunks arriving mid-clip play as the next segment', () async {
    player
      ..add(pcm(startMs), rate)
      ..add(pcm(50), rate)
      ..add(pcm(70), rate)
      ..finish();
    expect(clips.played, hasLength(1));

    clips.finish();
    await pumpEventQueue();
    expect(clips.played, hasLength(2));
    expect(dataBytes(clips.played.last), 120 * bytesPerMs);
    expect(completions, 0);

    clips.finish();
    await pumpEventQueue();
    expect(completions, 1);
    expect(player.isPlaying, isFalse);
  });

  test('finish plays a short reply below the threshold', () async {
    player
      ..add(pcm(80), rate)
      ..finish();
    expect(dataBytes(clips.played.single), 80 * bytesPerMs);
  });

  test('finish without audio is a no-op', () async {
    player.finish();
    await pumpEventQueue();
    expect(clips.played, isEmpty);
    expect(completions, 0);
  });

  test('stop drops the queue and stays silent', () async {
    player
      ..add(pcm(startMs), rate)
      ..add(pcm(100), rate);
    await player.stop();
    expect(clips.stops, 1);
    expect(player.isPlaying, isFalse);
    player.finish();
    clips.finish();
    await pumpEventQueue();
    expect(clips.played, hasLength(1));
    expect(completions, 0);
  });
}
