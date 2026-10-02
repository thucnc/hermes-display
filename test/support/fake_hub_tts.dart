import 'dart:async';
import 'dart:typed_data';

import 'package:hermes_display/services/hub_tts_service.dart';

/// Requests are completed by the test; null means TTS failed.
class FakeHubTts implements HubTtsService {
  final List<(Uri, String)> asked = [];
  final List<Completer<Uint8List?>> pending = [];

  @override
  Future<Uint8List?> fetch(Uri uri, String text) {
    asked.add((uri, text));
    final completer = Completer<Uint8List?>();
    pending.add(completer);
    return completer.future;
  }

  void reply(Uint8List? bytes) => pending.removeAt(0).complete(bytes);
}
