import '../../core/constants/app_constants.dart';
import 'audio_frame.dart';

enum CaptureEnd {
  /// Speech was heard, followed by enough trailing silence.
  speechEnded,

  /// Nothing above the speech threshold before [VoiceTiming.noSpeech].
  noSpeech,

  /// Utterance hit [VoiceTiming.maxUtterance].
  maxLength,

  /// Stopped from outside (cancel, state change, app paused).
  stopped,
}

/// Energy-based end-of-utterance detection. Time is derived from sample
/// counts, so results are deterministic and need no timers.
final class Endpointer {
  Endpointer({
    this.speechRms = VoiceLevels.speechRms,
    this.endSilence = VoiceTiming.endSilence,
    Duration? noSpeech,
    this.maxUtterance = VoiceTiming.maxUtterance,
  })  : defaultNoSpeech = noSpeech ?? VoiceTiming.noSpeech,
        _turnNoSpeech = noSpeech ?? VoiceTiming.noSpeech;

  final double speechRms;
  final Duration endSilence;
  final Duration defaultNoSpeech;
  Duration _turnNoSpeech;
  final Duration maxUtterance;

  Duration get noSpeech => _turnNoSpeech;

  Duration _elapsed = Duration.zero;
  Duration _silence = Duration.zero;
  bool _heardSpeech = false;

  /// Returns the reason capture should end, or null to keep going.
  CaptureEnd? feed(AudioFrame frame) {
    _elapsed += frame.duration;
    if (frame.rms >= speechRms) {
      _heardSpeech = true;
      _silence = Duration.zero;
    } else {
      _silence += frame.duration;
    }
    if (_elapsed >= maxUtterance) {
      return CaptureEnd.maxLength;
    }
    if (!_heardSpeech) {
      return _elapsed >= _turnNoSpeech ? CaptureEnd.noSpeech : null;
    }
    return _silence >= endSilence ? CaptureEnd.speechEnded : null;
  }

  void reset({Duration? noSpeech}) {
    _turnNoSpeech = noSpeech ?? defaultNoSpeech;
    _elapsed = Duration.zero;
    _silence = Duration.zero;
    _heardSpeech = false;
  }
}
