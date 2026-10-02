import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_display/core/photos/photo_frame.dart';
import 'package:hermes_display/services/photo_manifest_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/photo_fixture.dart';

void main() {
  const deck = ['https://picsum.photos/a', 'https://picsum.photos/b'];
  late SharedPreferences prefs;
  late List<Uri> requests;
  late DateTime now;
  late bool online;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    requests = [];
    now = photoToday;
    online = true;
  });

  PhotoManifestService manifests({String body = photoManifestJson}) {
    return PhotoManifestService(
      prefs: prefs,
      client: MockClient((request) async {
        requests.add(request.url);
        if (!online) {
          throw http.ClientException('offline');
        }
        return http.Response.bytes(utf8.encode(body), 200);
      }),
    );
  }

  PhotoFrame frame({
    PhotoManifestService? service,
    FakePhotoCache? cache,
    List<String> placeholders = deck,
  }) {
    return PhotoFrame(
      manifests: service ?? manifests(),
      cache: cache,
      deck: placeholders,
      clock: () => now,
      random: Random(7),
    );
  }

  List<String> ids(PhotoFrame frame) => [for (final p in frame.order) p.id];

  test('without a manifest URL the placeholder deck plays', () async {
    final photos = frame();
    await photos.boot('');
    expect(photos.showsFamily, isFalse);
    expect(photos.current, isNull);
    expect(photos.describe(), isEmpty);
    final first = photos.slide;
    expect(first.photo, isNotNull);
    expect(first.url.toString(), startsWith('https://picsum.photos/'));
    expect(first.memory, isNull);
    photos.advance();
    expect(photos.slide.photo!.id, isNot(first.photo!.id));
    expect(photos.slide.serial, first.serial + 1);
    expect(requests, isEmpty);
  });

  test('no deck and no manifest: an empty slide (gradient)', () async {
    final photos = frame(placeholders: const []);
    await photos.boot('');
    expect(photos.slide.photo, isNull);
    photos.advance();
    expect(photos.slide.photo, isNull);
  });

  test('manifest replaces the deck, memories first with a badge', () async {
    final photos = frame()..setMember('be');
    await photos.boot(photoManifestUrl);
    expect(requests.single, Uri.parse(photoManifestUrl));
    expect(photos.showsFamily, isTrue);
    expect(ids(photos).take(3), ['zoo', 'beach', 'bday']);
    expect(photos.current!.id, 'zoo');
    expect(photos.slide.memory, 'Ngày này 3 năm trước (2023): Bé Na đi sở thú');
    expect(photos.describe(), contains('Thảo Cầm Viên'));
    photos.advance();
    expect(photos.current!.id, 'beach');
    expect(photos.slide.memory, 'Ngày này 4 năm trước (2022)');
    photos.advance();
    expect(photos.current!.id, 'bday');
    expect(photos.slide.memory, isNull);
  });

  test('switching member promotes their photos from the next slide', () async {
    final photos = frame()..setMember('be');
    await photos.boot(photoManifestUrl);
    final shown = photos.slide;
    photos.setMember('thuc');
    expect(photos.slide, same(shown));
    expect(ids(photos)[2], 'dalat');
    photos.advance();
    expect(photos.current!.id, 'beach', reason: 'zoo is on screen already');
    photos.advance();
    expect(photos.current!.id, 'dalat');
    photos.setMember('thuc');
    expect(ids(photos)[2], 'dalat');
  });

  test('boots offline from the cached manifest', () async {
    await frame().boot(photoManifestUrl);
    online = false;
    final photos = frame();
    await photos.boot(photoManifestUrl);
    expect(requests, hasLength(2));
    expect(photos.showsFamily, isTrue);
    expect(photos.current!.id, 'zoo');
  });

  test('photos are shown from the disk cache, next one prefetched', () async {
    final cache = FakePhotoCache();
    final photos = frame(cache: cache)..setMember('be');
    var notified = 0;
    photos.addListener(() => notified++);
    await photos.boot(photoManifestUrl);
    expect(photos.slide.url, isNull);
    await pumpEventQueue();
    expect(photos.slide.file!.path, '/cache/zoo.webp');
    // The deck fills in until the first manifest arrives.
    expect(cache.fetched.map((u) => u.pathSegments.last), [
      'a',
      'b',
      'zoo.webp',
      'beach.webp',
    ]);
    expect(notified, greaterThanOrEqualTo(2));
    photos.advance();
    expect(photos.slide.file!.path, '/cache/beach.webp');
  });

  test('photos that fail to download are skipped', () async {
    final cache = FakePhotoCache(offline: {'zoo.webp'});
    final photos = frame(cache: cache)..setMember('be');
    await photos.boot(photoManifestUrl);
    await pumpEventQueue();
    expect(photos.current!.id, 'beach');
    for (var i = 0; i < 6; i++) {
      photos.advance();
      await pumpEventQueue();
      expect(photos.current!.id, isNot('zoo'));
    }
  });

  test('all downloads failing settles on a gradient slide', () async {
    final cache = FakePhotoCache(
      offline: {
        'zoo.webp',
        'bday.webp',
        'dalat.webp',
        'beach.webp',
        'old.webp',
      },
    );
    final photos = frame(cache: cache);
    await photos.boot(photoManifestUrl);
    await pumpEventQueue();
    expect(photos.slide.photo, isNotNull);
    expect(photos.slide.file, isNull);
    expect(photos.slide.url, isNull);
    final fetched = cache.fetched.length;
    photos.advance();
    await pumpEventQueue();
    expect(cache.fetched, hasLength(fetched));
  });

  test('a new day reorders: no more memories', () async {
    final photos = frame()..setMember('be');
    await photos.boot(photoManifestUrl);
    now = DateTime(2026, 10, 3, 0, 1);
    photos.advance();
    expect(ids(photos).take(2).toSet(), {'zoo', 'bday'});
    expect(photos.slide.memory, isNull);
  });

  test('the manifest is re-checked once per refresh period', () async {
    final photos = frame();
    await photos.boot(photoManifestUrl);
    now = now.add(const Duration(minutes: 30));
    photos.advance();
    expect(requests, hasLength(1));
    now = now.add(const Duration(minutes: 31));
    photos.advance();
    photos.advance();
    await pumpEventQueue();
    expect(requests, hasLength(2));
  });

  test('clearing the URL goes back to the deck', () async {
    final photos = frame();
    await photos.boot(photoManifestUrl);
    await photos.boot('');
    expect(photos.showsFamily, isFalse);
    expect(photos.slide.photo!.id, startsWith('deck-'));
  });

  test('a refresh for an old URL is ignored', () async {
    final photos = frame();
    final pending = photos.boot(photoManifestUrl);
    await photos.boot('');
    await pending;
    expect(photos.showsFamily, isFalse);
  });

  test('no manifest service: the URL is ignored', () async {
    final photos = PhotoFrame(deck: deck, clock: () => now);
    await photos.boot(photoManifestUrl);
    expect(photos.showsFamily, isFalse);
    expect((await photos.refresh()).status, PhotoSync.failed);
  });

  test('cache results after dispose are dropped', () async {
    final photos = frame(cache: FakePhotoCache());
    await photos.boot(photoManifestUrl);
    photos.dispose();
    await pumpEventQueue();
  });
}
