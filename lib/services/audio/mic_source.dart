import 'dart:async';

import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import '../../core/constants/app_constants.dart';
import 'audio_frame.dart';

enum MicPermission { granted, denied, permanentlyDenied }

/// Microphone contract so the voice pipeline runs in tests without hardware.
abstract interface class MicSource {
  /// Checks RECORD_AUDIO and asks the user only when Android still allows it.
  Future<MicPermission> ensurePermission();

  /// Starts capture; throws if the hardware is unavailable.
  Future<Stream<AudioFrame>> open();

  Future<void> close();

  Future<void> dispose();
}

final class RecordMicSource implements MicSource {
  RecordMicSource({AudioRecorder? recorder})
    : _recorder = recorder ?? AudioRecorder();

  static const RecordConfig _config = RecordConfig(
    encoder: AudioEncoder.pcm16bits,
    sampleRate: AudioSpec.sampleRate,
    numChannels: AudioSpec.channels,
    noiseSuppress: true,
    echoCancel: true,
  );

  final AudioRecorder _recorder;
  final Pcm16Aligner _aligner = Pcm16Aligner();

  @override
  Future<MicPermission> ensurePermission() async {
    final current = await Permission.microphone.status;
    if (current.isGranted) {
      return MicPermission.granted;
    }
    if (current.isPermanentlyDenied || current.isRestricted) {
      return MicPermission.permanentlyDenied;
    }
    final asked = await Permission.microphone.request();
    if (asked.isGranted) {
      return MicPermission.granted;
    }
    if (asked.isPermanentlyDenied) {
      return MicPermission.permanentlyDenied;
    }
    return MicPermission.denied;
  }

  @override
  Future<Stream<AudioFrame>> open() async {
    _aligner.reset();
    final raw = await _recorder.startStream(_config);
    return raw.map(_aligner.push).where((f) => f != null).cast<AudioFrame>();
  }

  @override
  Future<void> close() async {
    if (!await _recorder.isRecording()) {
      return;
    }
    await _recorder.stop();
  }

  @override
  Future<void> dispose() => _recorder.dispose();
}
