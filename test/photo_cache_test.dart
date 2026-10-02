import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_display/services/photo_cache.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late Directory root;
  late List<Uri> requests;
  late bool online;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('photo_cache_test');
    requests = [];
    online = true;
  });

  tearDown(() => root.delete(recursive: true));

  PhotoCache cache({int maxBytes = 1000, int size = 300}) {
    return PhotoCache(
      root: () async => root,
      maxBytes: maxBytes,
      client: MockClient((request) async {
        requests.add(request.url);
        if (!online) {
          throw http.ClientException('offline');
        }
        if (request.url.path.endsWith('missing.webp')) {
          return http.Response('', 404);
        }
        return http.Response.bytes(List.filled(size, 7), 200);
      }),
    );
  }

  Uri photo(String name) => Uri.parse('http://hub:8901/api/photos/img/$name');

  Future<List<String>> files() async {
    final dir = Directory('${root.path}/photo_cache');
    return [await for (final f in dir.list()) f.path];
  }

  test('downloads once, then serves from disk even offline', () async {
    final photos = cache();
    final first = await photos.fetch(photo('a.webp'));
    expect(first!.lengthSync(), 300);
    expect(first.path, startsWith('${root.path}/photo_cache/'));
    online = false;
    final again = await photos.fetch(photo('a.webp'));
    expect(again!.path, first.path);
    expect(requests, hasLength(1));
    final rebooted = await cache().fetch(photo('a.webp'));
    expect(rebooted!.path, first.path);
    expect(requests, hasLength(1));
  });

  test('concurrent fetches share one download', () async {
    final photos = cache();
    final results = await Future.wait([
      photos.fetch(photo('a.webp')),
      photos.fetch(photo('a.webp')),
    ]);
    expect(results[0]!.path, results[1]!.path);
    expect(requests, hasLength(1));
  });

  test('offline, HTTP errors and oversized photos give null', () async {
    online = false;
    expect(await cache().fetch(photo('a.webp')), isNull);
    online = true;
    expect(await cache().fetch(photo('missing.webp')), isNull);
    expect(await cache(maxBytes: 100).fetch(photo('big.webp')), isNull);
    expect(await files(), isEmpty);
  });

  test('evicts least recently shown photos past the cap', () async {
    final photos = cache();
    final a = await photos.fetch(photo('a.webp'));
    await a!.setLastModified(DateTime(2020));
    final b = await photos.fetch(photo('b.webp'));
    await b!.setLastModified(DateTime(2021));
    final c = await photos.fetch(photo('c.webp'));
    await c!.setLastModified(DateTime(2022));
    // Showing a again makes it the most recent; b is now the oldest.
    await photos.fetch(photo('a.webp'));
    final d = await photos.fetch(photo('d.webp'));
    final kept = await files();
    expect(kept, hasLength(3));
    expect(kept, containsAll([a.path, c.path, d!.path]));
    expect(kept, isNot(contains(b.path)));
  });

  test('a storage failure gives null instead of throwing', () async {
    final photos = PhotoCache(
      root: () async => throw const FileSystemException('no disk'),
      client: MockClient((_) async => http.Response('x', 200)),
    );
    expect(await photos.fetch(photo('a.webp')), isNull);
  });
}
