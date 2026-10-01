import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../core/dimming/dim_schedule.dart';

enum ScreenResult { ok, unsupported, failed }

/// Window brightness and lock-screen wake for the app's own activity.
/// Implementations report failures instead of throwing.
abstract interface class ScreenControl {
  /// Overrides brightness for the app window only (no WRITE_SETTINGS).
  Future<ScreenResult> setBrightness(BrightnessTarget target);

  /// Turns the screen on and shows the activity above the keyguard.
  Future<ScreenResult> wake();

  /// Drops the flags set by [wake].
  Future<ScreenResult> release();
}

/// Android `MainActivity` handler on `hermes_display/screen`.
final class ChannelScreenControl implements ScreenControl {
  const ChannelScreenControl();

  @visibleForTesting
  static const MethodChannel channel = MethodChannel('hermes_display/screen');
  static const String _setBrightness = 'setBrightness';
  static const String _wake = 'wakeScreen';
  static const String _release = 'releaseScreen';
  static const String _levelArg = 'level';

  @override
  Future<ScreenResult> setBrightness(BrightnessTarget target) {
    return _invoke(_setBrightness, {_levelArg: target.level});
  }

  @override
  Future<ScreenResult> wake() => _invoke(_wake);

  @override
  Future<ScreenResult> release() => _invoke(_release);

  Future<ScreenResult> _invoke(String method, [Object? args]) async {
    try {
      await channel.invokeMethod<void>(method, args);
      return ScreenResult.ok;
    } on MissingPluginException {
      return ScreenResult.unsupported;
    } on Object catch (error) {
      debugPrint('Screen $method failed: $error');
      return ScreenResult.failed;
    }
  }
}
