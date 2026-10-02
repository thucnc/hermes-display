import 'dart:async';
import 'dart:typed_data';

import 'package:hermes_display/services/audio/pcm_player.dart';

/// Records chunks; tests end playback with [drain].
class FakePcmPlayer implements PcmPlayer {
  final StreamController<void> _complete = StreamController<void>.broadcast();
  final List<Uint8List> chunks = [];
  final List<int> rates = [];
  int finishes = 0;
  int stops = 0;
  bool _playing = false;

  @override
  bool get isPlaying => _playing;

  @override
  Stream<void> get onComplete => _complete.stream;

  @override
  void add(Uint8List pcm, int sampleRate) {
    chunks.add(pcm);
    rates.add(sampleRate);
    _playing = true;
  }

  @override
  void finish() => finishes++;

  @override
  Future<void> stop() async {
    stops++;
    _playing = false;
  }

  /// Simulates the queued reply playing out.
  void drain() {
    _playing = false;
    _complete.add(null);
  }

  @override
  Future<void> dispose() => _complete.close();
}
