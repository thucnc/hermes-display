import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_display/core/members/member_profile.dart';
import 'package:hermes_display/core/pack/sen_pack.dart';
import 'package:hermes_display/core/pack/sen_pack_registry.dart';

import 'support/sen_pack_fixture.dart';

void main() {
  final pack = SenPack.tryParse(senPackJson)!;
  final now = DateTime(2026, 10, 2);

  group('SenPack parsing', () {
    test('reads version, members, skills and rituals', () {
      expect(pack.version, 'a1b2c3d4e5f6');
      expect(pack.updatedAt, '2026-10-02T09:00:00Z');
      expect(pack.members.map((m) => m.id), ['thuc', 'be', 'ong']);
      expect(pack.skills.map((s) => s.id), ['bedtime-story', 'quiz', 'garden']);
      expect(pack.rituals.single.schedule, '19:30');
    });

    test('accepts camelCase and snake_case fields', () {
      final [thuc, be, _] = pack.members;
      expect(thuc.englishLevel, EnglishLevel.intermediate);
      expect(thuc.callMe, 'Bố Thức ơi');
      expect(be.englishLevel, EnglishLevel.beginner);
      expect(be.callMe, 'Na ơi');
      expect(be.birthday, DateTime(2020, 5, 14));
      expect(be.goals, ['Tự giác dọn đồ chơi trước khi đi ngủ.']);
      expect(be.taboos, hasLength(1));
    });

    test('missing fields get safe defaults', () {
      final ong = pack.members.last;
      expect(ong.englishLevel, EnglishLevel.beginner);
      expect(ong.facts, isEmpty);
      expect(ong.birthday, isNull);
      expect(ong.avatarInitial, 'N');
      expect(pack.skills.first.status, PackStatus.draft);
      expect(pack.rituals.single.status, PackStatus.active);
    });

    test('drops malformed entries, keeps the rest', () {
      final parsed = SenPack.tryParse(
        jsonEncode({
          'version': 7,
          'members': [
            {'id': 'a', 'name': 'An'},
            {'id': '', 'name': 'Nameless'},
            {'name': 'No id'},
            'not a map',
          ],
          'skills': [
            {'id': 's', 'prompt': 'p'},
            {'id': 't', 'triggers': 'not a list', 'prompt': 'p'},
          ],
          'rituals': 'nope',
        }),
      )!;
      expect(parsed.version, '7');
      expect(parsed.members.map((m) => m.id), ['a']);
      expect(parsed.skills, isEmpty);
      expect(parsed.rituals, isEmpty);
    });

    test('rejects non-JSON, non-objects and empty packs', () {
      for (final raw in [
        'oops',
        '[1, 2]',
        '"text"',
        '{}',
        '{"members": [], "skills": []}',
        '{"members": [{"id": ""}]}',
      ]) {
        expect(SenPack.tryParse(raw), isNull, reason: raw);
      }
    });

    test('toJson round-trips', () {
      final again = SenPack.tryParse(jsonEncode(pack.toJson()))!;
      expect(jsonEncode(again.toJson()), jsonEncode(pack.toJson()));
      expect(again.sameContent(pack), isTrue);
      expect(const SenPack().sameContent(const SenPack()), isFalse);
    });
  });

  group('MemberPack', () {
    test('maps to a profile with a family role label', () {
      final profile = pack.members[1].toProfile();
      expect(profile.id, 'be');
      expect(profile.name, 'Bé Na');
      expect(profile.role, 'Con');
      expect(profile.initial, 'N');
      expect(profile.englishLevel, EnglishLevel.beginner);
      expect(pack.members.last.toProfile().role, 'Ông');
    });

    test('age counts whole years', () {
      final be = pack.members[1];
      expect(be.ageOn(DateTime(2026, 5, 13)), 5);
      expect(be.ageOn(DateTime(2026, 5, 14)), 6);
      expect(be.ageOn(now), 6);
      expect(pack.members.first.ageOn(now), isNull);
    });

    test('fills prompt placeholders', () {
      final text = pack.skills.first.instruction(pack.members[1].vars(now));
      expect(text, 'Kể chuyện cho Bé Na (6 tuổi), chúc Na ơi.');
      expect(fillVars('{{member.unknown}}', const {}), '{{member.unknown}}');
    });
  });

  group('SkillPack and RitualPack matching', () {
    test('triggers are case-insensitive and filtered by member', () {
      final story = pack.skills.first;
      expect(story.matches('Sen ơi KỂ CHUYỆN đi', 'be'), isTrue);
      expect(story.matches('kể chuyện', 'thuc'), isFalse);
      expect(story.matches('hôm nay trời đẹp', 'be'), isFalse);
    });

    test('paused entries never match', () {
      expect(pack.skills.last.matches('làm vườn', 'be'), isFalse);
    });

    test('ritual instruction lists questions and rules', () {
      final ritual = pack.rituals.single;
      expect(ritual.matches('chuyện bữa tối nào', 'thuc'), isTrue);
      expect(ritual.instruction, contains('Bữa tối Family Check-in'));
      expect(ritual.instruction, contains('Điều vui nhất hôm nay là gì?'));
      expect(ritual.instruction, contains('- Không hỏi về điểm số.'));
    });
  });

  group('SenPackRegistry', () {
    test('built-in family until a pack is loaded', () {
      final registry = SenPackRegistry();
      expect(registry.members, MemberProfile.family);
      expect(registry.byId('ghost'), MemberProfile.thuc);
      expect(registry.instructionFor('kể chuyện', MemberProfile.be, now), '');
    });

    test('pack members replace the family; unknown ids fall back', () {
      final registry = SenPackRegistry()..load(pack);
      expect(registry.members.map((m) => m.id), ['thuc', 'be', 'ong']);
      expect(registry.has('ong'), isTrue);
      expect(registry.has('me'), isFalse);
      expect(registry.byId('ong').name, 'Ông Nội');
      expect(registry.byId('ghost').id, 'thuc');
    });

    test('a pack without members keeps the built-in family', () {
      final registry = SenPackRegistry()..load(SenPack(skills: pack.skills));
      expect(registry.members, MemberProfile.family);
    });

    test('dynamic skill and ritual instructions, built-ins skipped', () {
      final registry = SenPackRegistry()..load(pack);
      final be = registry.byId('be');
      expect(
        registry.instructionFor('kể chuyện đi', be, now),
        'Kể chuyện cho Bé Na (6 tuổi), chúc Na ơi.',
      );
      expect(registry.instructionFor('đố vui đi', be, now), '');
      final both = registry.instructionFor('kể chuyện bữa tối', be, now);
      expect(both, startsWith('Kể chuyện cho Bé Na'));
      expect(both, contains('Nghi thức gia đình: Bữa tối Family Check-in.'));
    });
  });
}
