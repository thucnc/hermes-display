import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_display/core/members/member_profile.dart';
import 'package:hermes_display/core/state/display_controller.dart';
import 'package:hermes_display/services/hermes_websocket_client.dart';
import 'package:hermes_display/services/sen_pack_service.dart';
import 'package:hermes_display/services/settings_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_gemini_service.dart';
import 'support/fake_sen_memory.dart';
import 'support/fake_transport.dart';
import 'support/sen_pack_fixture.dart';

void main() {
  const url = 'http://192.168.1.5:8901/api/sen/pack';
  const cacheKey = 'sen_pack_json';
  late SharedPreferences prefs;
  late FakeGeminiService gemini;
  late FakeSenMemoryService memory;
  late List<Uri> requests;

  Future<void> init(Map<String, Object> values, {String packUrl = ''}) async {
    SharedPreferences.setMockInitialValues(values);
    prefs = await SharedPreferences.getInstance();
    await SettingsService(prefs).save(
      HubSettings.defaults.copyWith(
        geminiApiKey: 'key',
        knowledgePackUrl: packUrl,
      ),
    );
  }

  setUp(() => init({}));

  DisplayController build({String body = senPackJson, bool withPack = true}) {
    gemini = FakeGeminiService();
    memory = FakeSenMemoryService();
    requests = [];
    final host = MockClient((request) async {
      requests.add(request.url);
      return http.Response.bytes(utf8.encode(body), 200);
    });
    return DisplayController(
      settingsService: SettingsService(prefs),
      client: HermesWebSocketClient(
        transportFactory: FakeTransportFactory().call,
      ),
      gemini: gemini,
      memory: memory,
      pack: withPack
          ? SenPackService(prefs: prefs, memory: memory, client: host)
          : null,
    )..start();
  }

  test('without a pack the built-in family is used', () {
    fakeAsync((async) {
      final controller = build(withPack: false);
      async.flushMicrotasks();
      expect(controller.members, MemberProfile.family);
      controller.dispose();
    });
  });

  test('boots offline from the cached pack, no URL no request', () async {
    await init({cacheKey: senPackJson});
    fakeAsync((async) {
      final controller = build();
      async.flushMicrotasks();
      expect(controller.members.map((m) => m.name), [
        'Bố Thức',
        'Bé Na',
        'Ông Nội',
      ]);
      expect(memory.applied.single, hasLength(3));
      expect(requests, isEmpty);
      controller.dispose();
    });
  });

  test('boot refreshes from the configured URL', () async {
    await init({}, packUrl: url);
    fakeAsync((async) {
      final controller = build();
      var notified = 0;
      controller.addListener(() => notified++);
      async.flushMicrotasks();
      expect(requests.single, Uri.parse(url));
      expect(controller.members.last.id, 'ong');
      expect(notified, greaterThan(0));
      controller.dispose();
    });
  });

  test('a pack skill prompt goes to Gemini, built-ins stay', () async {
    await init({cacheKey: senPackJson});
    fakeAsync((async) {
      final controller = build();
      async.flushMicrotasks();
      controller.selectMember('be');
      async.flushMicrotasks();

      controller.sendText('Sen ơi kể chuyện đi');
      async.flushMicrotasks();
      expect(gemini.contexts.single, contains('Kể chuyện cho Bé Na'));
      expect(gemini.contexts.single, contains('chúc Na ơi'));
      gemini.answer('Ngày xửa ngày xưa…');
      async.flushMicrotasks();

      controller.sendText('đố vui đi');
      async.flushMicrotasks();
      expect(gemini.contexts.last, contains('"options"'));
      expect(gemini.contexts.last, isNot(contains('pack quiz')));
      controller.dispose();
    });
  });

  test('a pack-only member can be selected and survives restart', () async {
    await init({cacheKey: senPackJson});
    fakeAsync((async) {
      final controller = build();
      async.flushMicrotasks();
      controller.selectMember('ong');
      async.flushMicrotasks();
      expect(controller.member.name, 'Ông Nội');
      controller.selectMember('me');
      expect(controller.member.id, 'ong');
      controller.dispose();

      final restarted = build();
      async.flushMicrotasks();
      expect(restarted.member.name, 'Ông Nội');
      restarted.dispose();
    });
  });

  test('syncPack applies an update; failures keep the family', () async {
    await init({});
    fakeAsync((async) {
      final controller = build(body: 'oops');
      async.flushMicrotasks();
      PackSyncResult? result;
      controller.syncPack(url).then((r) => result = r);
      async.flushMicrotasks();
      expect(result!.status, PackSync.invalid);
      expect(controller.members, MemberProfile.family);
      controller.dispose();

      final offline = build(withPack: false);
      offline.syncPack(url).then((r) => result = r);
      async.flushMicrotasks();
      expect(result!.status, PackSync.failed);
      offline.dispose();
    });
  });
}
