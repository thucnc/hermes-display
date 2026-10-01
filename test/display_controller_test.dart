import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_display/core/constants/app_constants.dart';
import 'package:hermes_display/core/state/connection_status.dart';
import 'package:hermes_display/core/state/display_controller.dart';
import 'package:hermes_display/core/state/display_state.dart';
import 'package:hermes_display/services/hermes_websocket_client.dart';
import 'package:hermes_display/services/settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_transport.dart';

void main() {
  late SettingsService settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = await SettingsService.create();
  });

  DisplayController build(FakeTransportFactory factory) {
    return DisplayController(
      settingsService: settings,
      client: HermesWebSocketClient(transportFactory: factory.call),
    );
  }

  test('follows hub-driven voice loop', () {
    fakeAsync((async) {
      final factory = FakeTransportFactory();
      final controller = build(factory)..start();
      async.flushMicrotasks();
      expect(controller.connection, ConnectionStatus.connected);

      factory.last.push('{"type":"state","state":"listening"}');
      factory.last.push('{"type":"transcript","text":"mấy giờ rồi"}');
      async.flushMicrotasks();
      expect(controller.state, DisplayState.listening);
      expect(controller.transcript, 'mấy giờ rồi');

      factory.last.push('{"type":"state","state":"thinking"}');
      factory.last.push('{"type":"tts","text":"Bây giờ là 3 giờ"}');
      async.flushMicrotasks();
      expect(controller.state, DisplayState.speaking);
      expect(controller.reply, 'Bây giờ là 3 giờ');

      factory.last.push('{"type":"state","state":"idle"}');
      async.flushMicrotasks();
      expect(controller.state, DisplayState.idle);
      expect(controller.reply, isEmpty);
      controller.dispose();
    });
  });

  test('sendText goes to thinking only when online', () {
    fakeAsync((async) {
      final factory = FakeTransportFactory(fallback: FakeOutcome.reject);
      final controller = build(factory)..start();
      async.flushMicrotasks();
      expect(controller.sendText('hi'), SendResult.offline);
      expect(controller.sendText('   '), SendResult.empty);
      controller.dispose();
    });

    fakeAsync((async) {
      final factory = FakeTransportFactory();
      final controller = build(factory)..start();
      async.flushMicrotasks();
      expect(controller.sendText(' bật đèn '), SendResult.sent);
      expect(controller.state, DisplayState.thinking);
      expect(controller.transcript, 'bật đèn');
      expect(factory.last.sent.single, contains('text_input'));
      controller.dispose();
    });
  });

  test('watchdog and disconnect reset to idle', () {
    fakeAsync((async) {
      final factory = FakeTransportFactory();
      final controller = build(factory)..start();
      async.flushMicrotasks();

      controller.sendText('hello');
      async.elapse(StateTiming.activeTimeout);
      expect(controller.state, DisplayState.idle);

      controller.sendText('hello');
      factory.last.drop();
      async.flushMicrotasks();
      expect(controller.state, DisplayState.idle);
      expect(controller.connection, ConnectionStatus.disconnected);
      controller.dispose();
    });
  });

  test('applySettings persists and reconnects on address change', () {
    fakeAsync((async) {
      final factory = FakeTransportFactory();
      final controller = build(factory)..start();
      async.flushMicrotasks();

      controller.applySettings(
        controller.settings.copyWith(slideIntervalSec: 30),
      );
      async.flushMicrotasks();
      expect(factory.created, hasLength(1));

      controller.applySettings(controller.settings.copyWith(host: '10.0.0.5'));
      async.flushMicrotasks();
      expect(factory.created, hasLength(2));
      expect(factory.last.uri.host, '10.0.0.5');
      expect(settings.load().host, '10.0.0.5');
      controller.dispose();
    });
  });
}
