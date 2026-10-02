import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_display/core/constants/app_constants.dart';
import 'package:hermes_display/core/state/brain_mode.dart';
import 'package:hermes_display/core/state/display_controller.dart';
import 'package:hermes_display/core/state/display_state.dart';
import 'package:hermes_display/services/gemini_live_service.dart';
import 'package:hermes_display/services/hermes_websocket_client.dart';
import 'package:hermes_display/services/settings_service.dart';
import 'package:hermes_display/services/wake_word_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_gemini_service.dart';
import 'support/fake_hub_tts.dart';
import 'support/fake_pcm_player.dart';
import 'support/fake_transport.dart';
import 'support/fake_tts_player.dart';
import 'support/fake_voice.dart';

void main() {
  const setupComplete = '{"setupComplete":{}}';
  const turnComplete = '{"serverContent":{"turnComplete":true}}';
  late FakeTransportFactory hub;
  late FakeTransportFactory sockets;
  late FakeMic mic;
  late FakeGeminiService gemini;
  late FakeHubTts hubTts;
  late FakePcmPlayer pcm;
  late DisplayController controller;

  Future<void> build({
    BrainMode brain = BrainMode.gemini,
    FakeOutcome hubOutcome = FakeOutcome.reject,
    FakeOutcome liveOutcome = FakeOutcome.accept,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final settings = await SettingsService.create();
    await settings.save(
      HubSettings.defaults.copyWith(geminiApiKey: 'key', brainMode: brain),
    );
    hub = FakeTransportFactory(fallback: hubOutcome);
    sockets = FakeTransportFactory(fallback: liveOutcome);
    mic = FakeMic();
    gemini = FakeGeminiService();
    hubTts = FakeHubTts();
    pcm = FakePcmPlayer();
    controller = DisplayController(
      settingsService: settings,
      client: HermesWebSocketClient(transportFactory: hub.call),
      voice: WakeWordService(
        mic: mic,
        detector: FakeDetector(),
        cue: FakeCue(),
      ),
      tts: FakeTtsPlayer(),
      gemini: gemini,
      hubTts: hubTts,
      live: GeminiLiveService(transportFactory: sockets.call),
      pcm: pcm,
    )..start();
    await pumpEventQueue();
  }

  String audio(List<int> bytes) {
    return jsonEncode({
      'serverContent': {
        'modelTurn': {
          'parts': [
            {
              'inlineData': {
                'mimeType': 'audio/pcm;rate=24000',
                'data': base64Encode(bytes),
              },
            },
          ],
        },
      },
    });
  }

  String said(String key, String text) {
    return jsonEncode({
      'serverContent': {
        key: {'text': text},
      },
    });
  }

  Future<void> talk() async {
    for (var i = 0; i < 5; i++) {
      mic.emit(Frames.of(Frames.loud));
    }
    await pumpEventQueue();
  }

  Future<void> stopTalking() async {
    final silence =
        VoiceTiming.endSilence.inMilliseconds ~/ Frames.chunk.inMilliseconds;
    for (var i = 0; i < silence; i++) {
      mic.emit(Frames.of(Frames.quiet));
    }
    await pumpEventQueue();
  }

  List<Map<String, dynamic>> liveSent() {
    return [
      for (final raw in sockets.last.sent)
        jsonDecode(raw) as Map<String, dynamic>,
    ];
  }

  Future<void> openLive() async {
    expect(await controller.listen(), ListenResult.started);
    await pumpEventQueue();
    sockets.last.push(setupComplete);
    await pumpEventQueue();
  }

  tearDown(() => controller.dispose());

  test('wake opens a live session without the hub', () async {
    await build();
    await openLive();
    expect(controller.state, DisplayState.listening);
    expect(sockets.created, hasLength(1));
    final setup = liveSent().first['setup'] as Map<String, dynamic>;
    expect(setup['model'], 'models/gemini-3.8-live');
    final parts = (setup['systemInstruction'] as Map)['parts'] as List;
    expect((parts.single as Map)['text'], contains('Sen'));
  });

  test('mic PCM streams to Gemini Live, not the hub', () async {
    await build(hubOutcome: FakeOutcome.accept);
    await openLive();
    await talk();
    final chunks = liveSent().where((m) => m.containsKey('realtimeInput'));
    expect(chunks, hasLength(5));
    expect(hub.last.sent.where((s) => s.contains('wake')), isEmpty);
    expect(hub.last.sentBytes, isEmpty);
  });

  test('a full spoken turn plays the reply and keeps the card', () async {
    await build();
    await openLive();
    await talk();
    sockets.last.push(said('inputTranscription', 'chiên trứng thế nào'));
    await stopTalking();
    expect(controller.state, DisplayState.thinking);
    expect(liveSent().last, {
      'clientContent': {'turnComplete': true},
    });
    expect(controller.transcript, 'chiên trứng thế nào');

    sockets.last
      ..push(audio([1, 2, 3, 4]))
      ..push(said('outputTranscription', '1. Đập trứng.\n'))
      ..push(said('outputTranscription', '2. Chiên vàng.'));
    await pumpEventQueue();
    expect(controller.state, DisplayState.speaking);
    expect(pcm.chunks.single, [1, 2, 3, 4]);
    expect(pcm.rates.single, 24000);
    expect(controller.reply, '1. Đập trứng.\n2. Chiên vàng.');

    sockets.last.push(turnComplete);
    await pumpEventQueue();
    expect(pcm.finishes, 1);
    expect(controller.state, DisplayState.speaking);

    pcm.drain();
    await pumpEventQueue();
    expect(controller.state, DisplayState.idle);
    expect(controller.rich?.title, 'chiên trứng thế nào');
    expect(controller.rich?.steps, ['Đập trứng.', 'Chiên vàng.']);
    expect(hubTts.asked, isEmpty);
    expect(gemini.audios, isEmpty);
  });

  test(
    'server-side end of speech moves on before the local endpointer',
    () async {
      await build();
      await openLive();
      await talk();
      sockets.last.push(audio([5, 6]));
      await pumpEventQueue();
      expect(controller.state, DisplayState.speaking);
      expect(mic.isOpen, isTrue);
      expect(pcm.chunks, hasLength(1));
    },
  );

  test('barge-in stops playback', () async {
    await build();
    await openLive();
    await talk();
    await stopTalking();
    sockets.last.push(audio([1, 2]));
    await pumpEventQueue();
    sockets.last.push('{"serverContent":{"interrupted":true}}');
    await pumpEventQueue();
    expect(pcm.stops, greaterThan(0));
  });

  test('warm session is reused for the next turn', () async {
    await build();
    await openLive();
    await talk();
    await stopTalking();
    sockets.last
      ..push(audio([1, 2]))
      ..push(turnComplete);
    await pumpEventQueue();
    pcm.drain();
    await pumpEventQueue();
    expect(await controller.listen(), ListenResult.started);
    await pumpEventQueue();
    expect(sockets.created, hasLength(1));
  });

  test('cancel closes the session and ignores late audio', () async {
    await build();
    await openLive();
    await talk();
    await stopTalking();
    controller.cancel();
    sockets.last.push(audio([1, 2]));
    await pumpEventQueue();
    expect(sockets.last.closed, isTrue);
    expect(pcm.chunks, isEmpty);
    expect(controller.state, DisplayState.idle);
  });

  group('fallback', () {
    test('refused socket falls back to the WAV request', () async {
      await build(liveOutcome: FakeOutcome.reject);
      expect(await controller.listen(), ListenResult.started);
      await pumpEventQueue();
      await talk();
      await stopTalking();
      expect(gemini.audios, hasLength(1));
      expect(controller.state, DisplayState.thinking);
    });

    test('socket drop while thinking shows an error', () async {
      await build();
      await openLive();
      await talk();
      await stopTalking();
      await sockets.last.drop();
      await pumpEventQueue();
      expect(controller.state, DisplayState.idle);
      expect(controller.lastError, isNotNull);
    });

    test('hub brain never dials Gemini Live', () async {
      await build(brain: BrainMode.hub, hubOutcome: FakeOutcome.accept);
      expect(await controller.listen(), ListenResult.started);
      await pumpEventQueue();
      expect(sockets.created, isEmpty);
    });
  });
}
