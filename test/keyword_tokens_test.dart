import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_display/services/audio/keyword_tokens.dart';

/// Subset of the gigaspeech 3.3M `tokens.txt` (token, id per line).
const String _tokensTxt = '''
<blk> 0
<sos/eos> 1
<unk> 2
S 3
N 10
Y 17
▁HE 49
▁SE 120
▁HER 200
ME 201
▁ 300
X 301
IN 302
''';

void main() {
  final vocab = KwsVocab.parse(_tokensTxt);

  test('parses tokens and skips special symbols', () {
    expect(vocab.contains('▁HE'), isTrue);
    expect(vocab.contains('<blk>'), isFalse);
  });

  test('HEY SEN matches the sentencepiece segmentation', () {
    expect(keywordToTokens('HEY SEN', vocab), ['▁HE', 'Y', '▁SE', 'N']);
  });

  test('normalises case and whitespace', () {
    expect(keywordToTokens('  hey \t  sen ', vocab), ['▁HE', 'Y', '▁SE', 'N']);
  });

  test('prefers the longest piece at each step', () {
    expect(keywordToTokens('HERMES', vocab), ['▁HER', 'ME', 'S']);
  });

  test('falls back to a bare word marker', () {
    expect(keywordToTokens('XIN', vocab), ['▁', 'X', 'IN']);
  });

  test('builds the keywords.txt line with a label', () {
    expect(keywordLine('hey sen', vocab), '▁HE Y ▁SE N @HEY_SEN');
  });

  test('variants missing from the vocabulary are skipped', () {
    expect(keywordLines('HEY SEN', vocab), [
      '▁HE Y ▁SE N @HEY_SEN',
      '▁HE ▁SE N @HEY_SEN',
    ]);
  });

  test('empty input is rejected', () {
    expect(
      () => keywordToTokens('   ', vocab),
      throwsA(
        isA<KeywordException>().having(
          (e) => e.fault,
          'fault',
          KeywordFault.empty,
        ),
      ),
    );
  });

  test('unknown piece names the offending word', () {
    expect(
      () => keywordToTokens('HEY ZEN', vocab),
      throwsA(
        isA<KeywordException>()
            .having((e) => e.fault, 'fault', KeywordFault.unknownToken)
            .having((e) => e.word, 'word', 'ZEN'),
      ),
    );
  });

  test('diacritics are not in the vocabulary', () {
    expect(
      () => keywordToTokens('HÊY SEN', vocab),
      throwsA(isA<KeywordException>()),
    );
  });

  group('real gigaspeech 3.3M tokens.txt', () {
    // Expected values come from sentencepiece on the model's bpe.model.
    final real = KwsVocab.parse(
      File('test/fixtures/kws_tokens.txt').readAsStringSync(),
    );

    test('HEY SEN', () {
      expect(keywordLine('HEY SEN', real), '▁HE Y ▁SE N @HEY_SEN');
    });

    test('HEY SEN adds Vietnamese-accent variants under one label', () {
      expect(keywordLines('hey sen', real), [
        '▁HE Y ▁SE N @HEY_SEN',
        '▁HA Y ▁SE N @HEY_SEN',
        '▁HE ▁SE N @HEY_SEN',
      ]);
    });

    test('other keywords get a single line', () {
      expect(keywordLines('HEY HERMES', real), ['▁HE Y ▁HER ME S @HEY_HERMES']);
    });

    test('HEY HERMES matches the reference keywords.txt', () {
      expect(keywordToTokens('HEY HERMES', real), [
        '▁HE',
        'Y',
        '▁HER',
        'ME',
        'S',
      ]);
    });
  });

  group('checkKeyword', () {
    test('tokenisable keyword is ok', () {
      expect(checkKeyword('hey sen', vocab), KeywordCheck.ok);
    });

    test('blank keyword is empty', () {
      expect(checkKeyword('  ', vocab), KeywordCheck.empty);
    });

    test('untokenisable keyword is unsupported', () {
      expect(checkKeyword('HEY ZEN', vocab), KeywordCheck.unsupported);
    });

    test('without a model only plain letters pass, unverified', () {
      expect(checkKeyword('hey sen', null), KeywordCheck.unverified);
      expect(checkKeyword('xin chào', null), KeywordCheck.unsupported);
    });
  });
}
