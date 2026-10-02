import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_display/core/constants/app_constants.dart';
import 'package:hermes_display/core/state/brain_mode.dart';
import 'package:hermes_display/core/state/display_controller.dart';
import 'package:hermes_display/core/state/display_state.dart';
import 'package:hermes_display/services/hermes_websocket_client.dart';
import 'package:hermes_display/services/settings_service.dart';
import 'package:hermes_display/services/wake_word_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_gemini_service.dart';
import 'support/fake_hub_tts.dart';
import 'support/fake_transport.dart';
import 'support/fake_tts_player.dart';
import 'support/fake_voice.dart';

void main() {
  const heard = 'mấy giờ rồi';
  const answer = 'Trứng chiên:\n1. Đập trứng.\n2. Chiên vàng.';
  const transcript = '{"type":"transcript","text":"$heard","final":true}';
  final mp3 = Uint8List.fromList([0x49, 0x44, 0x33, 0x03]);
  late FakeTransportFactory hub;
  late FakeMic mic;
  late FakeGeminiService gemini;
  late FakeHubTts hubTts;
  late FakeTtsPlayer player;
  late DisplayController controller;

  Future<void> build({BrainMode brain = BrainMode.gemini}) async {
    SharedPreferences.setMockInitialValues({});
    final settings = await SettingsService.create();
    await settings.save(
      HubSettings.defaults.copyWith(geminiApiKey: 'key', brainMode: brain),
    );
    hub = FakeTransportFactory();
    mic = FakeMic();
    gemini = FakeGeminiService();
    hubTts = FakeHubTts();
    player = FakeTtsPlayer();
    controller = DisplayController(
      settingsService: settings,
      client: HermesWebSocketClient(transportFactory: hub.call),
      voice: WakeWordService(
        mic: mic,
        detector: FakeDetector(),
        cue: FakeCue(),
      ),
      tts: player,
      gemini: gemini,
      hubTts: hubTts,
    )..start();
    await pumpEventQueue();
  }

  Future<void> speakAndStop() async {
    await controller.listen();
    for (var i = 0; i < 5; i++) {
      mic.emit(Frames.of(Frames.loud));
    }
    final silence =
        VoiceTiming.endSilence.inMilliseconds ~/ Frames.chunk.inMilliseconds;
    for (var i = 0; i < silence; i++) {
      mic.emit(Frames.of(Frames.quiet));
    }
    await pumpEventQueue();
  }

  tearDown(() => controller.dispose());

  test('voice question goes to Gemini and the answer is spoken', () async {
    await build();
    await speakAndStop();
    expect(hub.last.sent.last, contains('"brain":"gemini"'));
    expect(controller.state, DisplayState.thinking);

    hub.last.push(transcript);
    await pumpEventQueue();
    expect(gemini.prompts.single, heard);
    expect(controller.transcript, heard);
    expect(controller.state, DisplayState.thinking);

    gemini.answer(answer);
    await pumpEventQueue();
    expect(controller.state, DisplayState.speaking);
    final (uri, text) = hubTts.asked.single;
    expect(uri.toString(), 'http://localhost:8901/tts');
    expect(text, 'Trứng chiên: 1. Đập trứng. 2. Chiên vàng.');

    hubTts.reply(mp3);
    await pumpEventQueue();
    expect(player.played.single, mp3);
    expect(controller.state, DisplayState.speaking);

    player.finish();
    await pumpEventQueue();
    expect(controller.state, DisplayState.idle);
    expect(controller.rich, isNotNull);
  });

  test('TTS failure falls back to the text reply', () async {
    await build();
    await speakAndStop();
    hub.last.push(transcript);
    await pumpEventQueue();
    gemini.answer(answer);
    await pumpEventQueue();
    hubTts.reply(null);
    await pumpEventQueue();
    expect(player.played, isEmpty);
    expect(controller.state, DisplayState.speaking);
    expect(controller.reply, answer);
  });

  test('cancel during TTS fetch keeps the clip silent', () async {
    await build();
    await speakAndStop();
    hub.last.push(transcript);
    await pumpEventQueue();
    gemini.answer(answer);
    await pumpEventQueue();
    controller.cancel();
    hubTts.reply(mp3);
    await pumpEventQueue();
    expect(player.played, isEmpty);
    expect(controller.state, DisplayState.idle);
  });

  test('hub brain keeps the hub voice turn', () async {
    await build(brain: BrainMode.hub);
    await speakAndStop();
    expect(hub.last.sent.last, isNot(contains('brain')));
    hub.last.push(transcript);
    await pumpEventQueue();
    expect(gemini.prompts, isEmpty);
    expect(controller.transcript, heard);
  });
}
