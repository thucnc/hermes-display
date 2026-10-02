import '../members/member_profile.dart';
import '../skills/sen_skill.dart';
import 'sen_pack.dart';

/// The loaded knowledge pack as Sen uses it: who is in the family and
/// which extra skills and rituals a question can start. Without a pack
/// Sen falls back to the built-in family and skills.
class SenPackRegistry {
  static const String _gap = '\n\n';

  /// Built-in skills keep their own prompt and card parsing.
  static final Set<String> _builtIn = {
    for (final kind in SkillKind.values) kind.name,
  };

  SenPack? _pack;
  List<MemberProfile> _members = MemberProfile.family;

  SenPack? get pack => _pack;

  /// Pack members, or the built-in family when the pack has none.
  List<MemberProfile> get members => _members;

  void load(SenPack pack) {
    _pack = pack;
    _members = pack.members.isEmpty
        ? MemberProfile.family
        : [for (final member in pack.members) member.toProfile()];
  }

  bool has(String id) => _members.any((member) => member.id == id);

  /// Unknown ids fall back to the default member, then the first one.
  MemberProfile byId(String id) {
    for (final member in _members) {
      if (member.id == id) {
        return member;
      }
    }
    for (final member in _members) {
      if (member.id == MemberProfile.defaultId) {
        return member;
      }
    }
    return _members.first;
  }

  /// Instructions of the pack skill and ritual [text] asks for; empty
  /// when none matches.
  String instructionFor(String text, MemberProfile member, DateTime now) {
    final pack = _pack;
    if (pack == null) {
      return '';
    }
    final vars = _varsOf(pack, member, now);
    final skill = pack.skills
        .where((s) => !_builtIn.contains(s.id) && s.matches(text, member.id))
        .firstOrNull;
    final ritual = pack.rituals
        .where((r) => r.matches(text, member.id))
        .firstOrNull;
    return [?skill?.instruction(vars), ?ritual?.instruction].join(_gap);
  }

  static Map<String, String> _varsOf(
    SenPack pack,
    MemberProfile member,
    DateTime now,
  ) {
    for (final entry in pack.members) {
      if (entry.id == member.id) {
        return entry.vars(now);
      }
    }
    return {
      PackVar.name: member.name,
      PackVar.role: member.role,
      PackVar.callMe: member.name,
      PackVar.englishLevel: member.englishLevel.name,
    };
  }
}
