import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_display/core/photos/photo_manifest.dart';

import 'support/photo_fixture.dart';

void main() {
  final base = Uri.parse(photoManifestUrl);

  test('parses the exporter manifest, resolving relative urls', () {
    final manifest = PhotoManifest.tryParse(photoManifestJson, base)!;
    expect(manifest.version, 'v1abc');
    expect(manifest.updatedAt, DateTime.utc(2026, 10, 1, 20));
    expect(manifest.photos.map((p) => p.id), [
      'zoo',
      'bday',
      'dalat',
      'beach',
      'old',
    ]);
    final zoo = manifest.photos.first;
    expect(
      zoo.url,
      Uri.parse('http://192.168.1.5:8901/api/photos/img/zoo.webp'),
    );
    expect(zoo.takenAt, DateTime(2023, 10, 2, 10));
    expect(zoo.caption, 'Bé Na đi sở thú');
    expect(zoo.place, 'Thảo Cầm Viên');
    expect(zoo.people, ['be']);
    expect(zoo.features('be'), isTrue);
    expect(zoo.features('thuc'), isFalse);
    expect(zoo.hasDetails, isTrue);
    expect(
      manifest.photos[2].url,
      Uri.parse('https://cdn.example.com/dalat.webp'),
    );
    final old = manifest.photos.last;
    expect(old.takenAt, isNull);
    expect(old.caption, isEmpty);
    expect(old.people, isEmpty);
    expect(old.hasDetails, isFalse);
  });

  test('offsets and snake_case are accepted, times become local', () {
    final manifest = PhotoManifest.tryParse('''
{"updated_at": "2026-10-01T00:00:00Z", "photos": [
  {"id": "a", "url": "a.webp", "taken_at": "2023-10-02T10:00:00+07:00",
   "people": ["be", "", 3, "  me "]}
]}''', base)!;
    final photo = manifest.photos.single;
    expect(photo.takenAt!.isUtc, isFalse);
    expect(photo.takenAt!.toUtc(), DateTime.utc(2023, 10, 2, 3));
    expect(photo.people, ['be', 'me']);
    expect(manifest.version, isEmpty);
    expect(manifest.updatedAt, DateTime.utc(2026, 10, 1));
  });

  test('bad entries and repeated ids are skipped', () {
    final manifest = PhotoManifest.tryParse('''
{"photos": [
  "nope", {"id": "", "url": "a.webp"}, {"id": "b"},
  {"id": "c", "url": "ftp://x/c.webp"}, {"id": "d", "url": "d.webp",
  "takenAt": "yesterday", "caption": 7}, {"id": "d", "url": "dup.webp"},
  {"id": "e", "url": "http://[bad"}
]}''', base)!;
    expect(manifest.photos.map((p) => p.id), ['d']);
    expect(manifest.photos.single.takenAt, isNull);
    expect(manifest.photos.single.caption, isEmpty);
    expect(manifest.photos.single.url.path, '/api/photos/d.webp');
  });

  test('rejects bodies without a usable photo', () {
    for (final body in [
      '',
      'not json',
      '[]',
      '{"photos": []}',
      '{"photos": "x"}',
      '{"photos": [{"id": "a"}]}',
    ]) {
      expect(PhotoManifest.tryParse(body, base), isNull, reason: body);
    }
  });
}
