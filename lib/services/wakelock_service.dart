import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Keeps the screen on for the lifetime of the app. Re-asserts on resume
/// because some OEM ROMs (EMUI/HarmonyOS) drop the flag when backgrounded.
class WakelockService {
  AppLifecycleListener? _listener;

  Future<void> attach() async {
    await _enable();
    _listener ??= AppLifecycleListener(onResume: () => unawaited(_enable()));
  }

  void dispose() {
    _listener?.dispose();
    _listener = null;
  }

  Future<void> _enable() async {
    try {
      await WakelockPlus.enable();
    } on Object catch (error) {
      debugPrint('Wakelock unavailable: $error');
    }
  }
}
