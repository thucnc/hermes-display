import 'dart:convert';

import '../constants/app_constants.dart';
import '../dimming/dim_schedule.dart';

/// The installed build, as Android reports it.
final class AppVersion {
  const AppVersion(this.code, this.name);

  final int code;
  final String name;
}

/// One entry of `GET /api/app/latest`.
final class AppRelease {
  const AppRelease({
    required this.versionCode,
    required this.versionName,
    required this.url,
    required this.sha256,
    this.notes = '',
  });

  final int versionCode;
  final String versionName;

  /// Absolute, or relative to the endpoint it came from.
  final String url;

  /// Lower-case hex.
  final String sha256;
  final String notes;

  static final RegExp _hex = RegExp(r'^[0-9a-f]{64}$');

  /// Null unless every field is usable; a release without a hash is
  /// never installed.
  static AppRelease? tryParse(String body) {
    final Object? json;
    try {
      json = jsonDecode(body);
    } on FormatException {
      return null;
    }
    if (json is! Map<String, dynamic>) {
      return null;
    }
    final code = json[_Key.versionCode];
    final name = json[_Key.versionName];
    final url = json[_Key.url];
    final hash = json[_Key.sha256];
    if (code is! int || code <= 0 || name is! String || name.isEmpty) {
      return null;
    }
    if (url is! String || url.trim().isEmpty || hash is! String) {
      return null;
    }
    final sha = hash.trim().toLowerCase();
    if (!_hex.hasMatch(sha)) {
      return null;
    }
    final notes = json[_Key.notes];
    return AppRelease(
      versionCode: code,
      versionName: name,
      url: url.trim(),
      sha256: sha,
      notes: notes is String ? notes : '',
    );
  }

  bool isNewerThan(AppVersion installed) => versionCode > installed.code;
}

abstract final class _Key {
  static const String versionCode = 'versionCode';
  static const String versionName = 'versionName';
  static const String url = 'url';
  static const String sha256 = 'sha256';
  static const String notes = 'notes';
}

/// True inside the night dim hours (even with dimming switched off) when
/// no nightly check ran in the last [UpdateDefaults.nightlyGap]: one quiet
/// check per night.
bool nightlyDue(DateTime now, DateTime? lastCheck, DimSettings dim) {
  if (!inDimWindow(now, dim.copyWith(enabled: true))) {
    return false;
  }
  if (lastCheck == null) {
    return true;
  }
  return now.difference(lastCheck) >= UpdateDefaults.nightlyGap;
}
