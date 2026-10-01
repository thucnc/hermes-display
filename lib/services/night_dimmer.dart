import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../core/constants/app_constants.dart';
import '../core/dimming/dim_schedule.dart';
import 'screen/screen_control.dart';

typedef Clock = DateTime Function();

/// Reasons to keep full brightness inside the dim window.
enum BrightHold { turn, touch }

enum ApplyMode { ifChanged, always }

/// Applies the night dim schedule to the app window: re-checked every
/// [DimTiming.tick], on resume, and whenever a hold changes.
class NightDimmer {
  NightDimmer({required ScreenControl screen, Clock? clock})
    : _screen = screen,
      _clock = clock ?? DateTime.now;

  final ScreenControl _screen;
  final Clock _clock;
  final Set<BrightHold> _holds = {};
  final ValueNotifier<bool> _dimmed = ValueNotifier<bool>(false);
  DimSettings _settings = DimSettings.defaults;
  BrightnessTarget? _applied;
  Timer? _ticker;
  Timer? _touchTimer;
  AppLifecycleListener? _lifecycle;
  ScreenResult? _lastResult;

  /// True while the window is actually dimmed (UI lowers its opacity).
  ValueListenable<bool> get dimmed => _dimmed;

  ScreenResult? get lastResult => _lastResult;

  void start(DimSettings settings) {
    _settings = settings;
    _ticker ??= Timer.periodic(DimTiming.tick, (_) => evaluate());
    evaluate(mode: ApplyMode.always);
  }

  void attachLifecycle() {
    _lifecycle ??= AppLifecycleListener(
      onResume: () => evaluate(mode: ApplyMode.always),
    );
  }

  void configure(DimSettings settings) {
    _settings = settings;
    evaluate();
  }

  void hold(BrightHold reason) {
    if (_holds.add(reason)) {
      evaluate();
    }
  }

  void release(BrightHold reason) {
    if (_holds.remove(reason)) {
      evaluate();
    }
  }

  /// Full brightness for [DimTiming.touchHold] after the last touch.
  void touch() {
    _touchTimer?.cancel();
    _touchTimer = Timer(DimTiming.touchHold, () => release(BrightHold.touch));
    hold(BrightHold.touch);
  }

  void evaluate({ApplyMode mode = ApplyMode.ifChanged}) {
    final scheduled = dimTarget(_clock(), _settings);
    final target = _holds.isEmpty ? scheduled : BrightnessTarget.system;
    _dimmed.value = target.isDim;
    if (mode == ApplyMode.ifChanged && target == _applied) {
      return;
    }
    _applied = target;
    unawaited(_apply(target));
  }

  Future<void> _apply(BrightnessTarget target) async {
    _lastResult = await _screen.setBrightness(target);
  }

  void dispose() {
    _ticker?.cancel();
    _ticker = null;
    _touchTimer?.cancel();
    _lifecycle?.dispose();
    _lifecycle = null;
    unawaited(_screen.setBrightness(BrightnessTarget.system));
    _dimmed.dispose();
  }
}
