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
      final speech = msg! as SpeechMessage;
      expect(speech.text, 'Xin chào');
      expect(speech.audioBytes, isNull);
    });

    test('parses tts audio from base64', () {
      final mp3 = [0x49, 0x44, 0x33, 0x03, 0xff];
      final raw = jsonEncode({
        WireKey.type: WireType.tts,
        WireKey.text: 'Xin chào',
        WireKey.audio: base64Encode(mp3),
      });
      final speech = HermesCodec.decode(raw)! as SpeechMessage;
      expect(speech.text, 'Xin chào');
      expect(speech.audioBytes, mp3);
    });

    test('keeps tts text when audio is malformed', () {
      final speech =
          HermesCodec.decode('{"type":"tts","text":"hi","audio":"%%%"}')!
              as SpeechMessage;
      expect(speech.text, 'hi');
      expect(speech.audioBytes, isNull);
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
