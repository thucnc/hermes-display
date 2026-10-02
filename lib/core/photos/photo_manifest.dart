import 'dart:convert';

abstract final class _Key {
  static const String version = 'version';
  static const String updatedAt = 'updatedAt';
  static const String updatedAtSnake = 'updated_at';
  static const String photos = 'photos';
  static const String id = 'id';
  static const String url = 'url';
  static const String takenAt = 'takenAt';
  static const String takenAtSnake = 'taken_at';
  static const String caption = 'caption';
  static const String place = 'place';
  static const String people = 'people';
}

String _str(Object? value) => value is String ? value.trim() : '';

DateTime? _date(Object? value) => DateTime.tryParse(_str(value));

/// One family photo from `photos.json`.
class FamilyPhoto {
  const FamilyPhoto({
    required this.id,
    required this.url,
    this.takenAt,
    this.caption = '',
    this.place = '',
    this.people = const [],
  });

  final String id;

  /// Absolute; relative manifest urls are resolved against the manifest.
  final Uri url;

  /// Capture moment, local time; null when the exporter had no date.
  final DateTime? takenAt;
  final String caption;
  final String place;

  /// Member ids seen in the photo, e.g. `be`.
  final List<String> people;

  bool features(String memberId) => people.contains(memberId);

  /// Something Sen can talk about beyond the pixels.
  bool get hasDetails => caption.isNotEmpty || place.isNotEmpty;

  /// Null without an id or a usable http(s) url.
  static FamilyPhoto? fromJson(Map<String, dynamic> json, Uri base) {
    final id = _str(json[_Key.id]);
    final raw = _str(json[_Key.url]);
    if (id.isEmpty || raw.isEmpty) {
      return null;
    }
    final Uri url;
    try {
      url = base.resolve(raw);
    } on FormatException {
      return null;
    }
    if (url.host.isEmpty || !PhotoManifest.schemes.contains(url.scheme)) {
      return null;
    }
    final people = json[_Key.people];
    return FamilyPhoto(
      id: id,
      url: url,
      takenAt: (_date(json[_Key.takenAt]) ?? _date(json[_Key.takenAtSnake]))
          ?.toLocal(),
      caption: _str(json[_Key.caption]),
      place: _str(json[_Key.place]),
      people: people is List
          ? [
              for (final person in people)
                if (_str(person).isNotEmpty) _str(person),
            ]
          : const [],
    );
  }
}

/// `photos.json` written by `tools/export_photos.py` (or by hand).
class PhotoManifest {
  const PhotoManifest({
    required this.version,
    required this.photos,
    this.updatedAt,
  });

  static const List<String> schemes = ['http', 'https'];

  final String version;
  final DateTime? updatedAt;
  final List<FamilyPhoto> photos;

  /// Lenient: bad entries and repeated ids are skipped. Null when the
  /// body is not JSON or has no usable photo, so a broken export never
  /// replaces a good cache.
  static PhotoManifest? tryParse(String body, Uri base) {
    final Object? json;
    try {
      json = jsonDecode(body);
    } on FormatException {
      return null;
    }
    if (json is! Map<String, dynamic>) {
      return null;
    }
    final photos = _photos(json[_Key.photos], base);
    if (photos.isEmpty) {
      return null;
    }
    return PhotoManifest(
      version: _str(json[_Key.version]),
      updatedAt:
          _date(json[_Key.updatedAt]) ?? _date(json[_Key.updatedAtSnake]),
      photos: photos,
    );
  }

  static List<FamilyPhoto> _photos(Object? raw, Uri base) {
    if (raw is! List) {
      return const [];
    }
    final seen = <String>{};
    final photos = <FamilyPhoto>[];
    for (final item in raw) {
      if (item is! Map<String, dynamic>) {
        continue;
      }
      final photo = FamilyPhoto.fromJson(item, base);
      if (photo == null || !seen.add(photo.id)) {
        continue;
      }
      photos.add(photo);
    }
    return photos;
  }
}
