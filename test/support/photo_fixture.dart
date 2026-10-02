import 'dart:io';

import 'package:hermes_display/services/photo_cache.dart';

const String photoManifestUrl = 'http://192.168.1.5:8901/api/photos/manifest';

/// "Today" for every photo test: 2 October 2026, local time.
final DateTime photoToday = DateTime(2026, 10, 2, 9);

/// Local times (no offset) so results do not depend on the machine TZ.
const String photoManifestJson = '''
{
  "version": "v1abc",
  "updatedAt": "2026-10-01T20:00:00Z",
  "photos": [
    {"id": "zoo", "url": "img/zoo.webp", "takenAt": "2023-10-02T10:00:00",
     "caption": "Bé Na đi sở thú", "place": "Thảo Cầm Viên",
     "people": ["be"]},
    {"id": "bday", "url": "img/bday.webp", "takenAt": "2024-05-14T18:00:00",
     "caption": "Sinh nhật Bé Na", "people": ["be", "me"]},
    {"id": "dalat", "url": "https://cdn.example.com/dalat.webp",
     "takenAt": "2025-01-01T08:00:00", "caption": "Bố đi Đà Lạt",
     "people": ["thuc"]},
    {"id": "beach", "url": "img/beach.webp", "takenAt": "2022-10-02T16:00:00",
     "people": []},
    {"id": "old", "url": "img/old.webp"}
  ]
}
''';

/// Disk cache stand-in: files for [cached] urls, null for the rest.
class FakePhotoCache implements PhotoCache {
  FakePhotoCache({Set<String>? offline}) : offline = offline ?? {};

  /// Photo file names (last url segment) whose download fails.
  final Set<String> offline;
  final List<Uri> fetched = [];

  @override
  int get maxBytes => 0;

  @override
  Future<File?> fetch(Uri url) async {
    fetched.add(url);
    if (offline.contains(url.pathSegments.last)) {
      return null;
    }
    return File('/cache/${url.pathSegments.last}');
  }
}
