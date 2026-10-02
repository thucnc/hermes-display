class ChatThread {
  const ChatThread({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    required this.memberId,
  });

  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String memberId;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
      'member_id': memberId,
    };
  }

  factory ChatThread.fromMap(Map<String, dynamic> map) {
    return ChatThread(
      id: map['id'] as String,
      title: map['title'] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
      memberId: map['member_id'] as String,
    );
  }
}

/// A single message inside a chat thread.
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.threadId,
    required this.role,
    required this.text,
    required this.timestamp,
  });

  final String id;
  final String threadId;
  final String role; // 'user' or 'assistant'
  final String text;
  final DateTime timestamp;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'thread_id': threadId,
      'role': role,
      'text': text,
      'timestamp': timestamp.millisecondsSinceEpoch,
    };
  }

  factory ChatMessage.fromMap(Map<String, dynamic> map) {
    return ChatMessage(
      id: map['id'] as String,
      threadId: map['thread_id'] as String,
      role: map['role'] as String,
      text: map['text'] as String,
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
    );
  }

  /// Builds conversational context string from recent messages.
  static String formatContext(List<ChatMessage> messages, {int maxMessages = 6}) {
    if (messages.isEmpty) return '';
    final slice = messages.length > maxMessages
        ? messages.sublist(messages.length - maxMessages)
        : messages;
    final buffer = StringBuffer('LỊCH SỬ CUỘC TRÒ CHUYỆN GẦN ĐÂY:\n');
    for (final m in slice) {
      final speaker = m.role == 'user' ? 'Người dùng' : 'Bé Sen';
      buffer.writeln('$speaker: ${m.text}');
    }
    buffer.writeln('Hãy tiếp tục cuộc trò chuyện dựa trên ngữ cảnh này một cách tự nhiên.');
    return buffer.toString();
  }
}
