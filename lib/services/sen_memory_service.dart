import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';

import '../core/members/member_profile.dart';
import '../core/pack/sen_pack.dart';
import '../core/skills/sen_skill.dart';

/// Kind of remembered fact; [name] is the stored value.
enum FactCategory { preference, habit, goal, taboo }

abstract final class SenMemoryLimits {
  /// Keeps the injected block well under 300 tokens.
  static const int maxPromptChars = 600;
  static const int maxFacts = 6;
}

/// Mem0-lite: per-member facts and skill progress, rendered as a short
/// block for Gemini's system instruction.
abstract interface class SenMemoryService {
  /// Empty for an unknown member.
  Future<String> buildMemoryPrompt(String memberId);

  /// Same text for the same member is stored once.
  Future<void> addFact(String memberId, FactCategory category, String fact);

  Future<void> recordSkill(
    String memberId,
    SkillKind skill,
    SkillOutcome outcome,
  );

  /// Replaces profiles and pack facts with the knowledge pack's; facts
  /// learned in conversation are kept.
  Future<void> applyMembers(List<MemberPack> members);
}

abstract final class _Table {
  static const String members = 'members';
  static const String facts = 'facts';
  static const String progress = 'skill_progress';
}

abstract final class _Col {
  static const String id = 'id';
  static const String name = 'name';
  static const String role = 'role';
  static const String englishLevel = 'english_level';
  static const String memberId = 'member_id';
  static const String category = 'category';
  static const String fact = 'fact';
  static const String createdAt = 'created_at';
  static const String skill = 'skill';
  static const String score = 'score';
  static const String level = 'level';
  static const String data = 'data';
  static const String updatedAt = 'updated_at';
  static const String plays = 'plays';
  static const String source = 'source';
}

/// Where a fact came from; [name] is the stored value, null for chat.
enum _Source { pack }

abstract final class _Prompt {
  static const String talkingTo = 'Đang nói chuyện với:';
  static const String facts = 'Sở thích/thói quen:';
  static const String progress = 'Tiến độ kỹ năng:';
  static const String none = 'chưa có';
  static const String factGap = '; ';
  static const String score = 'điểm';
  static const String plays = 'lượt';
  static const String ellipsis = '…';
}

final class SqfliteSenMemoryService implements SenMemoryService {
  SqfliteSenMemoryService({
    required String path,
    DatabaseFactory? factory,
    DateTime Function()? clock,
  }) : _path = path,
       _factory = factory ?? databaseFactory,
       _clock = clock ?? DateTime.now;

  static const String fileName = 'sen_memory.db';
  static const int _schemaVersion = 2;
  static const int _sourceVersion = 2;

  /// First memories of Bố Thức.
  static const List<(String, FactCategory, String)> _seeds = [
    (MemberId.thuc, FactCategory.preference, 'Thích uống cà phê ít đường'),
    (MemberId.thuc, FactCategory.preference, 'Thích công nghệ và AI'),
  ];

  final String _path;
  final DatabaseFactory _factory;
  final DateTime Function() _clock;
  Future<Database>? _db;

  /// On-device database in the app's databases folder.
  static Future<SqfliteSenMemoryService> device() async {
    return SqfliteSenMemoryService(
      path: '${await getDatabasesPath()}/$fileName',
    );
  }

  Future<Database> get _open {
    return _db ??= _factory.openDatabase(
      _path,
      options: OpenDatabaseOptions(
        version: _schemaVersion,
        onCreate: _create,
        onUpgrade: _upgrade,
        onOpen: _syncMembers,
      ),
    );
  }

  Future<void> close() async {
    final db = _db;
    _db = null;
    await (await db)?.close();
  }

  Future<void> _create(Database db, int version) async {
    await db.execute(
      'CREATE TABLE ${_Table.members}(${_Col.id} TEXT PRIMARY KEY, '
      '${_Col.name} TEXT, ${_Col.role} TEXT, ${_Col.englishLevel} TEXT)',
    );
    await db.execute(
      'CREATE TABLE ${_Table.facts}(${_Col.id} TEXT PRIMARY KEY, '
      '${_Col.memberId} TEXT, ${_Col.category} TEXT, ${_Col.fact} TEXT, '
      '${_Col.createdAt} INTEGER, ${_Col.source} TEXT)',
    );
    await db.execute(
      'CREATE TABLE ${_Table.progress}(${_Col.id} TEXT PRIMARY KEY, '
      '${_Col.memberId} TEXT, ${_Col.skill} TEXT, ${_Col.score} INTEGER, '
      '${_Col.level} TEXT, ${_Col.data} TEXT, ${_Col.updatedAt} INTEGER)',
    );
    for (final (member, category, fact) in _seeds) {
      await _insertFact(db, member, category, fact);
    }
  }

  Future<void> _upgrade(Database db, int from, int to) async {
    if (from < _sourceVersion) {
      await db.execute(
        'ALTER TABLE ${_Table.facts} ADD COLUMN ${_Col.source} TEXT',
      );
    }
  }

