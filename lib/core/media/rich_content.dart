/// Second Brain folder a saved note lands in; [name] is the wire value.
enum NoteCategory { recipes, notes }

/// Payload of a "Save to Hermes" request.
class NoteDraft {
  const NoteDraft({
    required this.title,
    required this.content,
    required this.category,
  });

  final String title;
  final String content;
  final NoteCategory category;
}

class YouTubeVideo {
  const YouTubeVideo({required this.id, this.title});

  final String id;

  /// Label of a markdown link around the URL, when the reply had one.
  final String? title;

  static const String _watchBase = 'https://www.youtube.com/watch';
  static const String _thumbHost = 'img.youtube.com';
  static const String _thumbFile = 'hqdefault.jpg';

  /// watch?v=, youtu.be/ and shorts/ links; ids are always 11 chars.
  static final RegExp _link = RegExp(
    r'(?:https?://)?(?:www\.|m\.)?'
    r'(?:youtube\.com/(?:watch\?(?:[^\s)\]]*&)?v=|shorts/)|youtu\.be/)'
    r'([A-Za-z0-9_-]{11})',
  );
  static final RegExp _markdown = RegExp(r'\[([^\]]+)\]\(([^)\s]+)\)');

  Uri get watchUri => Uri.parse('$_watchBase?v=$id');

  Uri get thumbnail => Uri.https(_thumbHost, '/vi/$id/$_thumbFile');

  /// Unique videos in order of appearance.
  static List<YouTubeVideo> extract(String text) {
    final titles = <String, String>{};
    for (final match in _markdown.allMatches(text)) {
      final id = _link.firstMatch(match.group(2)!)?.group(1);
      if (id == null) {
        continue;
      }
      titles.putIfAbsent(id, () => match.group(1)!.trim());
    }
    final seen = <String>{};
    return [
      for (final match in _link.allMatches(text))
        if (seen.add(match.group(1)!))
          YouTubeVideo(id: match.group(1)!, title: titles[match.group(1)]),
    ];
  }
}

/// A reply worth showing as a card: it has a video or a step list.
class RichContent {
  const RichContent({
    required this.title,
    required this.body,
    required this.steps,
    required this.category,
    this.video,
  });

  static const int maxTitleChars = 80;
  static const int _minSteps = 2;

  /// "1. x", "2) x", "Bước 3: x".
  static final RegExp _step = RegExp(
    r'^\s*(?:\d{1,2}[.)]|bước\s*\d{1,2}\s*[:.)-]?)\s+(.+)$',
    caseSensitive: false,
    multiLine: true,
  );
  static final RegExp _emphasis = RegExp(r'\*\*|__|`');
  static final RegExp _recipe = RegExp(
    r'công thức|nguyên liệu|nấu|chiên|xào|luộc|nướng|hấp|món|recipe',
    caseSensitive: false,
  );

  final String title;
  final String body;
  final List<String> steps;
  final NoteCategory category;
  final YouTubeVideo? video;

  /// Null when the reply is plain chat. [videos] adds links found outside
  /// the text, e.g. search grounding sources.
  static RichContent? parse({
    required String question,
    required String reply,
    List<YouTubeVideo> videos = const [],
  }) {
    final text = reply.trim();
    final steps = [
      for (final match in _step.allMatches(text))
        match.group(1)!.replaceAll(_emphasis, '').trim(),
    ];
    final found = [...YouTubeVideo.extract(text), ...videos];
    final hasSteps = steps.length >= _minSteps;
    if (!hasSteps && found.isEmpty) {
      return null;
    }
    final recipe = _recipe.hasMatch('$question\n$text');
    return RichContent(
      title: _titleFrom(question, text),
      body: text,
      steps: hasSteps ? steps : const [],
      category: recipe ? NoteCategory.recipes : NoteCategory.notes,
      video: found.isEmpty ? null : found.first,
    );
  }

  static String _titleFrom(String question, String reply) {
    final source = question.trim().isEmpty ? reply : question;
    final line = source.trim().split('\n').first.trim();
    if (line.length <= maxTitleChars) {
      return line;
    }
    return line.substring(0, maxTitleChars).trimRight();
  }

  /// Markdown note; the video link is appended unless already in the text.
  NoteDraft toNote() {
    final link = video?.watchUri.toString();
    final hasLink = link == null || body.contains(link);
    return NoteDraft(
      title: title,
      content: hasLink ? body : '$body\n\n$link',
      category: category,
    );
  }
}
