import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../core/constants/app_constants.dart';
import 'audio/audio_frame.dart';
import 'audio/cue_player.dart';
import 'audio/endpointer.dart';
import 'audio/mic_source.dart';
import 'audio/wake_detector.dart';

export 'audio/endpointer.dart' show CaptureEnd;
export 'audio/wake_detector.dart' show WakeConfig;

/// Where the pipeline is. Mic frames are routed according to this.
enum VoicePhase {
  /// [WakeWordService.start] not called yet, or disposed.
  off,

  /// Feeding the keyword spotter (mic open only if a model is loaded).
  armed,

  /// Keyword fired; frames are dropped until the owner decides.
  woken,

  /// Forwarding user speech and watching for end of utterance.
  capturing,

  /// App backgrounded; mic released.
  paused,
}

enum VoiceStatus {
  /// Wake word and capture both available.
  ready,

  /// No keyword model on device; capture works from the mic button.
  manualOnly,

  /// RECORD_AUDIO not granted; user can retry from the mic button.
  noPermission,

  /// Permanently denied; only system settings can fix it.
  blocked,

  /// Hardware refused to open.
  micFailed,
}

sealed class VoiceEvent {
  const VoiceEvent();
}

final class WakeHeard extends VoiceEvent {
  const WakeHeard();
}

final class SpeechAudio extends VoiceEvent {
  const SpeechAudio(this.pcm, this.level);

  /// PCM16 LE mono at [AudioSpec.sampleRate].
  final Uint8List pcm;

  /// Meter value 0..1 for the waveform.
  final double level;
}

final class CaptureDone extends VoiceEvent {
  const CaptureDone(this.reason);
  final CaptureEnd reason;
}

/// Always-on "Hey Sen" spotting plus utterance capture on one mic stream.
class WakeWordService {
  WakeWordService({
    required MicSource mic,
    required WakeDetector detector,
    required CuePlayer cue,
    Endpointer? endpointer,
  }) : _mic = mic,
       _detector = detector,
       _cue = cue,
       _endpointer = endpointer ?? Endpointer();

  /// Production wiring: `record` mic, sherpa-onnx KWS, synthesized chirp.
  factory WakeWordService.device() {
    return WakeWordService(
      mic: RecordMicSource(),
      detector: SherpaWakeDetector(),
      cue: ToneCuePlayer(),
    );
  }

  final MicSource _mic;
  final WakeDetector _detector;
  final CuePlayer _cue;
  final Endpointer _endpointer;
  final StreamController<VoiceEvent> _events =
      StreamController<VoiceEvent>.broadcast();

  VoicePhase _phase = VoicePhase.off;
  MicPermission _permission = MicPermission.denied;
  bool _detectorReady = false;
  bool _micFailed = false;
  WakeConfig? _config;
  StreamSubscription<AudioFrame>? _frames;
  AppLifecycleListener? _lifecycle;

  /// Serializes mic open/close so lifecycle bursts cannot interleave.
  Future<void> _queue = Future<void>.value();

  Stream<VoiceEvent> get events => _events.stream;
  VoicePhase get phase => _phase;
  bool get micOpen => _frames != null;

  VoiceStatus get status {
    if (_permission == MicPermission.permanentlyDenied) {
      return VoiceStatus.blocked;
    }
    if (_permission != MicPermission.granted) {
      return VoiceStatus.noPermission;
    }
    if (_micFailed) {
      return VoiceStatus.micFailed;
    }
    return _detectorReady ? VoiceStatus.ready : VoiceStatus.manualOnly;
  }

  Future<VoiceStatus> start(WakeConfig config) async {
    if (_phase != VoicePhase.off) {
      return status;
    }
    _config = config;
    _phase = VoicePhase.armed;
    _permission = await _askPermission();
    if (_permission == MicPermission.granted) {
      _detectorReady = await _detector.load(config);
    }
    await _sync();
    return status;
  }

  /// Reloads the spotter when keyword or sensitivity changed.
  Future<void> configure(WakeConfig config) async {
    if (config == _config) {
      return;
    }
    _config = config;
    if (_phase == VoicePhase.off || _permission != MicPermission.granted) {
      return;
    }
    await _closeMic();
    _detectorReady = await _detector.load(config);
    await _sync();
  }

  /// Binds pause/resume to the app lifecycle. Call once from `main`.
  void attachLifecycle() {
    _lifecycle ??= AppLifecycleListener(onStateChange: handleLifecycle);
  }

