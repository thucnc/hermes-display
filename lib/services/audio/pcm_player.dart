import 'dart:async';
import 'dart:typed_data';

import '../../core/constants/app_constants.dart';
import 'cue_player.dart';
import 'tts_player.dart';

/// Plays a reply that arrives as a stream of raw PCM16 mono chunks.
abstract interface class PcmPlayer {
  /// Queues [pcm]; playback starts once enough audio is buffered.
  void add(Uint8List pcm, int sampleRate);

  /// No more chunks for this reply; [onComplete] fires once the queue
  /// plays out. No-op when nothing was added.
  void finish();

  /// Drops queued audio; [onComplete] does not fire.
  Future<void> stop();

  Stream<void> get onComplete;

  /// True from the first [add] until the reply ends or [stop].
  bool get isPlaying;

  Future<void> dispose();
}

/// Streams through a clip player by wrapping buffered PCM in WAV
/// segments: the first after [GeminiLiveDefaults.startBuffer], then
/// whatever arrived while the previous one played.
final class SegmentPcmPlayer implements PcmPlayer {
  SegmentPcmPlayer({required TtsPlayer clips}) : _clips = clips {
    _ended = _clips.onComplete.listen(_onClipEnd);
  }

  static const int _msPerSecond = 1000;

  final TtsPlayer _clips;
  final StreamController<void> _complete = StreamController<void>.broadcast();
  late final StreamSubscription<void> _ended;
  final BytesBuilder _pending = BytesBuilder(copy: false);
  int _rate = GeminiLiveDefaults.outputRate;
  bool _active = false;
  bool _clipPlaying = false;
  bool _finished = false;

  @override
  bool get isPlaying => _active;

  @override
  Stream<void> get onComplete => _complete.stream;

  @override
  void add(Uint8List pcm, int sampleRate) {
    if (!_active) {
      _active = true;
      _finished = false;
    }
    _rate = sampleRate;
    _pending.add(pcm);
    if (!_clipPlaying && _buffered >= GeminiLiveDefaults.startBuffer) {
      _playPending();
    }
  }

  @override
  void finish() {
    if (!_active) {
      return;
    }
    _finished = true;
    if (_clipPlaying) {
      return;
    }
    _advance();
  }

  @override
  Future<void> stop() async {
    final wasPlaying = _clipPlaying;
    _reset();
    if (wasPlaying) {
      await _clips.stop();
    }
  }

  Duration get _buffered {
    final bytesPerMs = _rate * AudioSpec.bytesPerSample / _msPerSecond;
    return Duration(milliseconds: _pending.length ~/ bytesPerMs);
  }

  void _onClipEnd(void _) {
    if (!_clipPlaying) {
      return;
    }
    _clipPlaying = false;
    _advance();
  }

  /// Next segment, or the end of the reply once [finish] was called.
  void _advance() {
    if (_pending.isNotEmpty &&
        (_finished || _buffered >= GeminiLiveDefaults.startBuffer)) {
      _playPending();
      return;
    }
    if (!_finished || _pending.isNotEmpty) {
      return;
    }
    _reset();
    _complete.add(null);
  }

  void _playPending() {
    final pcm = _pending.takeBytes();
    _clipPlaying = true;
    final samples = Int16List.sublistView(
      pcm,
      0,
      pcm.length ~/ AudioSpec.bytesPerSample * AudioSpec.bytesPerSample,
    );
    unawaited(_clips.play(ToneSynth.wav(samples, sampleRate: _rate)));
  }

  void _reset() {
    _active = false;
    _clipPlaying = false;
    _finished = false;
    _pending.clear();
  }

  @override
  Future<void> dispose() async {
    _reset();
    await _ended.cancel();
    await _complete.close();
    await _clips.dispose();
  }
}
