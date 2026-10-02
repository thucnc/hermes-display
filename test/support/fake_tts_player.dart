import 'dart:async';
import 'dart:typed_data';

import 'package:hermes_display/services/audio/tts_player.dart';

/// Plays nothing; tests end playback with [finish].
class FakeTtsPlayer implements TtsPlayer {
  final StreamController<void> _complete = StreamController<void>.broadcast();
  final List<Uint8List> played = [];
  int stops = 0;
  bool disposed = false;
  bool _playing = false;

  @override
  bool get isPlaying => _playing;

  @override
  Stream<void> get onComplete => _complete.stream;

  @override
  Future<void> play(Uint8List bytes) async {
    played.add(bytes);
    _playing = true;
  }

  @override
  Future<void> stop() async {
    stops++;
    _playing = false;
  }

  /// Simulates the clip reaching its end.
  void finish() {
    _playing = false;
    _complete.add(null);
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    await _complete.close();
  }
}
