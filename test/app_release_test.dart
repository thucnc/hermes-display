import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_display/core/dimming/dim_schedule.dart';
import 'package:hermes_display/core/update/app_release.dart';

void main() {
  final sha = 'AB' * 32;

  String body(Map<String, Object?> overrides) {
    return jsonEncode({
      'versionCode': 5,
      'versionName': '0.5.2',
      'url': 'http://hub/api/app/apk/hermes-display-5.apk',
      'sha256': sha,
      'notes': 'Sửa lỗi',
      ...overrides,
    });
  }

  test('parses a complete release, hash lower-cased', () {
    final release = AppRelease.tryParse(body({}))!;
    expect(release.versionCode, 5);
    expect(release.versionName, '0.5.2');
    expect(release.sha256, 'ab' * 32);
    expect(release.notes, 'Sửa lỗi');
  });

  test('rejects unusable releases', () {
    for (final bad in [
      body({'versionCode': '5'}),
      body({'versionCode': 0}),
      body({'versionName': ''}),
      body({'url': ' '}),
      body({'sha256': null}),
      body({'sha256': 'abc'}),
      '[]',
      'not json',
    ]) {
      expect(AppRelease.tryParse(bad), isNull, reason: bad);
    }
  });

  test('only a higher versionCode is newer', () {
    final release = AppRelease.tryParse(body({}))!;
    expect(release.isNewerThan(const AppVersion(4, '0.5.1')), isTrue);
    expect(release.isNewerThan(const AppVersion(5, '0.5.2')), isFalse);
    expect(release.isNewerThan(const AppVersion(6, '0.6.0')), isFalse);
  });

  group('nightlyDue', () {
    const dim = DimSettings.defaults;
    final night = DateTime(2026, 10, 2, 23, 30);
    final day = DateTime(2026, 10, 2, 14);

    test('inside the window once per night', () {
      expect(nightlyDue(night, null, dim), isTrue);
      expect(nightlyDue(night, DateTime(2026, 10, 2, 9), dim), isTrue);
      expect(nightlyDue(night, DateTime(2026, 10, 2, 23), dim), isFalse);
      expect(
        nightlyDue(DateTime(2026, 10, 3, 5), DateTime(2026, 10, 2, 23), dim),
        isFalse,
      );
    });

    test('never during the day', () {
      expect(nightlyDue(day, null, dim), isFalse);
    });

    test('uses the window hours even with dimming off', () {
      expect(nightlyDue(night, null, dim.copyWith(enabled: false)), isTrue);
    });
  });
}
