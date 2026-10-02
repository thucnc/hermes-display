import 'package:hermes_display/core/pack/sen_pack.dart';
import 'package:hermes_display/core/skills/sen_skill.dart';
import 'package:hermes_display/services/sen_memory_service.dart';

/// Returns a fixed prompt and records every skill result.
class FakeSenMemoryService implements SenMemoryService {
  FakeSenMemoryService({this.prompt = ''});

  final String prompt;
  final List<String> asked = [];
  final List<(String, FactCategory, String)> facts = [];
  final List<(String, SkillKind, SkillOutcome)> records = [];
  final List<List<MemberPack>> applied = [];

  @override
  Future<String> buildMemoryPrompt(String memberId) async {
    asked.add(memberId);
    return prompt;
  }

  @override
  Future<void> addFact(
    String memberId,
    FactCategory category,
    String fact,
  ) async {
    facts.add((memberId, category, fact));
  }

  @override
  Future<void> recordSkill(
    String memberId,
    SkillKind skill,
    SkillOutcome outcome,
  ) async {
    records.add((memberId, skill, outcome));
  }

  @override
  Future<void> applyMembers(List<MemberPack> members) async {
    applied.add(members);
  }
}