  void handleLifecycle(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(resume());
      return;
    }
    if (state == AppLifecycleState.inactive) {
      // Transient (notification shade, dialogs); keep listening.
      return;
    }
    unawaited(pause());
  }

  Future<void> pause() async {
    if (_phase == VoicePhase.off || _phase == VoicePhase.paused) {
      return;
    }
    final interrupted =
        _phase == VoicePhase.capturing || _phase == VoicePhase.woken;
    _phase = VoicePhase.paused;
    if (interrupted) {
      _emit(const CaptureDone(CaptureEnd.stopped));
    }
    await _sync();
  }

  Future<void> resume() async {
    if (_phase != VoicePhase.paused) {
      return;
    }
    _phase = VoicePhase.armed;
    _detector.reset();
    await _sync();
  }

  Future<void> playCue() => _cue.play();

  /// Starts forwarding speech. Retries permission so a user who denied
  /// it once can still grant it from the mic button.
  Future<VoiceStatus> beginCapture() async {
    if (_phase == VoicePhase.off || _phase == VoicePhase.paused) {
      return status;
    }
    if (_permission == MicPermission.denied) {
      _permission = await _askPermission();
      await _loadIfNeeded();
    }
    if (_permission != MicPermission.granted) {
      return status;
    }
    _micFailed = false;
    _endpointer.reset();
    _phase = VoicePhase.capturing;
    await _sync();
    if (!micOpen) {
      _phase = VoicePhase.armed;
      return status;
    }
    return VoiceStatus.ready;
  }

  /// Back to spotting. No-op unless woken or capturing.
  Future<void> endCapture() async {
    if (_phase != VoicePhase.capturing && _phase != VoicePhase.woken) {
      return;
    }
    _rearm();
    await _sync();
  }

  Future<void> dispose() async {
    _lifecycle?.dispose();
    _lifecycle = null;
    _phase = VoicePhase.off;
    await _sync();
    _detector.dispose();
    await _mic.dispose();
    await _cue.dispose();
    await _events.close();
  }

  Future<MicPermission> _askPermission() async {
    try {
      return await _mic.ensurePermission();
    } on Object catch (error) {
      debugPrint('Mic permission check failed: $error');
      return MicPermission.denied;
    }
  }

  Future<void> _loadIfNeeded() async {
    final config = _config;
    if (_detectorReady || config == null) {
      return;
    }
    if (_permission != MicPermission.granted) {
      return;
    }
    _detectorReady = await _detector.load(config);
  }

  void _onFrame(AudioFrame frame) {
    switch (_phase) {
      case VoicePhase.armed:
        if (_detector.accept(frame)) {
          _phase = VoicePhase.woken;
          _emit(const WakeHeard());
        }
      case VoicePhase.capturing:
        _capture(frame);
      case VoicePhase.off:
      case VoicePhase.woken:
      case VoicePhase.paused:
        return;
    }
  }

  void _capture(AudioFrame frame) {
    final level = (frame.rms * VoiceLevels.meterGain).clamp(0.0, 1.0);
    _emit(SpeechAudio(frame.pcm, level));
    final end = _endpointer.feed(frame);
    if (end == null) {
      return;
    }
    _rearm();
    _emit(CaptureDone(end));
    unawaited(_sync());
  }

  void _rearm() {
    _phase = VoicePhase.armed;
    _detector.reset();
  }

  bool get _wantsMic {
    if (_permission != MicPermission.granted) {
      return false;
    }
    return switch (_phase) {
      VoicePhase.armed => _detectorReady,
      VoicePhase.woken || VoicePhase.capturing => true,
      VoicePhase.off || VoicePhase.paused => false,
    };
  }

  Future<void> _sync() => _serial(() async {
    if (_wantsMic) {
      await _openMic();
      return;
    }
    await _releaseMic();
  });

  Future<void> _closeMic() => _serial(_releaseMic);

  Future<void> _serial(Future<void> Function() op) {
    final next = _queue.then((_) => op());
    _queue = next.catchError((Object _) {});
    return next;
  }

  Future<void> _openMic() async {
    if (micOpen) {
      return;
    }
    try {
      final stream = await _mic.open();
      _frames = stream.listen(_onFrame, onError: _onMicError);
      _micFailed = false;
    } on Object catch (error) {
      debugPrint('Mic unavailable: $error');
      _micFailed = true;
    }
  }

  Future<void> _releaseMic() async {
    final frames = _frames;
    if (frames == null) {
      return;
    }
    _frames = null;
    await frames.cancel();
    try {
      await _mic.close();
    } on Object catch (error) {
      debugPrint('Mic close failed: $error');
    }
  }

  void _onMicError(Object error) {
    debugPrint('Mic stream error: $error');
    _micFailed = true;
    final capturing = _phase == VoicePhase.capturing;
    if (capturing) {
      _rearm();
      _emit(const CaptureDone(CaptureEnd.stopped));
    }
    unawaited(_closeMic());
  }

  void _emit(VoiceEvent event) {
    if (_events.isClosed) {
      return;
    }
    _events.add(event);
  }
}
