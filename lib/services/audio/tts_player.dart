import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Speaks the hub's synthesized reply.
abstract interface class TtsPlayer {
  /// Replaces whatever is playing with [bytes] (an in-memory MP3).
  Future<void> play(Uint8List bytes);

  /// Halts playback immediately; [onComplete] does not fire.
  Future<void> stop();

  /// Fires when a clip plays to its end.
  Stream<void> get onComplete;

  /// True from [play] until the clip ends or [stop] is called.
  bool get isPlaying;

  Future<void> dispose();
}

final class DeviceTtsPlayer implements TtsPlayer {
  DeviceTtsPlayer({AudioPlayer? player}) : _player = player ?? AudioPlayer() {
    _ended = _player.onPlayerComplete.listen(_onEnded);
  }

  static const String _mime = 'audio/mpeg';

  final AudioPlayer _player;
  final StreamController<void> _complete = StreamController<void>.broadcast();
  late final StreamSubscription<void> _ended;
  bool _playing = false;

  @override
  bool get isPlaying => _playing;

  @override
  Stream<void> get onComplete => _complete.stream;

  @override
  Future<void> play(Uint8List bytes) async {
    _playing = true;
    try {
      await _player.play(BytesSource(bytes, mimeType: _mime));
    } on Object catch (error) {
      _playing = false;
      debugPrint('TTS playback failed: $error');
    }
  }

  @override
  Future<void> stop() async {
    _playing = false;
    try {
      await _player.stop();
    } on Object catch (error) {
      debugPrint('TTS stop failed: $error');
    }
  }

  void _onEnded(void _) {
    if (!_playing) {
      return;
    }
    _playing = false;
    _complete.add(null);
  }

  @override
  Future<void> dispose() async {
    _playing = false;
    await _ended.cancel();
    await _complete.close();
    await _player.dispose();
  }
}
