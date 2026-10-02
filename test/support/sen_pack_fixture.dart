/// A pack like `tools/export_sen_pack.py` compiles from `Sen/`.
const String senPackJson = '''
{
  "version": "a1b2c3d4e5f6",
  "updatedAt": "2026-10-02T09:00:00Z",
  "hash": "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2",
  "members": [
    {"id": "thuc", "name": "Bố Thức", "role": "father",
     "englishLevel": "intermediate", "callMe": "Bố Thức ơi",
     "facts": ["Thích uống cà phê ít đường vào buổi sáng."]},
    {"id": "be", "name": "Bé Na", "role": "child", "english_level": "beginner",
     "call_me": "Na ơi", "birthday": "2020-05-14",
     "avatar": "assets/avatars/be.png",
     "facts": ["Thích khủng long tím"],
     "goals": ["Tự giác dọn đồ chơi trước khi đi ngủ."],
     "taboos": ["Không tự tiện hứa mua đồ chơi thay bố mẹ."]},
    {"id": "ong", "name": "Ông Nội", "role": "grandfather"}
  ],
  "skills": [
    {"id": "bedtime-story", "name": "Kể chuyện ru ngủ",
     "triggers": ["Kể chuyện", "bedtime story"], "members": ["be"],
     "status": "draft",
     "prompt": "Kể chuyện cho {{member.name}} ({{member.age}} tuổi), chúc {{member.call_me}}."},
    {"id": "quiz", "name": "Đố vui", "triggers": ["đố vui"], "prompt": "pack quiz"},
    {"id": "garden", "name": "Làm vườn", "triggers": ["làm vườn"],
     "status": "paused", "prompt": "paused"}
  ],
  "rituals": [
    {"id": "dinner-checkin", "name": "Bữa tối Family Check-in",
     "summary": "Mỗi người trả lời một câu hỏi.", "schedule": "19:30",
     "triggers": ["bữa tối"],
     "questions": ["Điều vui nhất hôm nay là gì?"],
     "rules": ["Không hỏi về điểm số."]}
  ]
}
''';
