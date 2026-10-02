import 'on_this_day.dart';
import 'photo_manifest.dart';

abstract final class _Text {
  static const String intro = 'Ảnh gia đình đang hiển thị trên màn hình:';
  static const String caption = 'chú thích';
  static const String place = 'chụp ở';
  static const String date = 'ngày chụp';
  static const String people = 'có';
  static const String yearsAgo = 'năm trước';
  static const String outro =
      'Nếu được hỏi về bức ảnh này, hãy trả lời dựa trên các thông tin '
      'trên; thông tin nào không có thì nói là chưa biết.';
  static const String gap = '; ';
  static const String listGap = ', ';
  static const String fieldGap = ': ';
  static const String dateSep = '/';
  static const int datePad = 2;
}

/// Words that mean the question is about the picture on screen.
abstract final class PhotoQuestion {
  static const List<String> keywords = [
    'ảnh',
    'hình này',
    'hình đó',
    'bức',
    'tấm này',
    'tấm đó',
    'chụp',
    'photo',
    'picture',
  ];

  static bool matches(String text) {
    final lower = text.toLowerCase();
    return keywords.any(lower.contains);
  }
}

/// Gemini context for the photo on screen; empty when it has no
/// metadata worth sharing.
String photoContext(
  FamilyPhoto photo,
  DateTime today, {
  String Function(String memberId)? nameOf,
}) {
  final takenAt = photo.takenAt;
  final names = [for (final id in photo.people) nameOf?.call(id) ?? id];
  final fields = [
    if (photo.caption.isNotEmpty) _field(_Text.caption, photo.caption),
    if (photo.place.isNotEmpty) _field(_Text.place, photo.place),
    if (takenAt != null) _field(_Text.date, _date(takenAt, today)),
    if (names.isNotEmpty) _field(_Text.people, names.join(_Text.listGap)),
  ];
  if (!photo.hasDetails && takenAt == null) {
    return '';
  }
  return '${_Text.intro} ${fields.join(_Text.gap)}. ${_Text.outro}';
}

String _field(String name, String value) => '$name${_Text.fieldGap}$value';

String _date(DateTime takenAt, DateTime today) {
  String pad(int value) => value.toString().padLeft(_Text.datePad, '0');
  final date =
      '${pad(takenAt.day)}${_Text.dateSep}${pad(takenAt.month)}'
      '${_Text.dateSep}${takenAt.year}';
  final years = OnThisDay.yearsAgo(takenAt, today);
  return years == null ? date : '$date ($years ${_Text.yearsAgo})';
}
