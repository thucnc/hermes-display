/// Detects when the user intends to end/stop the conversation.
abstract final class FarewellIntent {
  /// Patterns indicating a goodbye, stop or dismissal.
  static final RegExp _pattern = RegExp(
    r'(?:'
    r'tạm biệt|'
    r'hẹn gặp lại|'
    r'bye\s*bye|'
    r'bye\s*bạn|'
    r'bye\s*em|'
    r'cảm ơn\s*(?:em|sen|bạn)?\s*(?:nhé|nha|nghen|nhiều)?|'
    r'thôi\s*(?:được rồi|nha|nhé|nghỉ đi|dừng lại|dừng|ko cần nữa|không cần nữa)|'
    r'xong rồi\s*(?:nhé|nha)?|'
    r'nghỉ đi\s*(?:nhé|nha|em|sen)?|'
    r'dừng lại\s*(?:nhé|nha|đi)?|'
    r'không có gì\s*(?:nữa đâu|nữa)|'
    r'hết rồi\s*(?:nhé|nha)?'
    r')',
    caseSensitive: false,
  );

  /// Checks if [text] is primarily a farewell/ending statement.
  /// If the user says "Cảm ơn em, mai trời có mưa không?" -> false (it has a question).
  /// If the user says "Thôi được rồi, cảm ơn em nhé!" -> true.
  static bool matches(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;

    // If it contains a question mark, usually it's asking something
    if (trimmed.endsWith('?') || trimmed.contains('không?') || trimmed.contains('sao?')) {
      return false;
    }

    final hasFarewell = _pattern.hasMatch(trimmed);
    if (!hasFarewell) return false;

    // Check length: farewells are short utterances (< 40 chars)
    if (trimmed.length > 50) return false;

    return true;
  }
}
