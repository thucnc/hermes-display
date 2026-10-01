import 'dart:async';
import 'dart:typed_data';

import 'package:hermes_display/core/constants/app_constants.dart';
import 'package:hermes_display/services/audio/audio_frame.dart';
import 'package:hermes_display/services/audio/cue_player.dart';
import 'package:hermes_display/services/audio/mic_source.dart';
import 'package:hermes_display/services/audio/wake_detector.dart';

enum MicHealth { ok, broken }

/// Builds PCM16 frames of constant amplitude.
abstract final class Frames {
  static const Duration chunk = Duration(milliseconds: 100);
  static const double loud = 0.3;
  static const double quiet = 0;

  static AudioFrame of(double amplitude, {Duration length = chunk}) {
    final count =
        AudioSpec.sampleRate *
        length.inMicroseconds ~/
        Duration.microsecondsPerSecond;
    final value = (amplitude * (AudioSpec.int16Max - 1)).round();
    final samples = Int16List(count)..fillRange(0, count, value);
    return AudioFrame(samples.buffer.asUint8List());
  }
}

class FakeMic implements MicSource {
  FakeMic({
    this.permission = MicPermission.granted,
    this.health = MicHealth.ok,
  });

  MicPermission permission;
  MicHealth health;
  int permissionAsks = 0;
  int opens = 0;
  StreamController<AudioFrame>? _live;

  bool get isOpen => _live != null;

  @override
  Future<MicPermission> ensurePermission() async {
    permissionAsks++;
    return permission;
  }

  @override
  Future<Stream<AudioFrame>> open() async {
    if (health == MicHealth.broken) {
      throw StateError('no microphone');
    }
    opens++;
    final live = StreamController<AudioFrame>();
    _live = live;
    return live.stream;
  }

  void emit(AudioFrame frame) => _live?.add(frame);

  @override
  Future<void> close() async {
    final live = _live;
    _live = null;
    // A cancelled controller's close() future never completes; don't wait.
    unawaited(live?.close());
  }

  @override
  Future<void> dispose() => close();
}

/// Fires on any frame whose RMS exceeds [triggerRms], standing in for
/// "Hey Sen" being spoken.
class FakeDetector implements WakeDetector {
  FakeDetector({this.available = true});

  static const double triggerRms = 0.5;

  bool available;
  final List<WakeConfig> loads = [];
  int resets = 0;
  int fed = 0;

  @override
  Future<bool> load(WakeConfig config) async {
    loads.add(config);
    return available;
  }

  @override
  bool accept(AudioFrame frame) {
    fed++;
    return frame.rms > triggerRms;
  }

  @override
  void reset() => resets++;

  @override
  void dispose() {}
}

class FakeCue implements CuePlayer {
  int plays = 0;

  @override
  Future<void> play() async => plays++;

  @override
  Future<void> dispose() async {}
}

abstract final class Voice {
  static const double wakeAmplitude = 0.9;
  static const WakeConfig config = WakeConfig(
    keyword: HubDefaults.wakeKeyword,
    sensitivity: HubDefaults.wakeSensitivity,
  );
}
