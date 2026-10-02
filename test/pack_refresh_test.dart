import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_display/core/constants/app_constants.dart';
import 'package:hermes_display/core/state/display_controller.dart';
import 'package:hermes_display/services/hermes_websocket_client.dart';
import 'package:hermes_display/services/sen_pack_service.dart';
import 'package:hermes_display/services/settings_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_sen_memory.dart';
import 'support/fake_transport.dart';
import 'support/sen_pack_fixture.dart';

void main() {
  const url = 'http://192.168.1.5:8901/api/sen/pack';
  late SharedPreferences prefs;
  late FakeTransportFactory transports;
  late List<Uri> requests;

  Future<void> init({String packUrl = url}) async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    await SettingsService(
      prefs,
    ).save(HubSettings.defaults.copyWith(knowledgePackUrl: packUrl));
  }

  DisplayController build() {
    transports = FakeTransportFactory();
    requests = [];
    final host = MockClient((request) async {
      requests.add(request.url);
      return http.Response.bytes(utf8.encode(senPackJson), 200);
    });
    return DisplayController(
      settingsService: SettingsService(prefs),
      client: HermesWebSocketClient(transportFactory: transports.call),
      pack: SenPackService(
        prefs: prefs,
        memory: FakeSenMemoryService(),
        client: host,
      ),
    )..start();
  }

  test('refreshes every 30 minutes after boot', () async {
    await init();
    fakeAsync((async) {
      final controller = build();
      async.flushMicrotasks();
      expect(requests, hasLength(1));
      async.elapse(SenPackDefaults.refreshEvery - const Duration(seconds: 1));
      expect(requests, hasLength(1));
      async.elapse(const Duration(seconds: 1));
      expect(requests, hasLength(2));
      async.elapse(SenPackDefaults.refreshEvery);
      expect(requests, hasLength(3));
      controller.dispose();
      async.elapse(SenPackDefaults.refreshEvery);
      expect(requests, hasLength(3));
    });
  });

  test('hub pack_updated push fetches right away', () async {
    await init();
    fakeAsync((async) {
      final controller = build();
      async.flushMicrotasks();
      transports.last.push('{"type":"pack_updated","hash":"b"}');
      async.flushMicrotasks();
      expect(requests, hasLength(2));
      expect(requests.last, Uri.parse(url));
      controller.dispose();
    });
  });

  test(
    'ambient wake refreshes; overlapping triggers share one fetch',
    () async {
      await init();
      fakeAsync((async) {
        final controller = build();
        async.flushMicrotasks();
        controller.onAmbientWake();
        controller.onAmbientWake();
        transports.last.push('{"type":"pack_updated"}');
        async.flushMicrotasks();
        expect(requests, hasLength(2));
        controller.dispose();
      });
    },
  );

  test('no URL: timer, wake and push stay offline', () async {
    await init(packUrl: '');
    fakeAsync((async) {
      final controller = build();
      async.flushMicrotasks();
      controller.onAmbientWake();
      transports.last.push('{"type":"pack_updated"}');
      async.elapse(SenPackDefaults.refreshEvery);
      expect(requests, isEmpty);
      controller.dispose();
    });
  });
}
