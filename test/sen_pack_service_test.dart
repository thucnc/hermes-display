import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_display/core/pack/sen_pack.dart';
import 'package:hermes_display/services/sen_pack_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_sen_memory.dart';
import 'support/sen_pack_fixture.dart';

class _BrokenMemory extends FakeSenMemoryService {
  @override
  Future<void> applyMembers(List<MemberPack> members) {
    throw Exception('disk full');
  }
}

void main() {
  const url = 'https://raw.githubusercontent.com/fam/sen/main/sen-pack.json';
  const etag = '"a1b2c3"';
  late SharedPreferences prefs;
  late FakeSenMemoryService memory;
  late List<http.Request> requests;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    memory = FakeSenMemoryService();
    requests = [];
  });

  SenPackService service(
    http.Response Function(http.Request) reply, {
    FakeSenMemoryService? memoryOverride,
  }) {
    return SenPackService(
      prefs: prefs,
      memory: memoryOverride ?? memory,
      client: MockClient((request) async {
        requests.add(request);
        return reply(request);
      }),
    );
  }

  http.Response ok(String body, {String? tag}) {
    return http.Response.bytes(utf8.encode(body), 200, headers: {'etag': ?tag});
  }

  test('downloads, applies members and caches the pack', () async {
    final result = await service(
      (_) => ok(senPackJson, tag: etag),
    ).fetchAndApply(' $url ');
    expect(result.status, PackSync.updated);
    expect(result.pack!.members, hasLength(3));
    expect(requests.single.url, Uri.parse(url));
    expect(requests.single.headers, isNot(contains('if-none-match')));
    expect(memory.applied.single.map((m) => m.id), ['thuc', 'be', 'ong']);
  });

  test('works offline from the cache after one sync', () async {
    await service((_) => ok(senPackJson)).fetchAndApply(url);
    memory.applied.clear();

    final offline = service((_) => throw http.ClientException('no wifi'));
    final cached = await offline.loadCached();
    expect(cached!.version, 'a1b2c3d4e5f6');
    expect(memory.applied.single, hasLength(3));

    final retry = await offline.fetchAndApply(url);
    expect(retry.status, PackSync.failed);
    expect(retry.pack!.version, 'a1b2c3d4e5f6');
  });

  test('no cache: loadCached is null', () async {
    expect(await service((_) => ok(senPackJson)).loadCached(), isNull);
    expect(memory.applied, isEmpty);
  });

  test('sends the ETag back; 304 is unchanged', () async {
    await service((_) => ok(senPackJson, tag: etag)).fetchAndApply(url);
    memory.applied.clear();

    final result = await service(
      (_) => http.Response('', 304),
    ).fetchAndApply(url);
    expect(requests.last.headers['if-none-match'], etag);
    expect(result.status, PackSync.unchanged);
    expect(result.pack!.members, hasLength(3));
    expect(memory.applied, isEmpty);
  });

  test('same hash is unchanged and not re-applied', () async {
    await service((_) => ok(senPackJson)).fetchAndApply(url);
    memory.applied.clear();
    final reordered = jsonEncode(jsonDecode(senPackJson));

    final result = await service((_) => ok(reordered)).fetchAndApply(url);
    expect(result.status, PackSync.unchanged);
    expect(memory.applied, isEmpty);
  });

  test('a new version replaces the cache', () async {
    await service((_) => ok(senPackJson)).fetchAndApply(url);
    final next = jsonDecode(senPackJson) as Map<String, dynamic>
      ..['version'] = 'v2'
      ..['hash'] = 'h2'
      ..['members'] = [
        {'id': 'me', 'name': 'Mẹ'},
      ];

    final result = await service(
      (_) => ok(jsonEncode(next)),
    ).fetchAndApply(url);
    expect(result.status, PackSync.updated);
    expect((await service((_) => ok('')).loadCached())!.version, 'v2');
    expect(memory.applied.last.single.id, 'me');
  });

  test('bad URLs are invalid without a request', () async {
    final pack = service((_) => ok(senPackJson));
    for (final bad in ['', 'not a url', 'ftp://x/y.json', '/sen-pack.json']) {
      expect((await pack.fetchAndApply(bad)).status, PackSync.invalid);
    }
    expect(requests, isEmpty);
  });

  test('a bad body is invalid and keeps the cached pack', () async {
    await service((_) => ok(senPackJson)).fetchAndApply(url);
    for (final body in ['<html>', '[]', '{}']) {
      final result = await service((_) => ok(body)).fetchAndApply(url);
      expect(result.status, PackSync.invalid, reason: body);
      expect(result.pack!.version, 'a1b2c3d4e5f6');
    }
    final invalidUtf8 = await service(
      (_) => http.Response.bytes([0xff, 0xfe], 200),
    ).fetchAndApply(url);
    expect(invalidUtf8.status, PackSync.invalid);
  });

  test('HTTP errors and timeouts-as-exceptions fail', () async {
    for (final reply in <http.Response Function(http.Request)>[
      (_) => http.Response('nope', 404),
      (_) => http.Response('', 304),
      (_) => throw http.ClientException('down'),
    ]) {
      final result = await service(reply).fetchAndApply(url);
      expect(result.status, PackSync.failed);
      expect(result.pack, isNull);
    }
  });

  test('a memory failure fails the sync and caches nothing', () async {
    final result = await service(
      (_) => ok(senPackJson),
      memoryOverride: _BrokenMemory(),
    ).fetchAndApply(url);
    expect(result.status, PackSync.failed);
    expect(await service((_) => ok('')).loadCached(), isNull);
  });

  test('loadCached survives a broken memory database', () async {
    await service((_) => ok(senPackJson)).fetchAndApply(url);
    final cached = await service(
      (_) => ok(''),
      memoryOverride: _BrokenMemory(),
    ).loadCached();
    expect(cached, isNotNull);
  });

  test('parseUrl accepts only absolute http(s) URLs', () {
    expect(
      SenPackService.parseUrl('http://192.168.1.5:8901/api/sen/pack'),
      isNotNull,
    );
    expect(SenPackService.parseUrl('https://gist.github.com/x'), isNotNull);
    expect(SenPackService.parseUrl('file:///sdcard/pack.json'), isNull);
    expect(SenPackService.parseUrl('http://'), isNull);
  });
}
