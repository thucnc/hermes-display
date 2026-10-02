import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_display/core/photos/on_this_day.dart';
import 'package:hermes_display/core/photos/photo_context.dart';
import 'package:hermes_display/core/photos/photo_manifest.dart';
import 'package:hermes_display/core/photos/photo_playlist.dart';

import 'support/photo_fixture.dart';

void main() {
  final photos = PhotoManifest.tryParse(
    photoManifestJson,
    Uri.parse(photoManifestUrl),
  )!.photos;
  FamilyPhoto byId(String id) => photos.firstWhere((p) => p.id == id);

  group('OnThisDay.yearsAgo', () {
    test('same month and day in an earlier year', () {
      final today = DateTime(2026, 10, 2, 23, 59);
      expect(OnThisDay.yearsAgo(DateTime(2023, 10, 2, 0, 1), today), 3);
      expect(OnThisDay.yearsAgo(DateTime(2025, 10, 2), today), 1);
    });

    test('other days, this year and the future do not count', () {
      final today = DateTime(2026, 10, 2);
      expect(OnThisDay.yearsAgo(DateTime(2023, 10, 3), today), isNull);
      expect(OnThisDay.yearsAgo(DateTime(2023, 11, 2), today), isNull);
      expect(OnThisDay.yearsAgo(DateTime(2026, 10, 2, 7), today), isNull);
      expect(OnThisDay.yearsAgo(DateTime(2027, 10, 2), today), isNull);
    });

    test('29 February shows on the 28th in common years only', () {
      final leapPhoto = DateTime(2024, 2, 29);
      expect(OnThisDay.yearsAgo(leapPhoto, DateTime(2027, 2, 28)), 3);
      expect(OnThisDay.yearsAgo(leapPhoto, DateTime(2028, 2, 28)), isNull);
      expect(OnThisDay.yearsAgo(leapPhoto, DateTime(2028, 2, 29)), 4);
      expect(
        OnThisDay.yearsAgo(DateTime(2023, 2, 28), DateTime(2028, 2, 29)),
        isNull,
      );
    });

    test('photos without a date never match', () {
      expect(OnThisDay.of(byId('old'), photoToday), isNull);
      expect(OnThisDay.of(byId('zoo'), photoToday), 3);
    });
  });

  test('label reads like the brief, caption optional', () {
    expect(
      OnThisDay.label(byId('zoo'), 3),
      'Ngày này 3 năm trước (2023): Bé Na đi sở thú',
    );
    expect(OnThisDay.label(byId('beach'), 4), 'Ngày này 4 năm trước (2022)');
  });

  group('buildPlaylist', () {
    test('memories first (nearest year first), then member, then rest', () {
      final order = buildPlaylist(
        photos,
        memberId: 'be',
        today: photoToday,
        random: Random(1),
      );
      expect(order.map((p) => p.id).take(2), ['zoo', 'beach']);
      expect(order.map((p) => p.id).skip(2).first, 'bday');
      expect(order.map((p) => p.id).skip(3).toSet(), {'dalat', 'old'});
      expect(order, hasLength(photos.length));
    });

    test('another member promotes their own photos', () {
      final order = buildPlaylist(
        photos,
        memberId: 'thuc',
        today: photoToday,
        random: Random(2),
      );
      expect(order[2].id, 'dalat');
    });

    test('no memories on another day, members still first', () {
      final order = buildPlaylist(
        photos,
        memberId: 'be',
        today: DateTime(2026, 6, 1),
        random: Random(3),
      );
      expect(order.take(2).map((p) => p.id).toSet(), {'zoo', 'bday'});
      expect(order.skip(2).map((p) => p.id).toSet(), {'dalat', 'beach', 'old'});
    });

    test('empty input gives an empty playlist', () {
      expect(
        buildPlaylist(const [], memberId: 'be', today: photoToday),
        isEmpty,
      );
    });
  });

  group('photo context', () {
    test('describes caption, place, date, years ago and people', () {
      final context = photoContext(
        byId('zoo'),
        photoToday,
        nameOf: (id) => id == 'be' ? 'Bé Na' : id,
      );
      expect(context, contains('Bé Na đi sở thú'));
      expect(context, contains('chụp ở: Thảo Cầm Viên'));
      expect(context, contains('ngày chụp: 02/10/2023 (3 năm trước)'));
      expect(context, contains('có: Bé Na'));
    });

    test('ids are used when no names are given; no date, no years', () {
      final context = photoContext(byId('bday'), photoToday);
      expect(context, contains('có: be, me'));
      expect(context, contains('ngày chụp: 14/05/2024'));
      expect(context, isNot(contains('năm trước')));
    });

    test('nothing to say about a bare photo', () {
      expect(photoContext(byId('old'), photoToday), isEmpty);
    });

    test('photo questions are recognised', () {
      for (final text in [
        'Sen ơi, ảnh này chụp ở đâu?',
        'Bức này năm nào vậy',
        'Who is in this photo?',
        'Hình này ở đâu',
      ]) {
        expect(PhotoQuestion.matches(text), isTrue, reason: text);
      }
      for (final text in ['Hôm nay thời tiết thế nào', 'Kể chuyện đi']) {
        expect(PhotoQuestion.matches(text), isFalse, reason: text);
      }
    });
  });
}
