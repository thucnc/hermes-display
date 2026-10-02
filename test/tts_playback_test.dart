import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_display/core/constants/app_constants.dart';
import 'package:hermes_display/core/state/display_controller.dart';
import 'package:hermes_display/core/state/display_state.dart';
import 'package:hermes_display/services/hermes_websocket_client.dart';
import 'package:hermes_display/services/protocol/hermes_message.dart';
import 'package:hermes_display/services/settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_transport.dart';
import 'support/fake_tts_player.dart';

void main() {
  const reply = 'Bây giờ là 3 giờ';
  const mp3 = [0x49, 0x44, 0x33, 0x03];
  const idle = '{"type":"state","state":"idle"}';
  const thinking = '{"type":"state","state":"thinking"}';
  const speaking = '{"type":"state","state":"speaking"}';
  late SettingsService settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = await SettingsService.create();
  });

  String tts({List<int>? audio}) {
    return jsonEncode({
      WireKey.type: WireType.tts,
      WireKey.text: reply,
      if (audio != null) WireKey.audio: base64Encode(audio),
    });
  }

  /// Runs [body] with a connected controller already speaking [reply].
  void speak(
    void Function(
      FakeAsync async,
      DisplayController controller,
      FakeTransport hub,
      FakeTtsPlayer player,
    )
    body, {
    List<int>? audio = mp3,
  }) {
    fakeAsync((async) {
      final factory = FakeTransportFactory();
      final player = FakeTtsPlayer();
      final controller = DisplayController(
        settingsService: settings,
        client: HermesWebSocketClient(transportFactory: factory.call),
        tts: player,
      )..start();
      async.flushMicrotasks();
      factory.last
        ..push(thinking)
        ..push(tts(audio: audio))
        ..push(speaking);
      async.flushMicrotasks();
      body(async, controller, factory.last, player);
      controller.dispose();
      async.flushMicrotasks();
    });
  }

  test('plays hub audio and shows the reply', () {
    speak((async, controller, hub, player) {
      expect(controller.state, DisplayState.speaking);
      expect(controller.reply, reply);
      expect(player.played.single, mp3);
    });
  });

  test('stays speaking until playback completes', () {
    speak((async, controller, hub, player) {
      hub.push(idle);
      async.flushMicrotasks();
      expect(controller.state, DisplayState.speaking);
      expect(controller.reply, reply);

      player.finish();
      async.flushMicrotasks();
      expect(controller.state, DisplayState.idle);
    });
  });

  test('text-only reply follows hub idle without playback', () {
    speak((async, controller, hub, player) {
      expect(player.played, isEmpty);
      expect(controller.reply, reply);
      hub.push(idle);
      async.flushMicrotasks();
      expect(controller.state, DisplayState.idle);
    }, audio: null);
  });

  test('watchdog does not cut a long playback', () {
    speak((async, controller, hub, player) {
      async.elapse(StateTiming.activeTimeout * 2);
      expect(controller.state, DisplayState.speaking);
      expect(player.stops, 0);

      player.finish();
      async.flushMicrotasks();
      expect(controller.state, DisplayState.idle);
    });
  });

  test('cancel stops playback', () {
    speak((async, controller, hub, player) {
      controller.cancel();
      async.flushMicrotasks();
      expect(player.stops, 1);
      expect(controller.state, DisplayState.idle);
    });
  });

  test('touch stops playback', () {
    speak((async, controller, hub, player) {
      controller.touch();
      async.flushMicrotasks();
      expect(player.isPlaying, isFalse);
      expect(player.stops, 1);
    });
  });

  test('a new turn stops playback', () {
    speak((async, controller, hub, player) {
      controller.listen();
      async.flushMicrotasks();
      expect(controller.state, DisplayState.listening);
      expect(player.stops, 1);
    });

    speak((async, controller, hub, player) {
      controller.sendText('bật đèn');
      async.flushMicrotasks();
      expect(controller.state, DisplayState.thinking);
      expect(player.stops, 1);
    });
  });

  test('dispose releases the player', () {
    late FakeTtsPlayer released;
    speak((async, controller, hub, player) => released = player);
    expect(released.disposed, isTrue);
  });
}
