import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_display/core/media/rich_content.dart';

void main() {
  group('YouTubeVideo.extract', () {
    test('finds watch, short and youtu.be links with ids', () {
      final videos = YouTubeVideo.extract(
        'Xem https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=10 hoặc '
        'https://youtu.be/abcdefghijk và youtube.com/shorts/ABCDEFGHIJK',
      );
      expect(videos.map((v) => v.id), [
        'dQw4w9WgXcQ',
        'abcdefghijk',
        'ABCDEFGHIJK',
      ]);
    });

    test('takes the markdown link label as title', () {
      final video = YouTubeVideo.extract(
        'Video: [Cách nấu phở bò](https://youtu.be/abcdefghijk)',
      ).single;
      expect(video.title, 'Cách nấu phở bò');
      expect(
        video.watchUri.toString(),
        'https://www.youtube.com/watch?v=abcdefghijk',
      );
      expect(
        video.thumbnail.toString(),
        'https://img.youtube.com/vi/abcdefghijk/hqdefault.jpg',
      );
    });

    test('dedupes and ignores non-youtube links', () {
      final videos = YouTubeVideo.extract(
        'https://youtu.be/abcdefghijk https://youtu.be/abcdefghijk '
        'https://vimeo.com/123',
      );
      expect(videos, hasLength(1));
      expect(videos.single.title, isNull);
    });
  });

  group('RichContent.parse', () {
    const recipe = '''Công thức trứng chiên:
Nguyên liệu: 2 quả trứng, hành lá.
1. Đập trứng ra bát.
2. **Đánh đều** với hành.
Bước 3: Chiên vàng hai mặt.
[Trứng chiên ngon](https://www.youtube.com/watch?v=dQw4w9WgXcQ)''';

    test('recipe with steps and a video', () {
      final rich = RichContent.parse(
        question: 'Cách làm trứng chiên',
        reply: recipe,
      )!;
      expect(rich.steps, [
        'Đập trứng ra bát.',
        'Đánh đều với hành.',
        'Chiên vàng hai mặt.',
      ]);
      expect(rich.video?.id, 'dQw4w9WgXcQ');
      expect(rich.category, NoteCategory.recipes);
      expect(rich.title, 'Cách làm trứng chiên');
    });

    test('plain chit-chat has no rich content', () {
      expect(
        RichContent.parse(question: 'mấy giờ', reply: 'Bây giờ là 3 giờ'),
        isNull,
      );
    });

    test('a single numbered line is not a step list', () {
      expect(
        RichContent.parse(question: 'q', reply: '1. chỉ một dòng'),
        isNull,
      );
    });

    test('extra grounding videos count; non-recipe goes to notes', () {
      final rich = RichContent.parse(
        question: '',
        reply: 'Đây là video hướng dẫn thay lốp xe.',
        videos: YouTubeVideo.extract('https://youtu.be/abcdefghijk'),
      )!;
      expect(rich.category, NoteCategory.notes);
      expect(rich.steps, isEmpty);
      expect(rich.title, 'Đây là video hướng dẫn thay lốp xe.');
    });

    test('long titles are trimmed', () {
      final rich = RichContent.parse(
        question: 'a' * 200,
        reply: 'https://youtu.be/abcdefghijk',
      )!;
      expect(rich.title.length, RichContent.maxTitleChars);
    });

    test('note markdown keeps reply and video link', () {
      final note = RichContent.parse(question: 'q', reply: recipe)!.toNote();
      expect(note.category, NoteCategory.recipes);
      expect(note.content, contains('Đánh đều'));
      expect(
        note.content,
        contains('https://www.youtube.com/watch?v=dQw4w9WgXcQ'),
      );
    });
  });
}
