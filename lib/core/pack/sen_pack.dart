import 'dart:convert';

import '../members/member_profile.dart';

/// Lifecycle of a pack skill or ritual; [paused] ones are ignored.
enum PackStatus {
  active,
  draft,
  paused;

  /// Unknown values read as [active].
  static PackStatus fromName(Object? raw) {
    return values.asNameMap()[raw] ?? active;
  }
}

abstract final class _Key {
  static const String version = 'version';
  static const String updatedAt = 'updatedAt';
  static const String updatedAtSnake = 'updated_at';
  static const String hash = 'hash';
  static const String members = 'members';
  static const String skills = 'skills';
  static const String rituals = 'rituals';
  static const String id = 'id';
  static const String name = 'name';
  static const String role = 'role';
  static const String initial = 'initial';
  static const String englishLevel = 'englishLevel';
  static const String englishLevelSnake = 'english_level';
  static const String callMe = 'callMe';
  static const String callMeSnake = 'call_me';
  static const String birthday = 'birthday';
  static const String avatar = 'avatar';
  static const String aliases = 'aliases';
  static const String facts = 'facts';
  static const String goals = 'goals';
  static const String taboos = 'taboos';
  static const String triggers = 'triggers';
  static const String status = 'status';
  static const String prompt = 'prompt';
  static const String rules = 'rules';
  static const String schedule = 'schedule';
  static const String days = 'days';
  static const String summary = 'summary';
  static const String questions = 'questions';
}

/// Placeholders a skill prompt may use, as written in the Obsidian notes.
abstract final class PackVar {
  static const String name = 'member.name';
  static const String role = 'member.role';
  static const String callMe = 'member.call_me';
  static const String age = 'member.age';
  static const String englishLevel = 'member.english_level';
}

abstract final class _Text {
  static const String ritual = 'Nghi thức gia đình';
  static const String questions = 'Câu hỏi gợi ý:';
  static const String rules = 'Quy tắc:';
  static const String gap = '; ';
  static const String lineGap = '\n';
  static const String bullet = '- ';
  static const String placeholderOpen = '{{';
  static const String placeholderClose = '}}';
}

String _str(Object? value) {
  if (value is String) {
    return value.trim();
  }
  if (value is num) {
    return value.toString();
  }
  return '';
}

String _firstStr(Map<String, dynamic> json, String key, String alt) {
  final value = _str(json[key]);
  return value.isNotEmpty ? value : _str(json[alt]);
}

List<String> _strings(Object? value) {
  if (value is! List) {
    return const [];
  }
  return [
    for (final item in value)
      if (_str(item) case final text when text.isNotEmpty) text,
  ];
}

List<String> _lower(List<String> items) {
  return [for (final item in items) item.toLowerCase()];
}

/// Valid entries of a JSON list; malformed ones are dropped.
List<T> _items<T>(Object? value, T? Function(Map<String, dynamic>) parse) {
  if (value is! List) {
    return const [];
  }
  return [
    for (final item in value)
      if (item is Map<String, dynamic>)
        if (parse(item) case final parsed?) parsed,
  ];
}

/// One family member as described in `Sen/members/<id>.md`.
class MemberPack {
  const MemberPack({
    required this.id,
    required this.name,
    this.role = '',
    this.initial = '',
    this.englishLevel = EnglishLevel.beginner,
    this.callMe = '',
    this.birthday,
    this.avatar = '',
    this.aliases = const [],
    this.facts = const [],
    this.goals = const [],
    this.taboos = const [],
  });

  /// Note roles shown the way the family says them.
  static const Map<String, String> _roleLabels = {
    'father': 'Bố',
    'mother': 'Mẹ',
    'child': 'Con',
    'grandfather': 'Ông',
    'grandmother': 'Bà',
    'grandparent': 'Ông bà',
  };
  static const int _monthsPerYear = 12;

  /// Null without an id or a name.
  static MemberPack? fromJson(Map<String, dynamic> json) {
    final id = _str(json[_Key.id]);
    final name = _str(json[_Key.name]);
    if (id.isEmpty || name.isEmpty) {
      return null;
    }
    return MemberPack(
      id: id,
      name: name,
      role: _str(json[_Key.role]),
      initial: _str(json[_Key.initial]),
      englishLevel: EnglishLevel.fromName(
        _firstStr(json, _Key.englishLevel, _Key.englishLevelSnake),
      ),
      callMe: _firstStr(json, _Key.callMe, _Key.callMeSnake),
      birthday: DateTime.tryParse(_str(json[_Key.birthday])),
      avatar: _str(json[_Key.avatar]),
      aliases: _strings(json[_Key.aliases]),
      facts: _strings(json[_Key.facts]),
      goals: _strings(json[_Key.goals]),
      taboos: _strings(json[_Key.taboos]),
    );
  }

