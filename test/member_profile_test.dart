import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_display/core/members/member_profile.dart';

void main() {
  test('family has Bố Thức, Mẹ and Bé', () {
    expect(MemberProfile.family.map((m) => m.id), ['thuc', 'me', 'be']);
    expect(MemberProfile.byId('me').name, 'Mẹ');
    expect(MemberProfile.byId('be').role, 'Con');
    expect(MemberProfile.thuc.englishLevel, EnglishLevel.intermediate);
  });

  test('unknown or missing id falls back to Bố Thức', () {
    expect(MemberProfile.byId('ghost'), MemberProfile.thuc);
    expect(MemberProfile.byId(null), MemberProfile.thuc);
    expect(MemberProfile.defaultId, 'thuc');
  });

  test('english level parses its wire name', () {
    expect(EnglishLevel.fromName('beginner'), EnglishLevel.beginner);
    expect(EnglishLevel.fromName('nope'), EnglishLevel.beginner);
  });
}
