import 'dart:async';
import 'package:sqflite/sqflite.dart';
import '../core/chat/chat_thread.dart';

class ChatThreadService {
  ChatThreadService({Database? db}) : _db = db;

  Database? _db;

  Future<Database> _getDb() async {
    if (_db != null) return _db!;
    final dbPath = await getDatabasesPath();
    final path = '$dbPath/sen_chat.db';
    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE chat_threads (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            member_id TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE chat_messages (
            id TEXT PRIMARY KEY,
            thread_id TEXT NOT NULL,
            role TEXT NOT NULL,
            text TEXT NOT NULL,
            timestamp INTEGER NOT NULL,
            FOREIGN KEY (thread_id) REFERENCES chat_threads (id) ON DELETE CASCADE
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_messages_thread ON chat_messages(thread_id, timestamp)',
        );
      },
    );
    return _db!;
  }

  Future<ChatThread> createThread(String memberId, {String? initialTitle}) async {
    final db = await _getDb();
    final now = DateTime.now();
    final thread = ChatThread(
      id: 'thread_${now.millisecondsSinceEpoch}',
      title: initialTitle ?? 'Cuộc trò chuyện mới',
      createdAt: now,
      updatedAt: now,
      memberId: memberId,
    );
    await db.insert('chat_threads', thread.toMap());
    return thread;
  }

  Future<List<ChatThread>> listThreads({String? memberId}) async {
    final db = await _getDb();
    final List<Map<String, dynamic>> maps;
    if (memberId != null) {
      maps = await db.query(
        'chat_threads',
        where: 'member_id = ?',
        whereArgs: [memberId],
        orderBy: 'updated_at DESC',
      );
    } else {
      maps = await db.query('chat_threads', orderBy: 'updated_at DESC');
    }
    return maps.map(ChatThread.fromMap).toList();
  }

  Future<List<ChatMessage>> getMessages(String threadId) async {
    final db = await _getDb();
    final maps = await db.query(
      'chat_messages',
      where: 'thread_id = ?',
      whereArgs: [threadId],
      orderBy: 'timestamp ASC',
    );
    return maps.map(ChatMessage.fromMap).toList();
  }

  Future<void> addMessage({
    required String threadId,
    required String role,
    required String text,
    String? titleIfFirst,
  }) async {
    final db = await _getDb();
    final now = DateTime.now();
    final msg = ChatMessage(
      id: 'msg_${now.millisecondsSinceEpoch}_$role',
      threadId: threadId,
      role: role,
      text: text,
      timestamp: now,
    );
    await db.insert('chat_messages', msg.toMap());

    // Update thread updated_at and optionally title
    final updates = <String, dynamic>{
      'updated_at': now.millisecondsSinceEpoch,
    };
    if (titleIfFirst != null && titleIfFirst.isNotEmpty) {
      updates['title'] = titleIfFirst.length > 50
          ? '${titleIfFirst.substring(0, 47)}...'
          : titleIfFirst;
    }
    await db.update(
      'chat_threads',
      updates,
      where: 'id = ?',
      whereArgs: [threadId],
    );
  }

  Future<void> deleteThread(String threadId) async {
    final db = await _getDb();
    await db.delete('chat_messages', where: 'thread_id = ?', whereArgs: [threadId]);
    await db.delete('chat_threads', where: 'id = ?', whereArgs: [threadId]);
  }
}
