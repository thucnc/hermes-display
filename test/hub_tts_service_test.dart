import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_display/services/hub_tts_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final uri = Uri.parse('http://hub:8901/tts');
  final mp3 = Uint8List.fromList([0x49, 0x44, 0x33, 0x03]);

  test('returns MP3 bytes for the text', () async {
    late Uri asked;
    final service = HubTtsService(
      client: MockClient((request) async {
        asked = request.url;
        return http.Response.bytes(mp3, 200);
      }),
    );
    expect(await service.fetch(uri, 'Xin chào'), mp3);
    expect(asked.path, '/tts');
    expect(asked.queryParameters['text'], 'Xin chào');
  });

  test('HTTP error or empty body yields null', () async {
    for (final response in [
      http.Response('nope', 502),
      http.Response.bytes(const [], 200),
    ]) {
      final service = HubTtsService(client: MockClient((_) async => response));
      expect(await service.fetch(uri, 'a'), isNull);
    }
  });

  test('unreachable hub yields null', () async {
    final service = HubTtsService(
      client: MockClient((_) async => throw http.ClientException('down')),
    );
    expect(await service.fetch(uri, 'a'), isNull);
  });
}
