import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/constants/app_constants.dart';
import '../core/media/rich_content.dart';

enum SaveResult { saved, failed }

abstract final class _Key {
  static const String title = 'title';
  static const String content = 'content';
  static const String category = 'category';
  static const String status = 'status';
  static const String ok = 'ok';
}

/// Pushes notes to the hub's `POST /save`, which writes them into the
/// Obsidian Second Brain on the Mac.
class HermesSyncService {
  HermesSyncService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const int _httpOk = 200;
  static const String _jsonType = 'application/json; charset=utf-8';

  Future<SaveResult> save(Uri uri, NoteDraft note) async {
    final http.Response response;
    try {
      response = await _client
          .post(
            uri,
            headers: {'content-type': _jsonType},
            body: jsonEncode({
              _Key.title: note.title,
              _Key.content: note.content,
              _Key.category: note.category.name,
            }),
          )
          .timeout(SyncDefaults.timeout);
    } on Exception {
      // ClientException, TimeoutException and TLS errors alike.
      return SaveResult.failed;
    }
    if (response.statusCode != _httpOk) {
      return SaveResult.failed;
    }
    return _isOk(response.body) ? SaveResult.saved : SaveResult.failed;
  }

  static bool _isOk(String body) {
    try {
      final json = jsonDecode(body);
      return json is Map && json[_Key.status] == _Key.ok;
    } on FormatException {
      return false;
    }
  }
}
