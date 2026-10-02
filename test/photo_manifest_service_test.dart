import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_display/services/photo_manifest_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/photo_fixture.dart';

void main() {
  const etag = '"v1abc"';
  late SharedPreferences prefs;
  late List<http.Request> requests;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    requests = [];
  });

  PhotoManifestService service(http.Response Function(http.Request) reply) {
    return PhotoManifestService(
      prefs: prefs,
      client: MockClient((request) async {
        requests.add(request);
        return reply(request);
      }),
    );
  }

  http.Response ok(String body, {String? tag}) {
    return http.Response.bytes(utf8.encode(body), 200, headers: {'etag': ?tag});
  }

  test('downloads and caches the manifest for its URL', () async {
    final photos = service((_) => ok(photoManifestJson, tag: etag));
    final result = await photos.fetch(' $photoManifestUrl ');
    expect(result.status, PhotoSync.updated);
    expect(result.manifest!.photos, hasLength(5));
    expect(requests.single.url, Uri.parse(photoManifestUrl));
    expect(requests.single.headers, isNot(contains('if-none-match')));
    expect(photos.loadCached(photoManifestUrl)!.version, 'v1abc');
  });

  test('ETag makes the next fetch conditional; 304 keeps the cache', () async {
    await service(
      (_) => ok(photoManifestJson, tag: etag),
    ).fetch(photoManifestUrl);
    final again = await service(
      (_) => http.Response('', 304),
    ).fetch(photoManifestUrl);
    expect(requests.last.headers['if-none-match'], etag);
    expect(again.status, PhotoSync.unchanged);
    expect(again.manifest!.version, 'v1abc');
  });

  test('same body without ETag is unchanged', () async {
    await service((_) => ok(photoManifestJson)).fetch(photoManifestUrl);
    final again = await service(
      (_) => ok(photoManifestJson),
    ).fetch(photoManifestUrl);
    expect(again.status, PhotoSync.unchanged);
  });

  test('offline and HTTP errors fall back to the cache', () async {
    await service((_) => ok(photoManifestJson)).fetch(photoManifestUrl);
    final offline = await service(
      (_) => throw http.ClientException('no wifi'),
    ).fetch(photoManifestUrl);
    expect(offline.status, PhotoSync.failed);
    expect(offline.manifest!.photos, hasLength(5));
    final down = await service(
      (_) => http.Response('', 500),
    ).fetch(photoManifestUrl);
    expect(down.status, PhotoSync.failed);
    expect(down.manifest, isNotNull);
  });

  test('a broken export never replaces the cache', () async {
    await service((_) => ok(photoManifestJson)).fetch(photoManifestUrl);
    for (final body in ['{"photos": []}', 'oops']) {
      final bad = await service((_) => ok(body)).fetch(photoManifestUrl);
      expect(bad.status, PhotoSync.invalid);
      expect(bad.manifest!.version, 'v1abc');
    }
    final latin = await service(
      (_) => http.Response.bytes([0xff, 0xfe], 200),
    ).fetch(photoManifestUrl);
    expect(latin.status, PhotoSync.invalid);
    expect(service((_) => ok('')).loadCached(photoManifestUrl), isNotNull);
  });

  test('cache belongs to one URL; 304 without cache is a failure', () async {
    await service(
      (_) => ok(photoManifestJson, tag: etag),
    ).fetch(photoManifestUrl);
    const other = 'https://photos.example.com/photos.json';
    final photos = service((_) => http.Response('', 304));
    expect(photos.loadCached(other), isNull);
    final result = await photos.fetch(other);
    expect(requests.last.headers, isNot(contains('if-none-match')));
    expect(result.status, PhotoSync.failed);
    expect(result.manifest, isNull);
  });

  test('invalid URLs are rejected without a request', () async {
    final photos = service((_) => ok(photoManifestJson));
    for (final url in ['', 'photos.json', 'ftp://x/p.json', 'http://']) {
      expect(PhotoManifestService.parseUrl(url), isNull, reason: url);
      expect((await photos.fetch(url)).status, PhotoSync.invalid);
      expect(photos.loadCached(url), isNull);
    }
    expect(requests, isEmpty);
  });
}
