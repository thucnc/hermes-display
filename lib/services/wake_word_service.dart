import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../core/constants/app_constants.dart';
import 'audio/audio_frame.dart';
import 'audio/cue_player.dart';
import 'audio/endpointer.dart';
import 'audio/keyword_tokens.dart';
import 'audio/mic_coordinator.dart';
import 'audio/mic_source.dart';
import 'audio/wake_detector.dart';
import 'audio/wake_model_installer.dart';

export 'audio/endpointer.dart' show CaptureEnd;
export 'audio/keyword_tokens.dart' show KeywordCheck;
export 'audio/wake_detector.dart' show WakeConfig;

/// Where the pipeline is. Mic frames are routed according to this.
enum VoicePhase {
  /// [WakeWordService.start] not called yet, or disposed.
  off,

  /// Feeding the keyword spotter (mic open only if a model is loaded).
  armed,

  /// Keyword fired; mic released until the owner decides.
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

  /// Another recorder holds the mic, or the turn was cancelled while
  /// starting.
  micBusy,
}

/// What happens to the wake-word mic when the app leaves the foreground.
enum BackgroundMode {
  /// Release on pause; resume when the app returns.
  releaseMic,

  /// A microphone foreground service keeps the process eligible, so keep
  /// spotting through screen-off and backgrounding.
  keepListening,
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
    MicCoordinator? coordinator,
  }) : _mic = mic,
       _detector = detector,
       _cue = cue,
       _endpointer = endpointer ?? Endpointer(),
       _coordinator = coordinator ?? MicCoordinator();

  /// Production wiring: `record` mic, sherpa-onnx KWS, synthesized chirp.
  factory WakeWordService.device(WakeModelInstaller installer) {
    return WakeWordService(
      mic: RecordMicSource(),
      detector: SherpaWakeDetector(locate: installer.installed),
      cue: ToneCuePlayer(),
    );
  }

  final MicCoordinator _coordinator;
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
  StreamSubscription<MicOwner?>? _ownerChanges;
  MicLease? _lease;

  /// Set when another owner held the mic; cleared by the retry.
  bool _waitingForMic = false;
  AppLifecycleListener? _lifecycle;
  BackgroundMode _background = BackgroundMode.releaseMic;

  /// Serializes mic open/close so lifecycle bursts cannot interleave.
  Future<void> _queue = Future<void>.value();

  Stream<VoiceEvent> get events => _events.stream;
  VoicePhase get phase => _phase;
  bool get micOpen => _frames != null;
  MicOwner? get micOwner => _lease?.owner;

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
    _ownerChanges = _coordinator.changes.listen(_onOwnerChange);
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

  /// Reloads the spotter, e.g. once the model finished installing.
  Future<VoiceStatus> reloadModel() async {
    final config = _config;
    if (_phase == VoicePhase.off || config == null) {
      return status;
    }
    if (_permission != MicPermission.granted) {
      return status;
    }
    _detectorReady = await _detector.load(config);
    await _sync();
    return status;
  }

  KeywordCheck checkKeyword(String keyword) => _detector.check(keyword);

  void setBackgroundMode(BackgroundMode mode) => _background = mode;

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
    if (state != AppLifecycleState.detached &&
        _background == BackgroundMode.keepListening) {
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
    if (_lease?.owner == MicOwner.voiceTurn && micOpen) {
      return VoiceStatus.ready;
    }
    final failed = _micFailed;
    if (_phase == VoicePhase.capturing) {
      _rearm();
      await _sync();
    }
    return failed ? VoiceStatus.micFailed : VoiceStatus.micBusy;
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
    await _ownerChanges?.cancel();
    _ownerChanges = null;
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
          // Hand the mic back before the voice turn asks for it.
          unawaited(_sync());
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
    debugPrint('_capture frame: rms=${frame.rms}');
    final level = (frame.rms * VoiceLevels.meterGain).clamp(0.0, 1.0);
    _emit(SpeechAudio(frame.pcm, level));
    final end = _endpointer.feed(frame);
    if (end == null) {
      return;
    }
    debugPrint('_capture ended with: $end');
    _rearm();
    _emit(CaptureDone(end));
    unawaited(_sync());
  }

  void _rearm() {
    _phase = VoicePhase.armed;
    _detector.reset();
  }

  MicOwner? get _wantedOwner {
    if (_permission != MicPermission.granted) {
      return null;
    }
    return switch (_phase) {
      VoicePhase.armed => _detectorReady ? MicOwner.wakeWord : null,
      VoicePhase.capturing => MicOwner.voiceTurn,
      VoicePhase.off || VoicePhase.woken || VoicePhase.paused => null,
    };
  }

  /// Moves the mic to the owner the phase calls for: release first, then
  /// acquire, so wake word and voice turn never overlap.
  Future<void> _sync() => _serial(() async {
    final wanted = _wantedOwner;
    if (_lease?.owner != wanted) {
      await _releaseMic();
    }
    if (wanted == null) {
      return;
    }
    _lease ??= _coordinator.tryAcquire(wanted);
    if (_lease == null) {
      // Someone else records; _onOwnerChange retries when they finish.
      _waitingForMic = true;
      return;
    }
    await _openMic();
    if (!micOpen) {
      _releaseLease();
    }
  });

  void _onOwnerChange(MicOwner? owner) {
    if (owner != null || !_waitingForMic) {
      return;
    }
    _waitingForMic = false;
    unawaited(_sync());
  }

  void _releaseLease() {
    final lease = _lease;
    if (lease == null) {
      return;
    }
    _lease = null;
    _coordinator.release(lease);
  }

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
      _releaseLease();
      return;
    }
    _frames = null;
    await frames.cancel();
    try {
      await _mic.close();
    } on Object catch (error) {
      debugPrint('Mic close failed: $error');
    }
    _releaseLease();
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
