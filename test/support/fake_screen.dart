import 'package:hermes_display/core/dimming/dim_schedule.dart';
import 'package:hermes_display/services/screen/screen_control.dart';

enum ScreenHealth { ok, failing }

/// Simulates the panel and the activity's lock-screen flags.
class FakeScreen implements ScreenControl {
  FakeScreen({this.health = ScreenHealth.ok});

  ScreenHealth health;

  /// Physical display state; tests set false to model screen-off.
  bool displayOn = true;

  /// setTurnScreenOn / setShowWhenLocked currently applied.
  bool overLock = false;
  final List<BrightnessTarget> brightness = [];
  int wakes = 0;
  int releases = 0;

  BrightnessTarget? get lastBrightness {
    return brightness.isEmpty ? null : brightness.last;
  }

  ScreenResult get _result {
    return health == ScreenHealth.ok ? ScreenResult.ok : ScreenResult.failed;
  }

  @override
  Future<ScreenResult> setBrightness(BrightnessTarget target) async {
    if (health == ScreenHealth.ok) {
      brightness.add(target);
    }
    return _result;
  }

  @override
  Future<ScreenResult> wake() async {
    wakes++;
    if (health == ScreenHealth.ok) {
      displayOn = true;
      overLock = true;
    }
    return _result;
  }

  @override
  Future<ScreenResult> release() async {
    releases++;
    if (health == ScreenHealth.ok) {
      overLock = false;
    }
    return _result;
  }
}
