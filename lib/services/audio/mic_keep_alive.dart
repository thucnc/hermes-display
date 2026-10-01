import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

/// Keeps the process allowed to record while backgrounded or screen-off.
abstract interface class MicKeepAlive {
  /// True once the foreground service runs.
  Future<bool> start();

  Future<void> stop();
}

/// Android `MicKeepAliveService` (foregroundServiceType=microphone) via a
/// method channel. The mic stream itself stays in Dart; the service only
/// keeps the app eligible for background capture and holds a CPU wake lock.
final class ChannelKeepAlive implements MicKeepAlive {
  const ChannelKeepAlive();

  static const MethodChannel _channel = MethodChannel(
    'hermes_display/mic_service',
  );
  static const String _start = 'start';
  static const String _stop = 'stop';

  @override
  Future<bool> start() async {
    if (!Platform.isAndroid) {
      return false;
    }
    try {
      // Android 13+: without it the service still runs, notification hidden.
      await Permission.notification.request();
      return await _channel.invokeMethod<bool>(_start) ?? false;
    } on Object catch (error) {
      debugPrint('Mic service refused: $error');
      return false;
    }
  }

  @override
  Future<void> stop() async {
    if (!Platform.isAndroid) {
      return;
    }
    try {
      await _channel.invokeMethod<void>(_stop);
    } on Object catch (error) {
      debugPrint('Mic service stop failed: $error');
    }
  }
}
