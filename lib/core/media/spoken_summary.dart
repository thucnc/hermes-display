/// Text worth reading aloud from a markdown answer: link labels instead of
/// URLs, no `*`/`#`, and only the first sentences of a long answer.
String spokenSummary(String answer) {
  final plain = answer
      .replaceAllMapped(_link, (match) => match[1] ?? '')
      .replaceAll(_markup, '')
      .replaceAll(_spaces, ' ')
      .trim();
  if (plain.length <= _shortLength) {
    return plain;
  }
  return plain.split(_sentenceEnd).take(_maxSentences).join(' ');
}

const int _shortLength = 160;
const int _maxSentences = 2;
final RegExp _link = RegExp(r'\[([^\]]*)\]\([^)]*\)');
final RegExp _markup = RegExp(r'[*#]');
final RegExp _spaces = RegExp(r'\s+');
final RegExp _sentenceEnd = RegExp(r'(?<=[.!?])\s+');