  final String id;
  final String name;

  /// As written in the note, e.g. `child`; see [roleLabel].
  final String role;

  /// Avatar letter; empty means derived from [name].
  final String initial;
  final EnglishLevel englishLevel;

  /// How Sen calls this member, e.g. "Na ơi".
  final String callMe;
  final DateTime? birthday;

  /// Image URL or path relative to the pack; empty when none.
  final String avatar;
  final List<String> aliases;
  final List<String> facts;
  final List<String> goals;
  final List<String> taboos;

  String get roleLabel => _roleLabels[role.toLowerCase()] ?? role;

  /// First letter of the last word: "Bé Na" -> "N".
  String get avatarInitial {
    if (initial.isNotEmpty) {
      return initial;
    }
    final word = name.split(' ').lastWhere((w) => w.isNotEmpty);
    return word.substring(0, 1).toUpperCase();
  }

  MemberProfile toProfile() {
    return MemberProfile(
      id: id,
      name: name,
      role: roleLabel,
      englishLevel: englishLevel,
      initial: avatarInitial,
    );
  }

  /// Whole years on [now]; null without a birthday.
  int? ageOn(DateTime now) {
    final born = birthday;
    if (born == null) {
      return null;
    }
    final months =
        (now.year - born.year) * _monthsPerYear +
        now.month -
        born.month -
        (now.day < born.day ? 1 : 0);
    return months ~/ _monthsPerYear;
  }

  Map<String, String> vars(DateTime now) {
    return {
      PackVar.name: name,
      PackVar.role: roleLabel,
      PackVar.callMe: callMe.isEmpty ? name : callMe,
      PackVar.age: ageOn(now)?.toString() ?? '',
      PackVar.englishLevel: englishLevel.name,
    };
  }

  Map<String, Object?> toJson() {
    return {
      _Key.id: id,
      _Key.name: name,
      _Key.role: role,
      _Key.initial: initial,
      _Key.englishLevel: englishLevel.name,
      _Key.callMe: callMe,
      _Key.birthday: birthday?.toIso8601String(),
      _Key.avatar: avatar,
      _Key.aliases: aliases,
      _Key.facts: facts,
      _Key.goals: goals,
      _Key.taboos: taboos,
    };
  }
}

/// Fills `{{member.name}}`-style placeholders; unknown ones stay.
String fillVars(String template, Map<String, String> vars) {
  var text = template;
  for (final MapEntry(:key, :value) in vars.entries) {
    text = text.replaceAll(
      '${_Text.placeholderOpen}$key${_Text.placeholderClose}',
      value,
    );
  }
  return text;
}

/// Who an entry is for; empty means everyone.
bool _isFor(List<String> members, String memberId) {
  return members.isEmpty || members.contains(memberId);
}

/// A skill as described in `Sen/skills/<id>.md`.
class SkillPack {
  const SkillPack({
    required this.id,
    required this.name,
    required this.prompt,
    this.triggers = const [],
    this.members = const [],
    this.status = PackStatus.active,
  });

  /// Null without an id, a prompt or a trigger.
  static SkillPack? fromJson(Map<String, dynamic> json) {
    final id = _str(json[_Key.id]);
    final prompt = _str(json[_Key.prompt]);
    final triggers = _lower(_strings(json[_Key.triggers]));
    if (id.isEmpty || prompt.isEmpty || triggers.isEmpty) {
      return null;
    }
    return SkillPack(
      id: id,
      name: _str(json[_Key.name]),
      prompt: prompt,
      triggers: triggers,
      members: _strings(json[_Key.members]),
      status: PackStatus.fromName(json[_Key.status]),
    );
  }

  final String id;
  final String name;

  /// System instruction with `{{member.*}}` placeholders.
  final String prompt;

  /// Lower-case phrases that start this skill.
  final List<String> triggers;
  final List<String> members;
  final PackStatus status;

  bool matches(String text, String memberId) {
    if (status == PackStatus.paused || !_isFor(members, memberId)) {
      return false;
    }
    final lower = text.toLowerCase();
    return triggers.any(lower.contains);
  }

  String instruction(Map<String, String> vars) => fillVars(prompt, vars);

  Map<String, Object?> toJson() {
    return {
      _Key.id: id,
      _Key.name: name,
      _Key.prompt: prompt,
      _Key.triggers: triggers,
      _Key.members: members,
      _Key.status: status.name,
    };
  }
}

