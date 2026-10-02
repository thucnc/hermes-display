import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_display/core/constants/app_constants.dart';
import 'package:hermes_display/core/media/rich_content.dart';
import 'package:hermes_display/core/state/brain_mode.dart';
import 'package:hermes_display/core/state/connection_status.dart';
import 'package:hermes_display/core/state/display_controller.dart';
import 'package:hermes_display/core/state/display_state.dart';
import 'package:hermes_display/services/hermes_sync_service.dart';
import 'package:hermes_display/services/hermes_websocket_client.dart';
import 'package:hermes_display/services/settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_gemini_service.dart';
import 'support/fake_sync.dart';
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

  group('gemini brain', () {
    const recipe =
        'Trứng chiên:\n1. Đập trứng.\n2. Chiên vàng.\n'
        '[Video](https://youtu.be/abcdefghijk)';
    late FakeGeminiService gemini;
    late FakeSync sync;
    late FakeLinks links;

    DisplayController buildGemini(FakeTransportFactory factory) {
      gemini = FakeGeminiService();
      sync = FakeSync();
      links = FakeLinks();
      return DisplayController(
        settingsService: settings,
        client: HermesWebSocketClient(transportFactory: factory.call),
        gemini: gemini,
        sync: sync,
        links: links,
      );
    }

    setUp(() async {
      await settings.save(HubSettings.defaults.copyWith(geminiApiKey: 'key'));
    });

    test('typed turn goes to Gemini even while the hub is down', () {
      fakeAsync((async) {
        final factory = FakeTransportFactory(fallback: FakeOutcome.reject);
        final controller = buildGemini(factory)..start();
        async.flushMicrotasks();

        expect(controller.sendText(' trứng chiên '), SendResult.sent);
        expect(controller.state, DisplayState.thinking);
        expect(gemini.prompts.single, 'trứng chiên');
        expect(gemini.keys.single, 'key');

        gemini.answer(recipe);
        async.flushMicrotasks();
        expect(controller.state, DisplayState.speaking);
        expect(controller.reply, recipe);
        expect(controller.rich?.steps, hasLength(2));
        expect(controller.rich?.video?.id, 'abcdefghijk');
        controller.dispose();
      });
    });

    test('rich card outlives idle, clears on next turn and dismiss', () {
      fakeAsync((async) {
        final controller = buildGemini(FakeTransportFactory())..start();
        async.flushMicrotasks();
        controller.sendText('trứng');
        gemini.answer(recipe);
        async.flushMicrotasks();

        async.elapse(StateTiming.activeTimeout);
        expect(controller.state, DisplayState.idle);
        expect(controller.rich, isNotNull);

        controller.sendText('khác');
        expect(controller.rich, isNull);
        gemini.answer(recipe);
        async.flushMicrotasks();
        controller.dismissRich();
        expect(controller.rich, isNull);
        controller.dispose();
      });
    });

    test('cancelled turn drops its late answer', () {
      fakeAsync((async) {
        final controller = buildGemini(FakeTransportFactory())..start();
        async.flushMicrotasks();
        controller.sendText('trứng');
        controller.cancel();
        gemini.answer(recipe);
        async.flushMicrotasks();
        expect(controller.state, DisplayState.idle);
        expect(controller.rich, isNull);
        controller.dispose();
      });
    });

    test('Gemini failure records the error and idles', () {
      fakeAsync((async) {
        final controller = buildGemini(FakeTransportFactory())..start();
        async.flushMicrotasks();
        controller.sendText('trứng');
        gemini.fail('quota');
        async.flushMicrotasks();
        expect(controller.state, DisplayState.idle);
        expect(controller.lastError, 'quota');
        controller.dispose();
      });
    });

    test('hub brain is used when selected', () {
      fakeAsync((async) {
        final factory = FakeTransportFactory();
        final controller = buildGemini(factory)..start();
        async.flushMicrotasks();
        controller.applySettings(
          controller.settings.copyWith(brainMode: BrainMode.hub),
        );
        async.flushMicrotasks();
        controller.sendText('bật đèn');
        expect(gemini.prompts, isEmpty);
        expect(factory.last.sent.single, contains('text_input'));
        controller.dispose();
      });
    });

    test('hub replies with steps also get a rich card', () {
      fakeAsync((async) {
        final factory = FakeTransportFactory();
        final controller = buildGemini(factory)..start();
        async.flushMicrotasks();
        controller.applySettings(
          controller.settings.copyWith(brainMode: BrainMode.hub),
        );
        async.flushMicrotasks();
        factory.last.push('{"type":"state","state":"thinking"}');
        factory.last.push(
          '{"type":"tts","text":"1. Đập trứng.\\n2. Chiên vàng."}',
        );
        async.flushMicrotasks();
        expect(controller.rich?.steps, hasLength(2));
        controller.dispose();
      });
    });

    test('saveRich posts the note to the hub; openVideo launches', () {
      fakeAsync((async) {
        final controller = buildGemini(FakeTransportFactory())..start();
        async.flushMicrotasks();
        SaveResult? result;
        controller.saveRich().then((r) => result = r);
        async.flushMicrotasks();
        expect(result, SaveResult.failed);

        controller.sendText('Cách làm trứng chiên');
        gemini.answer(recipe);
        async.flushMicrotasks();
        controller.saveRich().then((r) => result = r);
        async.flushMicrotasks();
        expect(result, SaveResult.saved);
        final (uri, note) = sync.saved.single;
        expect(uri.toString(), 'http://localhost:8900/save');
        expect(note.title, 'Cách làm trứng chiên');
        expect(note.category, NoteCategory.recipes);

        controller.openVideo(controller.rich!.video!);
        async.flushMicrotasks();
        expect(
          links.opened.single.toString(),
          'https://www.youtube.com/watch?v=abcdefghijk',
        );
        controller.dispose();
      });
    });
  });
}
