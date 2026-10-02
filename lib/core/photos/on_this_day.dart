import 'photo_manifest.dart';

abstract final class _Text {
  static const String prefix = 'Ngày này';
  static const String suffix = 'năm trước';
  static const String captionGap = ': ';
}

/// "Ngày này năm xưa": photos taken on today's month and day in an
/// earlier year.
abstract final class OnThisDay {
  static const int _february = 2;
  static const int _leapDay = 29;
  static const int _leapEve = 28;

  /// Whole years since [takenAt] when it shares today's month and day,
  /// else null. A 29 February photo counts on the 28th in common years.
  static int? yearsAgo(DateTime takenAt, DateTime today) {
    final years = today.year - takenAt.year;
    if (years <= 0 || takenAt.month != today.month) {
      return null;
    }
    if (takenAt.day == today.day || _leapFallback(takenAt, today)) {
      return years;
    }
    return null;
  }

  static int? of(FamilyPhoto photo, DateTime today) {
    final takenAt = photo.takenAt;
    return takenAt == null ? null : yearsAgo(takenAt, today);
  }

  /// "Ngày này 3 năm trước (2023)", plus ": caption" when there is one.
  static String label(FamilyPhoto photo, int years) {
    final year = photo.takenAt?.year;
    final when = year == null ? '' : ' ($year)';
    final head = '${_Text.prefix} $years ${_Text.suffix}$when';
    if (photo.caption.isEmpty) {
      return head;
    }
    return '$head${_Text.captionGap}${photo.caption}';
  }

  static bool _leapFallback(DateTime takenAt, DateTime today) {
    return takenAt.month == _february &&
        takenAt.day == _leapDay &&
        today.day == _leapEve &&
        !_isLeap(today.year);
  }

  static bool _isLeap(int year) {
    return DateTime(year, _february, _leapDay).day == _leapDay;
  }
}
