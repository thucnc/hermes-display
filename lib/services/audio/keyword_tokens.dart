/// Turns a free-text wake phrase into the SentencePiece tokens a sherpa-onnx
/// KWS model understands, using only pieces present in its `tokens.txt`.
///
/// The model ships no tokenizer, so this is a greedy longest-match. It
/// reproduces the real sentencepiece output for "HEY SEN"
/// (`▁HE Y ▁SE N`) but not for every word.
library;

enum KeywordFault { empty, unknownToken }

enum KeywordCheck {
  /// Tokenises against the installed model's vocabulary.
  ok,

  /// No model yet; plain A-Z words pass and are re-checked on load.
  unverified,
  empty,
  unsupported,
}

final class KeywordException implements Exception {
  const KeywordException(this.fault, [this.word = '']);

  final KeywordFault fault;

  /// The word that could not be tokenised; empty for [KeywordFault.empty].
  final String word;

  @override
  String toString() => 'KeywordException(${fault.name}, $word)';
}

/// Piece set of a model's `tokens.txt` (`<piece> <id>` per line).
final class KwsVocab {
  const KwsVocab(this._pieces);

  factory KwsVocab.parse(String tokensTxt) {
    final pieces = <String>{};
    for (final line in tokensTxt.split(_newline)) {
      final piece = line.trim().split(_blank).first;
      if (piece.isEmpty || piece.startsWith(_specialPrefix)) {
        continue;
      }
      pieces.add(piece);
    }
    return KwsVocab(pieces);
  }

  static const String _newline = '\n';
  static const String _specialPrefix = '<';
  static final RegExp _blank = RegExp(r'\s+');

  final Set<String> _pieces;

  bool contains(String piece) => _pieces.contains(piece);
}

abstract final class KeywordSyntax {
  /// SentencePiece word-start marker (U+2581).
  static const String wordStart = '▁';
  static const String label = '@';
  static const String separator = ' ';
  static const String labelJoiner = '_';
}

final RegExp _whitespace = RegExp(r'\s+');

/// Letters the English KWS vocabulary can possibly cover.
final RegExp _plainWords = RegExp(r"^[A-Z' ]+$");

/// Validation for the Settings keyword field. [vocab] is null until the
/// model is installed.
KeywordCheck checkKeyword(String text, KwsVocab? vocab) {
  final words = keywordWords(text);
  if (words.isEmpty) {
    return KeywordCheck.empty;
  }
  if (vocab == null) {
    final plain = _plainWords.hasMatch(words.join(KeywordSyntax.separator));
    return plain ? KeywordCheck.unverified : KeywordCheck.unsupported;
  }
  try {
    keywordToTokens(text, vocab);
    return KeywordCheck.ok;
  } on KeywordException {
    return KeywordCheck.unsupported;
  }
}

/// Upper-cased, single-spaced words; empty when [text] is blank.
List<String> keywordWords(String text) {
  final trimmed = text.trim().toUpperCase();
  if (trimmed.isEmpty) {
    return const [];
  }
  return trimmed.split(_whitespace);
}

/// Throws [KeywordException] when [text] is blank or a word has no
/// segmentation in [vocab].
List<String> keywordToTokens(String text, KwsVocab vocab) {
  final words = keywordWords(text);
  if (words.isEmpty) {
    throw const KeywordException(KeywordFault.empty);
  }
  return [for (final word in words) ..._tokenizeWord(word, vocab)];
}

/// One `keywords.txt` line: tokens then `@LABEL`, e.g.
/// `▁HE Y ▁SE N @HEY_SEN`.
String keywordLine(String text, KwsVocab vocab) {
  final tokens = keywordToTokens(text, vocab);
  final label = keywordWords(text).join(KeywordSyntax.labelJoiner);
  return [...tokens, '${KeywordSyntax.label}$label']
      .join(KeywordSyntax.separator);
}

List<String> _tokenizeWord(String word, KwsVocab vocab) {
  final pieces = <String>[];
  var start = 0;
  var prefix = KeywordSyntax.wordStart;
  while (start < word.length) {
    final end = _longestMatch(word, start, prefix, vocab);
    if (end != null) {
      pieces.add('$prefix${word.substring(start, end)}');
      start = end;
      prefix = '';
      continue;
    }
    if (prefix.isEmpty || !vocab.contains(prefix)) {
      throw KeywordException(KeywordFault.unknownToken, word);
    }
    // No piece starts the word: emit the bare marker and continue.
    pieces.add(prefix);
    prefix = '';
  }
  return pieces;
}

int? _longestMatch(String word, int start, String prefix, KwsVocab vocab) {
  for (var end = word.length; end > start; end--) {
    if (vocab.contains('$prefix${word.substring(start, end)}')) {
      return end;
    }
  }
  return null;
}
