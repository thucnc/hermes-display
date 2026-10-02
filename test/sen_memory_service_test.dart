import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_display/core/pack/sen_pack.dart';
import 'package:hermes_display/core/skills/sen_skill.dart';
import 'package:hermes_display/services/sen_memory_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late SqfliteSenMemoryService memory;
  var now = DateTime(2026, 10, 2, 9);

  setUpAll(sqfliteFfiInit);

  setUp(() {
    now = DateTime(2026, 10, 2, 9);
    memory = SqfliteSenMemoryService(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
      clock: () => now,
    );
  });

  tearDown(() => memory.close());

  test('seeds Bố Thức with his coffee and tech facts', () async {
    final prompt = await memory.buildMemoryPrompt('thuc');
    expect(prompt, startsWith('Đang nói chuyện với: Bố Thức (Bố).'));
    expect(prompt, contains('Thích uống cà phê ít đường'));
    expect(prompt, contains('Thích công nghệ và AI'));
    expect(prompt, endsWith('Tiến độ kỹ năng: chưa có.'));
  });

  test('other members start without facts; unknown member is blank', () async {
    expect(
      await memory.buildMemoryPrompt('be'),
      'Đang nói chuyện với: Bé (Con). Sở thích/thói quen: chưa có. '
      'Tiến độ kỹ năng: chưa có.',
    );
    expect(await memory.buildMemoryPrompt('ghost'), isEmpty);
  });

  test('facts are per member, newest first and de-duplicated', () async {
    await memory.addFact('me', FactCategory.preference, 'Thích hoa hồng');
    now = now.add(const Duration(minutes: 1));
    await memory.addFact('me', FactCategory.habit, 'Tập yoga buổi sáng');
    await memory.addFact('me', FactCategory.habit, ' tập yoga buổi sáng ');
    final prompt = await memory.buildMemoryPrompt('me');
    expect(
      prompt,
      contains('Sở thích/thói quen: Tập yoga buổi sáng; Thích hoa hồng.'),
    );
    expect(await memory.buildMemoryPrompt('be'), contains('chưa có'));
  });

  test('skill progress accumulates score and plays', () async {
    await memory.recordSkill('be', SkillKind.quiz, SkillOutcome.correct);
    await memory.recordSkill('be', SkillKind.quiz, SkillOutcome.wrong);
    await memory.recordSkill('be', SkillKind.quiz, SkillOutcome.correct);
    await memory.recordSkill('be', SkillKind.english, SkillOutcome.practiced);
    final prompt = await memory.buildMemoryPrompt('be');
    expect(prompt, contains('Đố vui: 2 điểm / 3 lượt'));
    expect(prompt, contains('Tiếng Anh: 0 điểm / 1 lượt'));
    expect(await memory.buildMemoryPrompt('me'), contains('chưa có.'));
  });

  test('prompt stays short however many facts exist', () async {
    for (var i = 0; i < 40; i++) {
      now = now.add(const Duration(seconds: 1));
      await memory.addFact(
        'thuc',
        FactCategory.preference,
        'Sở thích số $i khá dài để kiểm tra giới hạn độ dài của bộ nhớ',
      );
    }
    final prompt = await memory.buildMemoryPrompt('thuc');
    expect(prompt.length, lessThanOrEqualTo(SenMemoryLimits.maxPromptChars));
    expect(prompt, contains('Sở thích số 39'));
    expect(prompt, isNot(contains('Sở thích số 0 ')));
  });

  group('knowledge pack members', () {
    const na = MemberPack(
      id: 'be',
      name: 'Bé Na',
      role: 'child',
      facts: ['Thích khủng long tím'],
      goals: ['Tự dọn đồ chơi'],
      taboos: ['Không hứa mua đồ chơi'],
    );

    test('profiles and facts reach the prompt', () async {
      await memory.applyMembers(const [
        na,
        MemberPack(id: 'ong', name: 'Ông Nội', role: 'grandfather'),
      ]);
      final prompt = await memory.buildMemoryPrompt('be');
      expect(prompt, startsWith('Đang nói chuyện với: Bé Na (Con).'));
      expect(prompt, contains('Thích khủng long tím'));
      expect(prompt, contains('Tự dọn đồ chơi'));
      expect(prompt, contains('Không hứa mua đồ chơi'));
      expect(
        await memory.buildMemoryPrompt('ong'),
        startsWith('Đang nói chuyện với: Ông Nội (Ông).'),
      );
    });

    test('a new pack replaces pack facts, chat facts stay', () async {
      await memory.addFact('be', FactCategory.habit, 'Ngủ trưa lúc 12 giờ');
      await memory.applyMembers(const [na]);
      await memory.applyMembers(const [
        MemberPack(id: 'be', name: 'Bé Na', facts: ['Thích mèo']),
      ]);
      final prompt = await memory.buildMemoryPrompt('be');
      expect(prompt, contains('Thích mèo'));
      expect(prompt, contains('Ngủ trưa lúc 12 giờ'));
      expect(prompt, isNot(contains('khủng long')));
      expect(prompt, isNot(contains('Tự dọn đồ chơi')));
    });
  });

  test('upgrades a version 1 database and keeps its facts', () async {
    final dir = await Directory.systemTemp.createTemp('sen_memory');
    final path = '${dir.path}/v1.db';
    final old = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE members(id TEXT PRIMARY KEY, name TEXT, role TEXT, '
            'english_level TEXT)',
          );
          await db.execute(
            'CREATE TABLE facts(id TEXT PRIMARY KEY, member_id TEXT, '
            'category TEXT, fact TEXT, created_at INTEGER)',
          );
          await db.execute(
            'CREATE TABLE skill_progress(id TEXT PRIMARY KEY, member_id TEXT, '
            'skill TEXT, score INTEGER, level TEXT, data TEXT, '
            'updated_at INTEGER)',
          );
          await db.insert('facts', {
            'id': 'x',
            'member_id': 'thuc',
            'category': 'habit',
            'fact': 'Chạy bộ buổi sáng',
            'created_at': 1,
          });
        },
      ),
    );
    await old.close();

    final upgraded = SqfliteSenMemoryService(
      path: path,
      factory: databaseFactoryFfi,
      clock: () => now,
    );
    await upgraded.applyMembers(const [
      MemberPack(id: 'thuc', name: 'Bố Thức', facts: ['Thích AI']),
    ]);
    final prompt = await upgraded.buildMemoryPrompt('thuc');
    expect(prompt, contains('Chạy bộ buổi sáng'));
    expect(prompt, contains('Thích AI'));
    await upgraded.close();
    await dir.delete(recursive: true);
  });
}
