import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../core/constants/app_constants.dart';

/// Fetches MP3 speech from the hub's `GET /tts` for answers the hub did
/// not produce itself (Gemini).
class HubTtsService {
  HubTtsService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const int _httpOk = 200;

  /// Null when the hub is unreachable or synthesis failed.
  Future<Uint8List?> fetch(Uri uri, String text) async {
    final http.Response response;
    try {
      response = await _client
          .get(uri.replace(queryParameters: {HubTtsDefaults.textParam: text}))
          .timeout(HubTtsDefaults.timeout);
    } on Exception {
      return null;
    }
    if (response.statusCode != _httpOk || response.bodyBytes.isEmpty) {
      return null;
    }
    return response.bodyBytes;
  }
}
