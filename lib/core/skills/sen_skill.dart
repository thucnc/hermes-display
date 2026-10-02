import '../members/member_profile.dart';
import 'skill_content.dart';

/// Skill ids; [name] is stored in the memory database.
enum SkillKind {
  quiz('Đố vui'),
  english('Tiếng Anh');

  const SkillKind(this.label);

  final String label;
}

enum SkillOutcome { correct, wrong, practiced }

/// A mode Sen switches into when a question asks for it. Each skill adds
/// its own system instruction and parses the structured reply.
sealed class SenSkill {
  const SenSkill();

  static const List<SenSkill> all = [QuizSkill(), EnglishRoleplaySkill()];

  SkillKind get kind;

  /// Lower-case phrases that start this skill.
  List<String> get triggers;

  String instruction(MemberProfile member);

  /// Null when the reply is plain chat, e.g. the user changed the topic.
  SkillContent? parse(String reply);

  bool matches(String text) {
    final lower = text.toLowerCase();
    return triggers.any(lower.contains);
  }

  static SenSkill? detect(String text) {
    for (final skill in all) {
      if (skill.matches(text)) {
        return skill;
      }
    }
    return null;
  }

  static SenSkill of(SkillKind kind) {
    return all.firstWhere((skill) => skill.kind == kind);
  }
}

const String _plainFallback =
    'Nếu người dùng muốn dừng hoặc hỏi chuyện khác, trả lời bình thường '
    'bằng văn bản, không dùng JSON.';

final class QuizSkill extends SenSkill {
  const QuizSkill();

  @override
  SkillKind get kind => SkillKind.quiz;

  @override
  List<String> get triggers => const ['đố vui', 'câu đố', 'chơi game', 'quiz'];

  @override
  String instruction(MemberProfile member) {
    return 'Kỹ năng Đố vui: đặt MỘT câu đố vui, độ khó hợp với '
        '${member.name} (${member.role}), không lặp câu cũ. Chỉ trả về đúng '
        'một JSON, không thêm chữ nào khác: {"question": "...", '
        '"options": ["...", "...", "...", "..."], "answer": "A", '
        '"explain": "..."}. Đúng 4 lựa chọn, "answer" là A, B, C hoặc D, '
        '"explain" giải thích ngắn. $_plainFallback';
  }

  @override
  SkillContent? parse(String reply) {
    final json = jsonObjectIn(reply);
    return json == null ? null : QuizContent.fromJson(json);
  }
}

final class EnglishRoleplaySkill extends SenSkill {
  const EnglishRoleplaySkill();

  static const Map<EnglishLevel, String> _guides = {
    EnglishLevel.starter:
        'câu cực ngắn 3-6 từ, từ vựng quen thuộc với trẻ em, nói chậm rõ',
    EnglishLevel.beginner:
        'câu ngắn, từ vựng cơ bản hằng ngày, luôn có bản dịch tiếng Việt',
    EnglishLevel.intermediate:
        'câu tự nhiên như người bản xứ, thêm cụm từ hữu ích, gợi ý tiếng Việt '
        'ngắn',
    EnglishLevel.advanced:
        'hội thoại tự nhiên, thành ngữ và cách nói trang trọng/thân mật',
  };

  @override
  SkillKind get kind => SkillKind.english;

  @override
  List<String> get triggers {
    return const ['tiếng anh', 'english', 'roleplay', 'học tiếng anh'];
  }

  @override
  String instruction(MemberProfile member) {
    final level = member.englishLevel;
    return 'Kỹ năng Luyện tiếng Anh nhập vai: chọn một tình huống đời thường '
        '(gọi cà phê, du lịch, mua sắm, hỏi đường...) và đóng vai '
        '(ví dụ người phục vụ quán cà phê) nói tiếng Anh với ${member.name}. '
        'Trình độ ${level.name}: ${_guides[level]}. Mỗi lượt 1-2 câu tiếng '
        'Anh, kết thúc bằng một câu hỏi để người học trả lời. Chỉ trả về đúng '
        'một JSON, không thêm chữ nào khác: {"scenario": "...", '
        '"line": "...", "translation": "...", "vocab": [{"word": "...", '
        '"meaning": "..."}]}. "scenario" là tên tình huống bằng tiếng Việt, '
        '"translation" là bản dịch/gợi ý tiếng Việt của "line", "vocab" tối '
        'đa 3 từ. $_plainFallback';
  }

  @override
  SkillContent? parse(String reply) {
    final json = jsonObjectIn(reply);
    return json == null ? null : RoleplayContent.fromJson(json);
  }
}