  /// Profiles live in code; the table mirrors them for joins and export.
  Future<void> _syncMembers(Database db) async {
    final batch = db.batch();
    for (final member in MemberProfile.family) {
      batch.insert(_Table.members, {
        _Col.id: member.id,
        _Col.name: member.name,
        _Col.role: member.role,
        _Col.englishLevel: member.englishLevel.name,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  @override
  Future<void> addFact(
    String memberId,
    FactCategory category,
    String fact,
  ) async {
    final text = fact.trim();
    if (text.isEmpty) {
      return;
    }
    await _insertFact(await _open, memberId, category, text);
  }

  Future<void> _insertFact(
    DatabaseExecutor db,
    String memberId,
    FactCategory category,
    String fact, {
    _Source? source,
  }) {
    final key = utf8.encode('$memberId|${fact.toLowerCase()}');
    return db.insert(_Table.facts, {
      _Col.id: sha1.convert(key).toString(),
      _Col.memberId: memberId,
      _Col.category: category.name,
      _Col.fact: fact,
      _Col.createdAt: _clock().millisecondsSinceEpoch,
      _Col.source: source?.name,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  @override
  Future<void> applyMembers(List<MemberPack> members) async {
    final db = await _open;
    await db.transaction((txn) async {
      await txn.delete(
        _Table.facts,
        where: '${_Col.source} = ?',
        whereArgs: [_Source.pack.name],
      );
      for (final member in members) {
        await _applyMember(txn, member);
      }
    });
  }

  Future<void> _applyMember(Transaction txn, MemberPack member) async {
    await txn.insert(_Table.members, {
      _Col.id: member.id,
      _Col.name: member.name,
      _Col.role: member.roleLabel,
      _Col.englishLevel: member.englishLevel.name,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    final facts = [
      for (final fact in member.facts) (FactCategory.preference, fact),
      for (final goal in member.goals) (FactCategory.goal, goal),
      for (final taboo in member.taboos) (FactCategory.taboo, taboo),
    ];
    for (final (category, fact) in facts) {
      await _insertFact(txn, member.id, category, fact, source: _Source.pack);
    }
  }

  @override
  Future<void> recordSkill(
    String memberId,
    SkillKind skill,
    SkillOutcome outcome,
  ) async {
    final db = await _open;
    final id = '$memberId:${skill.name}';
    await db.transaction((txn) async {
      final rows = await txn.query(
        _Table.progress,
        where: '${_Col.id} = ?',
        whereArgs: [id],
      );
      final row = rows.isEmpty ? null : rows.first;
      final gained = outcome == SkillOutcome.correct ? 1 : 0;
      await txn.insert(_Table.progress, {
        _Col.id: id,
        _Col.memberId: memberId,
        _Col.skill: skill.name,
        _Col.score: _int(row?[_Col.score]) + gained,
        _Col.level: MemberProfile.byId(memberId).englishLevel.name,
        _Col.data: jsonEncode({_Col.plays: _plays(row) + 1}),
        _Col.updatedAt: _clock().millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  @override
  Future<String> buildMemoryPrompt(String memberId) async {
    final db = await _open;
    final members = await db.query(
      _Table.members,
      where: '${_Col.id} = ?',
      whereArgs: [memberId],
    );
    if (members.isEmpty) {
      return '';
    }
    final member = members.first;
    final facts = await db.query(
      _Table.facts,
      columns: [_Col.fact],
      where: '${_Col.memberId} = ?',
      whereArgs: [memberId],
      orderBy: '${_Col.createdAt} DESC',
      limit: SenMemoryLimits.maxFacts,
    );
    final progress = await db.query(
      _Table.progress,
      where: '${_Col.memberId} = ?',
      whereArgs: [memberId],
      orderBy: _Col.skill,
    );
    final prompt =
        '${_Prompt.talkingTo} ${member[_Col.name]} (${member[_Col.role]}). '
        '${_Prompt.facts} ${_join([for (final f in facts) '${f[_Col.fact]}'])}. '
        '${_Prompt.progress} ${_join(_progressLines(progress))}.';
    return _clip(prompt);
  }

  static List<String> _progressLines(List<Map<String, Object?>> rows) {
    final kinds = SkillKind.values.asNameMap();
    return [
      for (final row in rows)
        if (kinds[row[_Col.skill]] case final kind?)
          '${kind.label}: ${_int(row[_Col.score])} ${_Prompt.score} / '
              '${_plays(row)} ${_Prompt.plays}',
    ];
  }

  static String _join(List<String> items) {
    return items.isEmpty ? _Prompt.none : items.join(_Prompt.factGap);
  }

  static String _clip(String prompt) {
    if (prompt.length <= SenMemoryLimits.maxPromptChars) {
      return prompt;
    }
    final end = SenMemoryLimits.maxPromptChars - _Prompt.ellipsis.length;
    return '${prompt.substring(0, end)}${_Prompt.ellipsis}';
  }

  static int _int(Object? value) => value is int ? value : 0;

  static int _plays(Map<String, Object?>? row) {
    final raw = row?[_Col.data];
    if (raw is! String) {
      return 0;
    }
    try {
      final data = jsonDecode(raw);
      return data is Map<String, dynamic> ? _int(data[_Col.plays]) : 0;
    } on FormatException {
      return 0;
    }
  }
}
