import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_display/services/gemini_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const key = 'k-123';

  Map<String, Object?> reply(String text, {List<String> uris = const []}) {
    return {
      'candidates': [
        {
          'content': {
            'parts': [
              {'text': text},
            ],
          },
          'groundingMetadata': {
            'groundingChunks': [
              for (final uri in uris)
                {
                  'web': {'uri': uri, 'title': 'youtube.com'},
                },
            ],
          },
        },
      ],
    };
  }

  test('posts prompt, system instruction and google_search tool', () async {
    late http.Request seen;
    final service = HttpGeminiService(
      client: MockClient((request) async {
        seen = request;
        return http.Response.bytes(
          utf8.encode(jsonEncode(reply('Chào bạn'))),
          200,
        );
      }),
    );
    final answer = await service.ask('xin chào', key);
    expect(answer.text, 'Chào bạn');
    expect(seen.method, 'POST');
    expect(
      seen.url.toString(),
      'https://generativelanguage.googleapis.com/v1beta/models/'
      'gemini-3.8-flash:generateContent?key=k-123',
    );
    final body = jsonDecode(seen.body) as Map<String, dynamic>;
    expect(body['tools'], [
      {'google_search': <String, Object?>{}},
    ]);
    expect(
      body['system_instruction']['parts'][0]['text'],
      GeminiService.systemPrompt,
    );
    expect(body['contents'][0]['parts'][0]['text'], 'xin chào');
  });

  test(
    'joins parts and extracts YouTube videos from text and grounding',
    () async {
      final payload = reply(
        'Xem [Phở](https://youtu.be/abcdefghijk)',
        uris: ['https://www.youtube.com/watch?v=ZYXWVUTSRQP'],
      );
      (payload['candidates']! as List).first['content']['parts'].add({
        'text': ' nhé',
      });
      final service = HttpGeminiService(
        client: MockClient((_) async {
          return http.Response.bytes(utf8.encode(jsonEncode(payload)), 200);
        }),
      );
      final answer = await service.ask('phở', key);
      expect(answer.text, 'Xem [Phở](https://youtu.be/abcdefghijk) nhé');
      expect(answer.videos.map((v) => v.id), ['abcdefghijk', 'ZYXWVUTSRQP']);
      expect(answer.videos.first.title, 'Phở');
    },
  );

  test('missing key, HTTP errors and empty answers throw', () async {
    final ok = HttpGeminiService(
      client: MockClient((_) async => http.Response('{}', 200)),
    );
    await expectLater(ok.ask('q', ''), throwsA(isA<GeminiException>()));
    await expectLater(ok.ask('q', key), throwsA(isA<GeminiException>()));

    final denied = HttpGeminiService(
      client: MockClient((_) async => http.Response('nope', 403)),
    );
    await expectLater(denied.ask('q', key), throwsA(isA<GeminiException>()));

    final broken = HttpGeminiService(
      client: MockClient((_) async => http.Response('<html>', 200)),
    );
    await expectLater(broken.ask('q', key), throwsA(isA<GeminiException>()));

    final offline = HttpGeminiService(
      client: MockClient((_) async => throw http.ClientException('down')),
    );
    await expectLater(offline.ask('q', key), throwsA(isA<GeminiException>()));
  });

  test('memory context is prepended to the system prompt', () async {
    late http.Request seen;
    final service = HttpGeminiService(
      client: MockClient((request) async {
        seen = request;
        return http.Response.bytes(utf8.encode(jsonEncode(reply('ok'))), 200);
      }),
    );
    await service.ask('q', key, memoryContext: 'Đang nói chuyện với: Mẹ');
    final body = jsonDecode(seen.body) as Map<String, dynamic>;
    expect(
      body['system_instruction']['parts'][0]['text'],
      'Đang nói chuyện với: Mẹ\n\n${GeminiService.systemPrompt}',
    );
  });

  group('askAudio', () {
    final wav = Uint8List.fromList([0x52, 0x49, 0x46, 0x46, 1, 2, 3]);

    Future<(GeminiReply, Map<String, dynamic>)> run(String text) async {
      late http.Request seen;
      final service = HttpGeminiService(
        client: MockClient((request) async {
          seen = request;
          return http.Response.bytes(utf8.encode(jsonEncode(reply(text))), 200);
        }),
      );
      final answer = await service.askAudio(wav, key);
      return (answer, jsonDecode(seen.body) as Map<String, dynamic>);
    }

    test('sends the WAV as inlineData and splits the transcript', () async {
      final (answer, body) = await run(
        '${GeminiService.transcriptTag} mấy giờ rồi\nBây giờ là 9 giờ.',
      );
      final parts = body['contents'][0]['parts'] as List;
      expect(parts[0]['text'], GeminiService.audioPrompt);
      expect(parts[1]['inlineData'], {
        'mimeType': 'audio/wav',
        'data': base64Encode(wav),
      });
      expect(answer.transcript, 'mấy giờ rồi');
      expect(answer.text, 'Bây giờ là 9 giờ.');
    });

    test('bold tag is tolerated, missing tag keeps the whole text', () async {
      final (bold, _) = await run(
        '**${GeminiService.transcriptTag}** chào Sen\nChào bạn!',
      );
      expect(bold.transcript, 'chào Sen');
      expect(bold.text, 'Chào bạn!');

      final (plain, _) = await run('Chào bạn!');
      expect(plain.transcript, isEmpty);
      expect(plain.text, 'Chào bạn!');
    });

    test('missing key throws', () async {
      final service = HttpGeminiService(
        client: MockClient((_) async => http.Response('{}', 200)),
      );
      await expectLater(
        service.askAudio(wav, ''),
        throwsA(isA<GeminiException>()),
      );
    });
  });
}
