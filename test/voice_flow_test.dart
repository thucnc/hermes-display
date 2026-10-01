import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_display/core/constants/app_constants.dart';
import 'package:hermes_display/core/state/display_controller.dart';
import 'package:hermes_display/core/state/display_state.dart';
import 'package:hermes_display/services/audio/mic_source.dart';
import 'package:hermes_display/services/hermes_websocket_client.dart';
import 'package:hermes_display/services/settings_service.dart';
import 'package:hermes_display/services/wake_word_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_transport.dart';
import 'support/fake_voice.dart';

void main() {
  late FakeTransportFactory hub;
  late FakeMic mic;
  late FakeCue cue;
  late WakeWordService voice;
  late DisplayController controller;

  Future<void> build({
    FakeOutcome link = FakeOutcome.accept,
    MicPermission permission = MicPermission.granted,
  }) async {
    SharedPreferences.setMockInitialValues({});
    hub = FakeTransportFactory(fallback: link);
    mic = FakeMic(permission: permission);
    cue = FakeCue();
    voice = WakeWordService(mic: mic, detector: FakeDetector(), cue: cue);
    controller = DisplayController(
      settingsService: await SettingsService.create(),
      client: HermesWebSocketClient(transportFactory: hub.call),
      voice: voice,
    )..start();
    await pumpEventQueue();
  }

  Future<void> say(double amplitude, Duration span) async {
    final count = span.inMilliseconds ~/ Frames.chunk.inMilliseconds;
    for (var i = 0; i < count; i++) {
      mic.emit(Frames.of(amplitude));
    }
    await pumpEventQueue();
  }

  tearDown(() => controller.dispose());

  test('wake word: cue, listening, stream audio, end of utterance', () async {
    await build();
    expect(controller.voiceStatus, VoiceStatus.ready);

    mic.emit(Frames.of(Voice.wakeAmplitude));
    await pumpEventQueue();
    expect(cue.plays, 1);
    expect(controller.state, DisplayState.listening);
    expect(hub.last.sent.single, contains('"wake"'));

    await say(Frames.loud, const Duration(milliseconds: 500));
    expect(hub.last.sentBytes, hasLength(5));
    expect(controller.level.value, greaterThan(0));

    await say(Frames.quiet, VoiceTiming.endSilence);
    expect(hub.last.sent.last, contains('audio_end'));
    expect(controller.state, DisplayState.thinking);
  });

  test('tap cancel stops capture and returns to idle', () async {
    await build();
    expect(await controller.listen(), ListenResult.started);
    controller.cancel();
    await pumpEventQueue();
    expect(controller.state, DisplayState.idle);

    final sentBefore = hub.last.sentBytes.length;
    await say(Frames.loud, Frames.chunk);
    expect(hub.last.sentBytes, hasLength(sentBefore));
  });

  test('silence after the cue cancels the turn', () async {
    await build();
    await controller.listen();
    await say(Frames.quiet, VoiceTiming.noSpeech);
    expect(controller.state, DisplayState.idle);
    expect(hub.last.sent.last, contains('cancel'));
  });

  test('hub moving on ends local capture', () async {
    await build();
    await controller.listen();
    hub.last.push('{"type":"state","state":"thinking"}');
    await pumpEventQueue();
    final sentBefore = hub.last.sentBytes.length;
    await say(Frames.loud, Frames.chunk);
    expect(hub.last.sentBytes, hasLength(sentBefore));
  });

  test('offline wake word does not enter listening', () async {
    await build(link: FakeOutcome.reject);
    mic.emit(Frames.of(Voice.wakeAmplitude));
    await pumpEventQueue();
    expect(controller.state, DisplayState.idle);
    expect(cue.plays, 0);
    expect(await controller.listen(), ListenResult.offline);
  });

  test('denied microphone reports instead of listening', () async {
    await build(permission: MicPermission.permanentlyDenied);
    expect(controller.voiceStatus, VoiceStatus.blocked);
    expect(await controller.listen(), ListenResult.noPermission);
    expect(controller.state, DisplayState.idle);
    expect(hub.last.sent, isEmpty);
  });

  test('backgrounding cancels the turn and frees the mic', () async {
    await build();
    await controller.listen();
    voice.handleLifecycle(AppLifecycleState.paused);
    await pumpEventQueue();
    expect(controller.state, DisplayState.idle);
    expect(hub.last.sent.last, contains('cancel'));
    expect(mic.isOpen, isFalse);

    voice.handleLifecycle(AppLifecycleState.resumed);
    await pumpEventQueue();
    expect(mic.isOpen, isTrue);
  });
}
