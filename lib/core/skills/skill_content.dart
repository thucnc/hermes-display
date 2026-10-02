import 'dart:convert';

import 'sen_skill.dart';

/// Structured answer of a skill turn, shown as an interactive card.
sealed class SkillContent {
  const SkillContent();

  SkillKind get kind;

  /// Plain text read aloud and shown as the reply.
  String get spoken;

  /// One line reminding Gemini of this turn on the next one.
  String get recap;
}

abstract final class _Field {
  static const String question = 'question';
  static const String options = 'options';
  static const String answer = 'answer';
  static const String explain = 'explain';
  static const String scenario = 'scenario';
  static const String line = 'line';
  static const String translation = 'translation';
  static const String vocab = 'vocab';
  static const String word = 'word';
  static const String meaning = 'meaning';
}

/// The JSON object in a reply, tolerating code fences and chatter.
Map<String, dynamic>? jsonObjectIn(String reply) {
  final start = reply.indexOf('{');
  final end = reply.lastIndexOf('}');
  if (start < 0 || end <= start) {
    return null;
  }
  try {
    final value = jsonDecode(reply.substring(start, end + 1));
    return value is Map<String, dynamic> ? value : null;
  } on FormatException {
    return null;
  }
}

String _text(Object? value) => value is String ? value.trim() : '';

final class QuizContent extends SkillContent {
  const QuizContent({
    required this.question,
    required this.options,
    required this.answer,
    this.explanation = '',
  });

  static const List<String> letters = ['A', 'B', 'C', 'D'];
  static const int optionCount = 4;

  /// "A. x", "B) x", "C: x".
  static final RegExp _letterPrefix = RegExp(r'^[A-Da-d]\s*[.):-]\s+');

  /// Letter words as Vietnamese speech-to-text writes them.
  static const Map<String, int> _spokenLetters = {
    'a': 0,
    'b': 1,
    'bê': 1,
    'bờ': 1,
    'c': 2,
    'xê': 2,
    'cê': 2,
    'cờ': 2,
    'd': 3,
    'đê': 3,
    'dê': 3,
    'dờ': 3,
  };
  static const Set<String> _choiceWords = {
    'đáp',
    'án',
    'câu',
    'chọn',
    'phương',
    'là',
    'nhé',
    'ạ',
  };
  static final RegExp _wordSplit = RegExp(r'[\s.,!?:;]+');

  final String question;
  final List<String> options;

  /// Index into [options].
  final int answer;
  final String explanation;

  @override
  SkillKind get kind => SkillKind.quiz;

  @override
  String get spoken {
    final choices = [
      for (final (index, option) in options.indexed)
        '${letters[index]}: $option.',
    ];
    return '$question ${choices.join(' ')}';
  }

  @override
  String get recap => 'Câu đố trước: $question (đáp án ${letters[answer]}).';

  bool isCorrect(int index) => index == answer;

  /// Null when [raw] has no question, not four options or no valid answer.
  static QuizContent? fromJson(Map<String, dynamic> raw) {
    final question = _text(raw[_Field.question]);
    final options = raw[_Field.options];
    final answer = letters.indexOf(_text(raw[_Field.answer]).toUpperCase());
    if (question.isEmpty || options is! List || answer < 0) {
      return null;
    }
    final cleaned = [
      for (final option in options)
        _text(option).replaceFirst(_letterPrefix, ''),
    ];
    if (cleaned.length != optionCount || cleaned.any((o) => o.isEmpty)) {
      return null;
    }
    return QuizContent(
      question: question,
      options: cleaned,
      answer: answer,
      explanation: _text(raw[_Field.explain]),
    );
  }

  /// Choice named in a typed or spoken reply ("B", "đáp án xê", option
  /// text), or null when it is about something else.
  int? choiceFrom(String text) {
    final lower = text.toLowerCase().trim();
    final words = [
      for (final word in lower.split(_wordSplit))
        if (word.isNotEmpty && !_choiceWords.contains(word)) word,
    ];
    if (words.length == 1 && _spokenLetters.containsKey(words.single)) {
      return _spokenLetters[words.single];
    }
    for (final (index, option) in options.indexed) {
      if (lower.contains(option.toLowerCase())) {
        return index;
      }
    }
    return null;
  }
}

class VocabTip {
  const VocabTip({required this.word, required this.meaning});

  final String word;
  final String meaning;
}

final class RoleplayContent extends SkillContent {
  const RoleplayContent({
    required this.scenario,
    required this.line,
    this.translation = '',
    this.vocab = const [],
  });

  final String scenario;

  /// Sen's English line in the scene.
  final String line;

  /// Vietnamese translation or hint for [line].
  final String translation;
  final List<VocabTip> vocab;

  @override
  SkillKind get kind => SkillKind.english;

  @override
  String get spoken => line;

  @override
  String get recap => 'Câu trước của Sen ($scenario): $line';

  /// Null without an English line.
  static RoleplayContent? fromJson(Map<String, dynamic> raw) {
    final line = _text(raw[_Field.line]);
    if (line.isEmpty) {
      return null;
    }
    final vocab = raw[_Field.vocab];
    return RoleplayContent(
      scenario: _text(raw[_Field.scenario]),
      line: line,
      translation: _text(raw[_Field.translation]),
      vocab: [
        if (vocab is List)
          for (final tip in vocab.whereType<Map<String, dynamic>>())
            if (_text(tip[_Field.word]).isNotEmpty)
              VocabTip(
                word: _text(tip[_Field.word]),
                meaning: _text(tip[_Field.meaning]),
              ),
      ],
    );
  }
}
