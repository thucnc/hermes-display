import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_display/core/state/display_state.dart';
import 'package:hermes_display/services/protocol/hermes_message.dart';

void main() {
  group('HermesCodec.decode', () {
    test('parses state', () {
      final msg = HermesCodec.decode('{"type":"state","state":"THINKING"}');
      expect(msg, isA<StateMessage>());
      expect((msg! as StateMessage).state, DisplayState.thinking);
    });

    test('parses tts text', () {
      final msg = HermesCodec.decode('{"type":"tts","text":"Xin chào"}');
      expect((msg! as SpeechMessage).text, 'Xin chào');
    });

    test('parses final transcript', () {
      final msg = HermesCodec.decode(
        '{"type":"transcript","text":"hi","final":true}',
      );
      expect((msg! as TranscriptMessage).isFinal, isTrue);
    });

    test('clamps level', () {
      final msg = HermesCodec.decode('{"type":"level","level":3}');
      expect((msg! as LevelMessage).level, 1);
    });

    test('rejects malformed input', () {
      expect(HermesCodec.decode('not json'), isNull);
      expect(HermesCodec.decode('[1,2]'), isNull);
      expect(HermesCodec.decode('{"type":"state","state":"dance"}'), isNull);
      expect(HermesCodec.decode('{"type":"tts","text":42}'), isNull);
      expect(HermesCodec.decode('{"type":"unknown"}'), isNull);
      expect(HermesCodec.decode(null), isNull);
    });
  });

  test('encodes user text', () {
    final map = jsonDecode(HermesCodec.userText('bật đèn')) as Map;
    expect(map[WireKey.type], WireType.textInput);
    expect(map[WireKey.text], 'bật đèn');
  });
}
