import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_display/core/constants/app_constants.dart';
import 'package:hermes_display/core/dimming/dim_schedule.dart';
import 'package:hermes_display/core/state/display_controller.dart';
import 'package:hermes_display/core/state/display_state.dart';
import 'package:hermes_display/services/hermes_websocket_client.dart';
import 'package:hermes_display/services/night_dimmer.dart';
import 'package:hermes_display/services/screen/screen_control.dart';
import 'package:hermes_display/services/settings_service.dart';
import 'package:hermes_display/services/wake_word_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_keep_alive.dart';
import 'support/fake_screen.dart';
import 'support/fake_transport.dart';
import 'support/fake_voice.dart';

void main() {
  const dim = BrightnessTarget.dim(DimDefaults.level);
  final night = DateTime(2026, 10, 2, 2);
  late FakeMic mic;
  late FakeScreen screen;
  late WakeWordService voice;
  late DisplayController controller;

  Future<void> build({ScreenHealth health = ScreenHealth.ok}) async {
    SharedPreferences.setMockInitialValues({});
    mic = FakeMic();
    screen = FakeScreen(health: health);
    voice = WakeWordService(mic: mic, detector: FakeDetector(), cue: FakeCue());
    controller = DisplayController(
      settingsService: await SettingsService.create(),
      client: HermesWebSocketClient(
        transportFactory: FakeTransportFactory(
          fallback: FakeOutcome.accept,
        ).call,
      ),
      voice: voice,
      keepAlive: FakeKeepAlive(),
      screen: screen,
      dimmer: NightDimmer(screen: screen, clock: () => night),
    )..start();
    await pumpEventQueue();
  }

  Future<void> sayHeySen() async {
    mic.emit(Frames.of(Voice.wakeAmplitude));
    await pumpEventQueue();
  }

  tearDown(() => controller.dispose());

  test('wake while idle lights the screen at full brightness', () async {
    await build();
    expect(screen.lastBrightness, dim);
    expect(controller.nightDimmed.value, isTrue);

    await sayHeySen();
    expect(controller.state, DisplayState.listening);
    expect(screen.wakes, 1);
    expect(screen.overLock, isTrue);
    expect(screen.lastBrightness, BrightnessTarget.system);
    expect(controller.nightDimmed.value, isFalse);
  });

  test('wake while the screen is off turns it on', () async {
    await build();
    screen.displayOn = false;
    voice.handleLifecycle(AppLifecycleState.hidden);
    voice.handleLifecycle(AppLifecycleState.paused);
    await pumpEventQueue();

    await sayHeySen();
    expect(screen.displayOn, isTrue);
    expect(screen.overLock, isTrue);
    expect(controller.state, DisplayState.listening);
  });

  test('cancel mid-turn releases flags and returns to dim', () async {
    await build();
    await sayHeySen();
    controller.cancel();
    await pumpEventQueue();
    expect(controller.state, DisplayState.idle);
    expect(screen.overLock, isFalse);
    expect(screen.releases, 1);
    expect(screen.lastBrightness, dim);
  });

  test('repeated wakes do not leak flags', () async {
    await build();
    for (var turn = 1; turn <= 3; turn++) {
      await sayHeySen();
      expect(screen.overLock, isTrue);
      controller.cancel();
      await pumpEventQueue();
      expect(screen.overLock, isFalse);
      expect(screen.wakes, turn);
      expect(screen.releases, turn);
    }
  });

  test('mic button does not touch lock-screen flags', () async {
    await build();
    await controller.listen();
    expect(screen.wakes, 0);
    expect(screen.lastBrightness, BrightnessTarget.system);
    controller.cancel();
    await pumpEventQueue();
    expect(screen.releases, 0);
    expect(screen.lastBrightness, dim);
  });

  test('screen channel failure is reported, turn continues', () async {
    await build(health: ScreenHealth.failing);
    await sayHeySen();
    expect(controller.state, DisplayState.listening);
    expect(controller.screenResult, ScreenResult.failed);
  });

  test('touch brightens a dimmed screen briefly', () {
    fakeAsync((async) {
      build();
      async.elapse(Duration.zero);
      expect(screen.lastBrightness, dim);
      controller.touch();
      async.flushMicrotasks();
      expect(screen.lastBrightness, BrightnessTarget.system);
      async.elapse(DimTiming.touchHold);
      expect(screen.lastBrightness, dim);
    });
  });
}
