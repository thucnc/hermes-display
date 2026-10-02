import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_display/core/media/rich_content.dart';
import 'package:hermes_display/core/members/member_profile.dart';
import 'package:hermes_display/core/skills/sen_skill.dart';
import 'package:hermes_display/core/skills/skill_content.dart';
import 'package:hermes_display/services/hermes_sync_service.dart';
import 'package:hermes_display/ui/strings.dart';
import 'package:hermes_display/ui/theme/app_theme.dart';
import 'package:hermes_display/ui/widgets/member_switcher.dart';
import 'package:hermes_display/ui/widgets/quiz_card.dart';
import 'package:hermes_display/ui/widgets/rich_card.dart';
import 'package:hermes_display/ui/widgets/roleplay_card.dart';

void main() {
  final quiz =
      const QuizSkill().parse(
            '{"question":"Con vật nào biết bay?",'
            '"options":["Chó","Chim","Mèo","Cá"],"answer":"B",'
            '"explain":"Chim có cánh."}',
          )!
          as QuizContent;
  final roleplay =
      const EnglishRoleplaySkill().parse(
            '{"scenario":"Gọi cà phê","line":"What can I get for you?",'
            '"translation":"Bạn muốn gọi gì?",'
            '"vocab":[{"word":"latte","meaning":"cà phê sữa"}]}',
          )!
          as RoleplayContent;

  Widget host(Widget child) {
    return MaterialApp(
      home: Scaffold(body: Center(child: child)),
    );
  }

  Color fillOf(WidgetTester tester, int index) {
    final box = tester.widget<AnimatedContainer>(
      find.byKey(QuizCard.optionKey(index)),
    );
    return (box.decoration! as BoxDecoration).color!;
  }

  Future<void> pumpQuiz(WidgetTester tester, int? picked, List<int> picks) {
    return tester.pumpWidget(
      host(QuizCard(quiz: quiz, picked: picked, onPick: picks.add)),
    );
  }

  testWidgets('quiz shows four tappable choices', (tester) async {
    final picks = <int>[];
    await pumpQuiz(tester, null, picks);
    expect(find.text('Con vật nào biết bay?'), findsOneWidget);
    for (final letter in QuizContent.letters) {
      expect(find.text(letter), findsOneWidget);
    }
    await tester.tap(find.text('Mèo'));
    expect(picks, [2]);
    expect(find.text('Chim có cánh.'), findsNothing);
  });

  testWidgets('wrong pick is red, right answer green, no more taps', (
    tester,
  ) async {
    final picks = <int>[];
    await pumpQuiz(tester, 2, picks);
    await tester.pump(Motion.quick);
    expect(fillOf(tester, 1), QuizCard.correctFill);
    expect(fillOf(tester, 2), QuizCard.wrongFill);
    expect(fillOf(tester, 0), isNot(QuizCard.wrongFill));
    expect(find.textContaining(AppStrings.quizWrong), findsOneWidget);
    expect(find.text('Chim có cánh.'), findsOneWidget);
    await tester.tap(find.text('Chó'));
    expect(picks, isEmpty);
  });

  testWidgets('right pick says so', (tester) async {
    await pumpQuiz(tester, 1, []);
    expect(find.text(AppStrings.quizCorrect), findsOneWidget);
  });

  testWidgets('roleplay shows scenario, line, hint and vocab', (tester) async {
    await tester.pumpWidget(host(RoleplayCard(roleplay: roleplay)));
    expect(find.text('Gọi cà phê'), findsOneWidget);
    expect(find.text('What can I get for you?'), findsOneWidget);
    expect(find.text('(Bạn muốn gọi gì?)'), findsOneWidget);
    expect(find.text('latte'), findsOneWidget);
    expect(find.text('cà phê sữa'), findsOneWidget);
  });

  testWidgets('rich card swaps in skill cards without save', (tester) async {
    final picks = <int>[];
    Future<void> pumpRich(SkillContent skill) {
      return tester.pumpWidget(
        host(
          RichCard(
            content: RichContent.forSkill(question: 'đố vui', skill: skill),
            onSave: () async => SaveResult.saved,
            onClose: () {},
            onQuizPick: picks.add,
          ),
        ),
      );
    }

    await pumpRich(quiz);
    expect(find.byType(QuizCard), findsOneWidget);
    expect(find.text(AppStrings.saveToHermes), findsNothing);
    await tester.tap(find.text('Chó'));
    expect(picks, [0]);

    await pumpRich(roleplay);
    expect(find.byType(RoleplayCard), findsOneWidget);
  });

  testWidgets('member switcher highlights and selects', (tester) async {
    final picked = <String>[];
    await tester.pumpWidget(
      host(
        MemberSwitcher(
          members: MemberProfile.family,
          activeId: 'thuc',
          onSelect: picked.add,
        ),
      ),
    );
    expect(find.text('Bố Thức'), findsOneWidget);
    expect(find.text('Mẹ'), findsOneWidget);
    final active = tester.widget<AnimatedContainer>(
      find.byKey(MemberSwitcher.keyFor('thuc')),
    );
    final idle = tester.widget<AnimatedContainer>(
      find.byKey(MemberSwitcher.keyFor('me')),
    );
    final ring = (active.decoration! as BoxDecoration).border! as Border;
    expect(ring.top.color, AppPalette.accent);
    expect((idle.decoration! as BoxDecoration).boxShadow, isNull);

    await tester.tap(find.text('Bé'));
    expect(picked, ['be']);
  });
}
