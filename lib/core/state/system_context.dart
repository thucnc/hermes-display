/// Formats real-time situational context for Gemini System Instruction.
abstract final class SystemContext {
  /// Builds live context: City, Current Time, Weekday, Part of Day, and Timezone.
  static String live(DateTime now, {String city = 'Hồ Chí Minh'}) {
    final weekdayStr = switch (now.weekday) {
      DateTime.monday => 'Thứ Hai',
      DateTime.tuesday => 'Thứ Ba',
      DateTime.wednesday => 'Thứ Tư',
      DateTime.thursday => 'Thứ Năm',
      DateTime.friday => 'Thứ Sáu',
      DateTime.saturday => 'Thứ Bảy',
      DateTime.sunday => 'Chủ Nhật',
      _ => '',
    };

    final partOfDay = switch (now.hour) {
      >= 5 && < 11 => 'buổi sáng',
      >= 11 && < 14 => 'buổi trưa',
      >= 14 && < 18 => 'buổi chiều',
      >= 18 && < 22 => 'buổi tối',
      _ => 'đêm muộn',
    };

    final hourStr = now.hour.toString().padLeft(2, '0');
    final minuteStr = now.minute.toString().padLeft(2, '0');
    final dateStr = '${now.day}/${now.month}/${now.year}';

    return 'NGỮ CẢNH HIỆN TẠI:\n'
        '- Địa điểm: Thành phố $city, Việt Nam (múi giờ GMT+7, Asia/Ho_Chi_Minh).\n'
        '- Thời gian thực: $hourStr:$minuteStr ($weekdayStr, ngày $dateStr, $partOfDay).\n'
        'Hãy lưu ý ngữ cảnh thời gian và địa điểm này để trả lời chính xác, chào hỏi hợp buổi và phù hợp với thực tế.';
  }
}
