import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_display/core/media/spoken_summary.dart';

void main() {
  test('short answer is spoken whole, markdown stripped', () {
    expect(spokenSummary('**Bây giờ** là 3 giờ.'), 'Bây giờ là 3 giờ.');
  });

  test('long answer keeps the first two sentences', () {
    const text =
        '# Trứng chiên\nTrứng chiên rất dễ làm. Chỉ cần trứng và dầu! '
        'Đầu tiên đập trứng vào bát và đánh thật đều tay cho tan. '
        'Sau đó cho chảo lên bếp và đun nóng dầu ăn ở lửa vừa.';
    expect(
      spokenSummary(text),
      'Trứng chiên Trứng chiên rất dễ làm. Chỉ cần trứng và dầu!',
    );
  });

  test('links are read as their label', () {
    expect(
      spokenSummary('Xem [video này](https://youtu.be/abcdefghijk) nhé.'),
      'Xem video này nhé.',
    );
  });

  test('blank or symbol-only answer is empty', () {
    expect(spokenSummary('  ** # '), isEmpty);
  });
}