/// A family ritual as described in `Sen/rituals/<id>.md`.
class RitualPack {
  const RitualPack({
    required this.id,
    required this.name,
    this.summary = '',
    this.schedule = '',
    this.days = const [],
    this.triggers = const [],
    this.members = const [],
    this.questions = const [],
    this.rules = const [],
    this.status = PackStatus.active,
  });

  /// Null without an id or a name.
  static RitualPack? fromJson(Map<String, dynamic> json) {
    final id = _str(json[_Key.id]);
    final name = _str(json[_Key.name]);
    if (id.isEmpty || name.isEmpty) {
      return null;
    }
    return RitualPack(
      id: id,
      name: name,
      summary: _str(json[_Key.summary]),
      schedule: _str(json[_Key.schedule]),
      days: _strings(json[_Key.days]),
      triggers: _lower(_strings(json[_Key.triggers])),
      members: _strings(json[_Key.members]),
      questions: _strings(json[_Key.questions]),
      rules: _strings(json[_Key.rules]),
      status: PackStatus.fromName(json[_Key.status]),
    );
  }

  final String id;
  final String name;
  final String summary;

  /// Local time "HH:MM"; empty when on demand.
  final String schedule;
  final List<String> days;

  /// Lower-case phrases that bring the ritual into a turn.
  final List<String> triggers;
  final List<String> members;

  /// e.g. dinner check-in questions to rotate through.
  final List<String> questions;

  /// e.g. how to praise.
  final List<String> rules;
  final PackStatus status;

  bool matches(String text, String memberId) {
    if (status == PackStatus.paused || !_isFor(members, memberId)) {
      return false;
    }
    final lower = text.toLowerCase();
    return triggers.any(lower.contains);
  }

  String get instruction {
    return [
      '${_Text.ritual}: $name.${summary.isEmpty ? '' : ' $summary'}',
      if (questions.isNotEmpty)
        '${_Text.questions} ${questions.join(_Text.gap)}',
      if (rules.isNotEmpty)
        '${_Text.rules}${_Text.lineGap}'
            '${rules.map((rule) => '${_Text.bullet}$rule').join(_Text.lineGap)}',
    ].join(_Text.lineGap);
  }

  Map<String, Object?> toJson() {
    return {
      _Key.id: id,
      _Key.name: name,
      _Key.summary: summary,
      _Key.schedule: schedule,
      _Key.days: days,
      _Key.triggers: triggers,
      _Key.members: members,
      _Key.questions: questions,
      _Key.rules: rules,
      _Key.status: status.name,
    };
  }
}

/// `sen-pack.json`: everything Sen knows about the family, compiled from
/// the Second Brain and hosted at any URL.
class SenPack {
  const SenPack({
    this.version = '',
    this.updatedAt = '',
    this.hash = '',
    this.members = const [],
    this.skills = const [],
    this.rituals = const [],
  });

  /// Null for anything that is not a JSON object with at least one
  /// member, skill or ritual; an empty pack would wipe the family.
  static SenPack? tryParse(String raw) {
    final Object? json;
    try {
      json = jsonDecode(raw);
    } on FormatException {
      return null;
    }
    if (json is! Map<String, dynamic>) {
      return null;
    }
    final pack = SenPack.fromJson(json);
    return pack.isEmpty ? null : pack;
  }

  factory SenPack.fromJson(Map<String, dynamic> json) {
    return SenPack(
      version: _str(json[_Key.version]),
      updatedAt: _firstStr(json, _Key.updatedAt, _Key.updatedAtSnake),
      hash: _str(json[_Key.hash]),
      members: _items(json[_Key.members], MemberPack.fromJson),
      skills: _items(json[_Key.skills], SkillPack.fromJson),
      rituals: _items(json[_Key.rituals], RitualPack.fromJson),
    );
  }

  final String version;
  final String updatedAt;

  /// Content hash from the exporter; empty when the host has none.
  final String hash;
  final List<MemberPack> members;
  final List<SkillPack> skills;
  final List<RitualPack> rituals;

  bool get isEmpty => members.isEmpty && skills.isEmpty && rituals.isEmpty;

  /// Same content as [other]: equal non-empty hashes.
  bool sameContent(SenPack other) => hash.isNotEmpty && hash == other.hash;

  Map<String, Object?> toJson() {
    return {
      _Key.version: version,
      _Key.updatedAt: updatedAt,
      _Key.hash: hash,
      _Key.members: [for (final member in members) member.toJson()],
      _Key.skills: [for (final skill in skills) skill.toJson()],
      _Key.rituals: [for (final ritual in rituals) ritual.toJson()],
    };
  }
}
