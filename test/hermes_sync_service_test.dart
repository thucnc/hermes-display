import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_display/core/media/rich_content.dart';
import 'package:hermes_display/services/hermes_sync_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const note = NoteDraft(
    title: 'Phở bò',
    content: '1. Ninh xương',
    category: NoteCategory.recipes,
  );
  final uri = Uri.parse('http://10.0.0.2:8901/save');

  test('posts title, content and category as JSON', () async {
    late http.Request seen;
    final sync = HermesSyncService(
      client: MockClient((request) async {
        seen = request;
        return http.Response('{"status":"ok","path":"/x.md"}', 200);
      }),
    );
    expect(await sync.save(uri, note), SaveResult.saved);
    expect(seen.url, uri);
    expect(seen.headers['content-type'], startsWith('application/json'));
    expect(jsonDecode(seen.body), {
      'title': 'Phở bò',
      'content': '1. Ninh xương',
      'category': 'recipes',
    });
  });

  test('HTTP error, bad body and network failure are failures', () async {
    for (final client in [
      MockClient((_) async => http.Response('{"error":"x"}', 400)),
      MockClient((_) async => http.Response('{"status":"nope"}', 200)),
      MockClient((_) async => http.Response('oops', 200)),
      MockClient((_) async => throw http.ClientException('down')),
    ]) {
      final sync = HermesSyncService(client: client);
      expect(await sync.save(uri, note), SaveResult.failed);
    }
  });
}
