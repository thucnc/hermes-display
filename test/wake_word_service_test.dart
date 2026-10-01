import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_display/core/constants/app_constants.dart';
import 'package:hermes_display/services/audio/mic_coordinator.dart';
import 'package:hermes_display/services/audio/mic_source.dart';
import 'package:hermes_display/services/wake_word_service.dart';

import 'support/fake_voice.dart';

void main() {
  late FakeMic mic;
  late FakeDetector detector;
  late FakeCue cue;
  late WakeWordService service;
  late MicCoordinator lease;
  late List<VoiceEvent> events;

  void build({
    MicPermission permission = MicPermission.granted,
    bool model = true,
  }) {
    mic = FakeMic(permission: permission);
    detector = FakeDetector(available: model);
    cue = FakeCue();
    lease = MicCoordinator();
    service = WakeWordService(
      mic: mic,
      detector: detector,
      cue: cue,
      coordinator: lease,
    );
    events = [];
    service.events.listen(events.add);
  }

  Future<void> feed(double amplitude, Duration span) async {
    final count = span.inMilliseconds ~/ Frames.chunk.inMilliseconds;
    for (var i = 0; i < count; i++) {
      mic.emit(Frames.of(amplitude));
    }
    await pumpEventQueue();
  }

  test('arms the mic and reports the wake word', () async {
    build();
    service.start(Voice.config);
    await pumpEventQueue();
    expect(service.status, VoiceStatus.ready);
    expect(service.phase, VoicePhase.armed);
    expect(mic.isOpen, isTrue);

    await feed(Frames.loud, Frames.chunk);
    expect(events, isEmpty);

    mic.emit(Frames.of(Voice.wakeAmplitude));
    await pumpEventQueue();
    expect(events.single, isA<WakeHeard>());
    expect(service.phase, VoicePhase.woken);

    final fedBefore = detector.fed;
    await feed(Voice.wakeAmplitude, Frames.chunk);
    expect(detector.fed, fedBefore, reason: 'detector paused once woken');
  });

  test('captures speech until trailing silence', () async {
    build();
    service.start(Voice.config);
    await pumpEventQueue();

    late VoiceStatus status;
    service.beginCapture().then((s) => status = s);
    await pumpEventQueue();
    expect(status, VoiceStatus.ready);
    expect(service.phase, VoicePhase.capturing);

    await feed(Frames.loud, const Duration(seconds: 1));
    final audio = events.whereType<SpeechAudio>().toList();
    expect(audio, hasLength(10));
    expect(audio.first.pcm, isNotEmpty);
    expect(audio.first.level, greaterThan(0));

    await feed(Frames.quiet, VoiceTiming.endSilence);
    final done = events.whereType<CaptureDone>().single;
    expect(done.reason, CaptureEnd.speechEnded);
    expect(service.phase, VoicePhase.armed);
    expect(mic.isOpen, isTrue, reason: 'mic stays open for spotting');
  });

  test('gives up when the user never speaks', () async {
    build();
    service.start(Voice.config);
    await pumpEventQueue();
    service.beginCapture();
    await pumpEventQueue();

    await feed(Frames.quiet, VoiceTiming.noSpeech);
    expect(events.whereType<CaptureDone>().single.reason, CaptureEnd.noSpeech);
  });

  test('caps long utterances', () async {
    build();
    service.start(Voice.config);
    await pumpEventQueue();
    service.beginCapture();
    await pumpEventQueue();

    await feed(Frames.loud, VoiceTiming.maxUtterance);
    expect(events.whereType<CaptureDone>().single.reason, CaptureEnd.maxLength);
  });

  test('denied permission never opens the mic and retries on demand', () async {
    build(permission: MicPermission.denied);
    service.start(Voice.config);
    await pumpEventQueue();
    expect(service.status, VoiceStatus.noPermission);
    expect(mic.opens, 0);
    expect(detector.loads, isEmpty);

    mic.permission = MicPermission.granted;
    late VoiceStatus status;
    service.beginCapture().then((s) => status = s);
    await pumpEventQueue();
    expect(status, VoiceStatus.ready);
    expect(mic.permissionAsks, 2);
    expect(detector.loads, hasLength(1));
  });

  test('permanently denied is reported and not re-asked', () async {
    build(permission: MicPermission.permanentlyDenied);
    service.start(Voice.config);
    await pumpEventQueue();
    late VoiceStatus status;
    service.beginCapture().then((s) => status = s);
    await pumpEventQueue();
    expect(status, VoiceStatus.blocked);
    expect(mic.permissionAsks, 1);
    expect(mic.opens, 0);
  });

  test('without a model the mic opens only while capturing', () async {
    build(model: false);
    service.start(Voice.config);
    await pumpEventQueue();
    expect(service.status, VoiceStatus.manualOnly);
    expect(mic.isOpen, isFalse);

    service.beginCapture();
    await pumpEventQueue();
    expect(mic.isOpen, isTrue);

    service.endCapture();
    await pumpEventQueue();
    expect(mic.isOpen, isFalse);
  });

  test('broken hardware is reported, not thrown', () async {
    build();
    mic.health = MicHealth.broken;
    service.start(Voice.config);
    await pumpEventQueue();
    expect(service.status, VoiceStatus.micFailed);

    late VoiceStatus status;
    service.beginCapture().then((s) => status = s);
    await pumpEventQueue();
    expect(status, VoiceStatus.micFailed);
    expect(service.phase, VoicePhase.armed);
  });

  test('releases the mic in background and resumes on return', () async {
    build();
    service.start(Voice.config);
    await pumpEventQueue();
    service.beginCapture();
    await pumpEventQueue();

    service.handleLifecycle(AppLifecycleState.inactive);
    await pumpEventQueue();
    expect(mic.isOpen, isTrue, reason: 'inactive is transient');

    service.handleLifecycle(AppLifecycleState.paused);
    await pumpEventQueue();
    expect(mic.isOpen, isFalse);
    expect(service.phase, VoicePhase.paused);
    expect(events.whereType<CaptureDone>().single.reason, CaptureEnd.stopped);

    service.handleLifecycle(AppLifecycleState.resumed);
    await pumpEventQueue();
    expect(mic.isOpen, isTrue);
    expect(service.phase, VoicePhase.armed);
    // start, wake-to-capture hand-off, resume.
    expect(mic.opens, 3);
  });

  test('reloads the detector only when config changes', () async {
    build();
    service.start(Voice.config);
    await pumpEventQueue();
    service.configure(Voice.config);
    await pumpEventQueue();
    expect(detector.loads, hasLength(1));

    const next = WakeConfig(keyword: 'HEY HERMES', sensitivity: 0.8);
    service.configure(next);
    await pumpEventQueue();
    expect(detector.loads.last, next);
    expect(mic.isOpen, isTrue);
  });

  test('default sensitivity detects measured "Hey Sen" speech', () {
    // Measured offline with the real KWS model: a real voice matched at every
    // threshold up to 0.25, synthetic voices only up to ~0.15. The default
    // must therefore stay at or below the measured ceiling.
    const measuredCeiling = 0.25;
    final config = WakeConfig(
      keyword: HubDefaults.wakeKeyword,
      sensitivity: HubDefaults.wakeSensitivity,
    );
    expect(config.threshold, lessThanOrEqualTo(measuredCeiling));
  });

  test('loosest sensitivity reaches the measured TTS floor', () {
    const measuredFloor = 0.1;
    final loosest = WakeConfig(
      keyword: HubDefaults.wakeKeyword,
      sensitivity: SettingsLimits.maxSensitivity,
    );
    expect(loosest.threshold, lessThanOrEqualTo(measuredFloor));
  });

  test('sensitivity maps onto spotter threshold', () {
    const loose = WakeConfig(keyword: 'X', sensitivity: 1);
    const strict = WakeConfig(keyword: 'X', sensitivity: 0);
    expect(loose.threshold, closeTo(WakeTuning.looseThreshold, 1e-9));
    expect(strict.threshold, closeTo(WakeTuning.strictThreshold, 1e-9));
  });

  group('mic hand-off', () {
    Future<void> armed() async {
      build();
      service.start(Voice.config);
      await pumpEventQueue();
    }

    test('wake releases the mic before capture takes it', () async {
      await armed();
      expect(lease.owner, MicOwner.wakeWord);

      mic.emit(Frames.of(Voice.wakeAmplitude));
      await pumpEventQueue();
      expect(lease.owner, isNull, reason: 'released once woken');
      expect(mic.isOpen, isFalse);

      service.beginCapture();
      await pumpEventQueue();
      expect(lease.owner, MicOwner.voiceTurn);
      expect(mic.opens, 2);

      await feed(Frames.loud, Frames.chunk);
      await feed(Frames.quiet, VoiceTiming.endSilence);
      expect(lease.owner, MicOwner.wakeWord, reason: 'resumes after turn');
      expect(mic.isOpen, isTrue);
    });

    test('cancel mid-turn returns the mic to wake word', () async {
      await armed();
      service.beginCapture();
      await pumpEventQueue();
      await feed(Frames.loud, Frames.chunk);
      expect(lease.owner, MicOwner.voiceTurn);

      service.endCapture();
      await pumpEventQueue();
      expect(lease.owner, MicOwner.wakeWord);
      expect(service.phase, VoicePhase.armed);
      expect(mic.isOpen, isTrue);
      expect(detector.resets, greaterThan(0));
    });

    test('cancel while capture is starting never leaks the lease', () async {
      await armed();
      late VoiceStatus status;
      service.beginCapture().then((s) => status = s);
      service.endCapture();
      await pumpEventQueue();

      expect(status, VoiceStatus.micBusy);
      expect(service.phase, VoicePhase.armed);
      expect(lease.owner, MicOwner.wakeWord);
      expect(mic.isOpen, isTrue);
    });

    test('double start opens the capture mic once', () async {
      await armed();
      final results = <VoiceStatus>[];
      service.beginCapture().then(results.add);
      service.beginCapture().then(results.add);
      await pumpEventQueue();

      expect(results, [VoiceStatus.ready, VoiceStatus.ready]);
      expect(mic.opens, 2, reason: 'one wake open, one capture open');
      expect(lease.owner, MicOwner.voiceTurn);
    });

    test('double service start acquires one lease', () async {
      build();
      service.start(Voice.config);
      service.start(Voice.config);
      await pumpEventQueue();
      expect(mic.opens, 1);
      expect(detector.loads, hasLength(1));
    });

    test('waits for another recorder, then resumes', () async {
      build();
      final other = lease.tryAcquire(MicOwner.voiceTurn)!;
      service.start(Voice.config);
      await pumpEventQueue();
      expect(mic.isOpen, isFalse);

      late VoiceStatus status;
      service.beginCapture().then((s) => status = s);
      await pumpEventQueue();
      expect(status, VoiceStatus.micBusy);

      lease.release(other);
      await pumpEventQueue();
      expect(lease.owner, MicOwner.wakeWord);
      expect(mic.isOpen, isTrue);
    });
  });

  group('background mode', () {
    test('keep listening ignores screen-off lifecycle', () async {
      build();
      service.setBackgroundMode(BackgroundMode.keepListening);
      service.start(Voice.config);
      await pumpEventQueue();

      service.handleLifecycle(AppLifecycleState.hidden);
      service.handleLifecycle(AppLifecycleState.paused);
      await pumpEventQueue();
      expect(service.phase, VoicePhase.armed);
      expect(mic.isOpen, isTrue);

      mic.emit(Frames.of(Voice.wakeAmplitude));
      await pumpEventQueue();
      expect(events.single, isA<WakeHeard>());
    });

    test('detach still releases the mic', () async {
      build();
      service.setBackgroundMode(BackgroundMode.keepListening);
      service.start(Voice.config);
      await pumpEventQueue();

      service.handleLifecycle(AppLifecycleState.detached);
      await pumpEventQueue();
      expect(mic.isOpen, isFalse);
      expect(lease.owner, isNull);
    });
  });

  test('reloadModel arms the mic once a model appears', () async {
    build(model: false);
    service.start(Voice.config);
    await pumpEventQueue();
    expect(mic.isOpen, isFalse);

    detector.available = true;
    late VoiceStatus status;
    service.reloadModel().then((s) => status = s);
    await pumpEventQueue();
    expect(status, VoiceStatus.ready);
    expect(mic.isOpen, isTrue);
  });
}
