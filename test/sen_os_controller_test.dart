import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_display/core/members/member_profile.dart';
import 'package:hermes_display/core/skills/sen_skill.dart';
import 'package:hermes_display/core/skills/skill_content.dart';
import 'package:hermes_display/core/state/display_controller.dart';
import 'package:hermes_display/core/state/display_state.dart';
import 'package:hermes_display/services/hermes_websocket_client.dart';
import 'package:hermes_display/services/settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_gemini_service.dart';
import 'support/fake_sen_memory.dart';
import 'support/fake_transport.dart';

void main() {
  const memo = 'Đang nói chuyện với: Bé (Con).';
  const quiz =
      '{"question":"Con vật nào biết bay?","options":["Chó","Chim","Mèo","Cá"],'
      '"answer":"B","explain":"Chim có cánh."}';
  const roleplay =
      '{"scenario":"Gọi cà phê","line":"What can I get for you?",'
      '"translation":"Bạn muốn gọi gì?","vocab":[]}';
  late SettingsService settings;
  late FakeGeminiService gemini;
  late FakeSenMemoryService memory;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = await SettingsService.create();
    await settings.save(HubSettings.defaults.copyWith(geminiApiKey: 'key'));
  });

  DisplayController build() {
    gemini = FakeGeminiService();
    memory = FakeSenMemoryService(prompt: memo);
    return DisplayController(
      settingsService: settings,
      client: HermesWebSocketClient(
        transportFactory: FakeTransportFactory().call,
      ),
      gemini: gemini,
      memory: memory,
    )..start();
  }

  test('selecting a member persists and notifies', () {
    fakeAsync((async) {
      final controller = build();
      async.flushMicrotasks();
      var notified = 0;
      controller.addListener(() => notified++);
      expect(controller.member, MemberProfile.thuc);

      controller.selectMember('be');
      async.flushMicrotasks();
      expect(controller.member, MemberProfile.be);
      expect(settings.load().activeMemberId, 'be');
      expect(notified, 1);

      controller.selectMember('be');
      controller.selectMember('ghost');
      expect(notified, 1);
      controller.dispose();
    });
  });

  test('memory of the active member goes to Gemini', () {
    fakeAsync((async) {
      final controller = build();
      controller.selectMember('be');
      async.flushMicrotasks();
      controller.sendText('xin chào');
      async.flushMicrotasks();
      expect(memory.asked, ['be']);
      expect(gemini.contexts.single, memo);
      controller.dispose();
    });
  });

  test('quiz reply becomes a quiz card; a tap scores it', () {
    fakeAsync((async) {
      final controller = build();
      controller.sendText('đố vui đi');
      async.flushMicrotasks();
      expect(gemini.contexts.single, startsWith('$memo\n\n'));
      expect(gemini.contexts.single, contains('"options"'));

      gemini.answer(quiz);
      async.flushMicrotasks();
      expect(controller.state, DisplayState.speaking);
      expect(controller.rich?.skill, isA<QuizContent>());
      expect(controller.reply, startsWith('Con vật nào biết bay?'));
      expect(controller.quizPick, isNull);

      controller.pickQuiz(0);
      async.flushMicrotasks();
      expect(controller.quizPick, 0);
      expect(memory.records.single, (
        'thuc',
        SkillKind.quiz,
        SkillOutcome.wrong,
      ));

      controller.pickQuiz(1);
      expect(controller.quizPick, 0);
      expect(memory.records, hasLength(1));
      controller.dispose();
    });
  });

  test('a spoken or typed letter answers the quiz without Gemini', () {
    fakeAsync((async) {
      final controller = build();
      controller.sendText('chơi game');
      async.flushMicrotasks();
      gemini.answer(quiz);
      async.flushMicrotasks();

      expect(controller.sendText('đáp án B'), SendResult.sent);
      async.flushMicrotasks();
      expect(gemini.prompts, hasLength(1));
      expect(controller.state, DisplayState.idle);
      expect(controller.quizPick, 1);
      expect(controller.rich?.skill, isA<QuizContent>());
      expect(memory.records.single.$3, SkillOutcome.correct);
      controller.dispose();
    });
  });

  test('next quiz turn keeps the skill and its recap', () {
    fakeAsync((async) {
      final controller = build();
      controller.sendText('câu đố');
      async.flushMicrotasks();
      gemini.answer(quiz);
      async.flushMicrotasks();
      controller.pickQuiz(1);

      controller.sendText('câu tiếp theo');
      async.flushMicrotasks();
      expect(gemini.contexts.last, contains('"options"'));
      expect(gemini.contexts.last, contains('Con vật nào biết bay?'));

      gemini.answer('Hết giờ chơi rồi nhé!');
      async.flushMicrotasks();
      expect(controller.rich, isNull);
      controller.sendText('thời tiết');
      async.flushMicrotasks();
      expect(gemini.contexts.last, memo);
      controller.dispose();
    });
  });

  test('roleplay reply shows its card and logs practice', () {
    fakeAsync((async) {
      final controller = build();
      controller.selectMember('me');
      async.flushMicrotasks();
      controller.sendText('học tiếng anh');
      async.flushMicrotasks();
      expect(gemini.contexts.single, contains(EnglishLevel.beginner.name));

      gemini.answer(roleplay);
      async.flushMicrotasks();
      expect(controller.rich?.skill, isA<RoleplayContent>());
      expect(controller.reply, 'What can I get for you?');
      expect(memory.records.single, (
        'me',
        SkillKind.english,
        SkillOutcome.practiced,
      ));

      controller.sendText('I want a latte');
      async.flushMicrotasks();
      expect(gemini.contexts.last, contains('What can I get for you?'));
      controller.dismissRich();
      controller.sendText('cảm ơn');
      async.flushMicrotasks();
      expect(gemini.contexts.last, memo);
      controller.dispose();
    });
  });
}
