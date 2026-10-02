/// English skill used to pitch roleplay; [name] is the stored value.
enum EnglishLevel {
  starter,
  beginner,
  intermediate,
  advanced;

  /// Unknown values read as [beginner].
  static EnglishLevel fromName(String? raw) {
    return values.asNameMap()[raw] ?? beginner;
  }
}

abstract final class MemberId {
  static const String thuc = 'thuc';
  static const String me = 'me';
  static const String be = 'be';
}

/// A family member Sen can talk to.
class MemberProfile {
  const MemberProfile({
    required this.id,
    required this.name,
    required this.role,
    required this.englishLevel,
    required this.initial,
  });

  static const MemberProfile thuc = MemberProfile(
    id: MemberId.thuc,
    name: 'Bố Thức',
    role: 'Bố',
    englishLevel: EnglishLevel.intermediate,
    initial: 'T',
  );
  static const MemberProfile me = MemberProfile(
    id: MemberId.me,
    name: 'Mẹ',
    role: 'Mẹ',
    englishLevel: EnglishLevel.beginner,
    initial: 'M',
  );
  static const MemberProfile be = MemberProfile(
    id: MemberId.be,
    name: 'Bé',
    role: 'Con',
    englishLevel: EnglishLevel.starter,
    initial: 'B',
  );

  static const List<MemberProfile> family = [thuc, me, be];
  static const String defaultId = MemberId.thuc;

  final String id;
  final String name;
  final String role;
  final EnglishLevel englishLevel;

  /// Letter shown in the avatar chip.
  final String initial;

  static bool isKnown(String? id) => family.any((member) => member.id == id);

  /// Unknown ids fall back to the default member.
  static MemberProfile byId(String? id) {
    for (final member in family) {
      if (member.id == id) {
        return member;
      }
    }
    return thuc;
  }

  /// Addressing rules based on family member.
  String get pronounRule {
    return switch (id) {
      MemberId.thuc =>
        'XƯNG HÔ: Bạn đang nói chuyện với Bố Thức. Hãy xưng là "em" và gọi người dùng là "anh" (xưng hô em - anh). Tuyệt đối không xưng con hay cháu.',
      MemberId.me =>
        'XƯNG HÔ: Bạn đang nói chuyện với Mẹ. Hãy xưng là "em" và gọi người dùng là "chị" (xưng hô em - chị). Tuyệt đối không xưng con hay cháu.',
      MemberId.be =>
        'XƯNG HÔ: Bạn đang nói chuyện với Bé. Hãy xưng là "mình" và gọi bé là "bạn" (xưng hô mình - bạn) như bạn thân đồng trang lứa.',
      _ => 'XƯNG HÔ: Hãy xưng là "em" và gọi người dùng lịch sự, thân thiện.',
    };
  }
}
