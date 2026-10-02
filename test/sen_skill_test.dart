import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_display/core/members/member_profile.dart';
import 'package:hermes_display/core/skills/sen_skill.dart';
import 'package:hermes_display/core/skills/skill_content.dart';

void main() {
  const quizJson = '''```json
{"question": "Con vật nào biết bay?", "options": ["A. Chó", "B) Chim", "Mèo", "Cá"], "answer": "B", "explain": "Chim có cánh."}
```''';
  const roleplayJson =
      '''{"scenario": "Gọi cà phê", "line": "Hi! What can I get for you?",
"translation": "Chào! Bạn muốn gọi gì?", "vocab": [{"word": "latte", "meaning": "cà phê sữa"}]}''';

  group('detect', () {
    test('quiz triggers', () {
      for (final text in ['Đố vui đi Sen', 'cho câu đố', 'chơi game', 'QUIZ']) {
        expect(SenSkill.detect(text)?.kind, SkillKind.quiz, reason: text);
      }
    });

    test('english roleplay triggers', () {
      for (final text in ['học tiếng anh', 'English please', 'roleplay']) {
        expect(SenSkill.detect(text)?.kind, SkillKind.english, reason: text);
      }
    });

    test('plain chat has no skill', () {
      expect(SenSkill.detect('thời tiết hôm nay'), isNull);
    });
  });

  group('quiz', () {
    const skill = QuizSkill();

    test('parses fenced JSON and strips option letters', () {
      final quiz = skill.parse(quizJson)! as QuizContent;
      expect(quiz.question, 'Con vật nào biết bay?');
      expect(quiz.options, ['Chó', 'Chim', 'Mèo', 'Cá']);
      expect(quiz.answer, 1);
      expect(quiz.explanation, 'Chim có cánh.');
      expect(quiz.isCorrect(1), isTrue);
      expect(quiz.isCorrect(0), isFalse);
      expect(
        quiz.spoken,
        'Con vật nào biết bay? A: Chó. B: Chim. C: Mèo. D: Cá.',
      );
      expect(quiz.recap, contains('Con vật nào biết bay?'));
    });

    test('rejects plain text, wrong option count and bad answers', () {
      expect(skill.parse('Thôi không chơi nữa nhé!'), isNull);
      expect(
        skill.parse('{"question":"q","options":["a","b"],"answer":"A"}'),
        isNull,
      );
      expect(
        skill.parse(
          '{"question":"q","options":["a","b","c","d"],"answer":"E"}',
        ),
        isNull,
      );
      expect(skill.parse('{broken'), isNull);
    });

    test('reads a spoken or typed choice', () {
      final quiz = skill.parse(quizJson)! as QuizContent;
      expect(quiz.choiceFrom('B'), 1);
      expect(quiz.choiceFrom('đáp án c'), 2);
      expect(quiz.choiceFrom('Chọn đê'), 3);
      expect(quiz.choiceFrom('câu a nhé'), 0);
      expect(quiz.choiceFrom('con chim'), 1);
      expect(quiz.choiceFrom('kể chuyện cười đi'), isNull);
    });

    test('instruction asks for JSON with four options', () {
      final text = skill.instruction(MemberProfile.be);
      expect(text, contains('"options"'));
      expect(text, contains('Bé'));
    });
  });

  group('english roleplay', () {
    const skill = EnglishRoleplaySkill();

    test('parses scenario, line, translation and vocab', () {
      final play = skill.parse(roleplayJson)! as RoleplayContent;
      expect(play.scenario, 'Gọi cà phê');
      expect(play.line, 'Hi! What can I get for you?');
      expect(play.translation, 'Chào! Bạn muốn gọi gì?');
      expect(play.vocab.single.word, 'latte');
      expect(play.vocab.single.meaning, 'cà phê sữa');
      expect(play.spoken, 'Hi! What can I get for you?');
      expect(play.recap, contains('Hi! What can I get for you?'));
    });

    test('missing line means plain chat', () {
      expect(skill.parse('{"scenario":"x"}'), isNull);
    });

    test('instruction adapts to the member level', () {
      final mom = skill.instruction(MemberProfile.me);
      final dad = skill.instruction(MemberProfile.thuc);
      expect(mom, contains(EnglishLevel.beginner.name));
      expect(dad, contains(EnglishLevel.intermediate.name));
      expect(mom, isNot(dad));
      expect(mom, contains('"translation"'));
    });
  });
}
