import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_display/core/constants/app_constants.dart';
import 'package:hermes_display/core/dimming/dim_schedule.dart';
import 'package:hermes_display/services/night_dimmer.dart';
import 'package:hermes_display/services/screen/screen_control.dart';

import 'support/fake_screen.dart';

void main() {
  const dim = BrightnessTarget.dim(DimDefaults.level);
  late FakeScreen screen;
  late DateTime now;
  late NightDimmer dimmer;

  void build(FakeAsync async, DateTime start, {FakeScreen? fake}) {
    now = start;
    screen = fake ?? FakeScreen();
    dimmer = NightDimmer(screen: screen, clock: () => now)
      ..start(DimSettings.defaults);
    async.flushMicrotasks();
  }

  void advance(FakeAsync async, Duration step) {
    now = now.add(step);
    async.elapse(step);
  }

  test('dims when the window opens and restores when it closes', () {
    fakeAsync((async) {
      build(async, DateTime(2026, 10, 1, 22, 59));
      expect(screen.lastBrightness, BrightnessTarget.system);
      expect(dimmer.dimmed.value, isFalse);

      advance(async, DimTiming.tick);
      expect(screen.lastBrightness, dim);
      expect(dimmer.dimmed.value, isTrue);

      advance(async, const Duration(hours: 7));
      expect(screen.lastBrightness, BrightnessTarget.system);
      dimmer.dispose();
    });
  });

  test('ticks do not resend an unchanged target', () {
    fakeAsync((async) {
      build(async, DateTime(2026, 10, 1, 1));
      advance(async, DimTiming.tick * 5);
      expect(screen.brightness, [dim]);
      dimmer.dispose();
    });
  });

  test('resume re-applies even when unchanged', () {
    fakeAsync((async) {
      build(async, DateTime(2026, 10, 1, 1));
      dimmer.evaluate(mode: ApplyMode.always);
      async.flushMicrotasks();
      expect(screen.brightness, [dim, dim]);
      dimmer.dispose();
    });
  });

  test('a turn holds full brightness, then returns to dim', () {
    fakeAsync((async) {
      build(async, DateTime(2026, 10, 1, 2));
      dimmer.hold(BrightHold.turn);
      async.flushMicrotasks();
      expect(screen.lastBrightness, BrightnessTarget.system);
      expect(dimmer.dimmed.value, isFalse);

      dimmer.release(BrightHold.turn);
      async.flushMicrotasks();
      expect(screen.lastBrightness, dim);
      dimmer.dispose();
    });
  });

  test('a touch brightens for a while', () {
    fakeAsync((async) {
      build(async, DateTime(2026, 10, 1, 2));
      dimmer.touch();
      async.flushMicrotasks();
      expect(screen.lastBrightness, BrightnessTarget.system);

      advance(async, DimTiming.touchHold - const Duration(seconds: 1));
      dimmer.touch();
      advance(async, DimTiming.touchHold - const Duration(seconds: 1));
      expect(screen.lastBrightness, BrightnessTarget.system);

      advance(async, const Duration(seconds: 1));
      expect(screen.lastBrightness, dim);
      dimmer.dispose();
    });
  });

  test('disabling restores system brightness', () {
    fakeAsync((async) {
      build(async, DateTime(2026, 10, 1, 2));
      dimmer.configure(DimSettings.defaults.copyWith(enabled: false));
      async.flushMicrotasks();
      expect(screen.lastBrightness, BrightnessTarget.system);
      expect(dimmer.dimmed.value, isFalse);
      dimmer.dispose();
    });
  });

  test('channel failure is reported, not thrown', () {
    fakeAsync((async) {
      build(
        async,
        DateTime(2026, 10, 1, 2),
        fake: FakeScreen(health: ScreenHealth.failing),
      );
      expect(dimmer.lastResult, ScreenResult.failed);
      dimmer.dispose();
    });
  });

  test('dispose restores system brightness and stops ticking', () {
    fakeAsync((async) {
      build(async, DateTime(2026, 10, 1, 2));
      dimmer.dispose();
      async.flushMicrotasks();
      expect(screen.lastBrightness, BrightnessTarget.system);
      final count = screen.brightness.length;
      advance(async, DimTiming.tick * 3);
      expect(screen.brightness, hasLength(count));
    });
  });
}
