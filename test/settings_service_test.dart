import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_display/core/constants/app_constants.dart';
import 'package:hermes_display/core/state/brain_mode.dart';
import 'package:hermes_display/core/dimming/dim_schedule.dart';
import 'package:hermes_display/services/settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('loads defaults when empty', () async {
    SharedPreferences.setMockInitialValues({});
    final service = await SettingsService.create();
    final settings = service.load();
    expect(settings.host, HubDefaults.host);
    expect(settings.alwaysListening, isTrue);
    expect(settings.wsUri.toString(), 'ws://localhost:8900');
  });

  test('round-trips and clamps values', () async {
    SharedPreferences.setMockInitialValues({});
    final service = await SettingsService.create();
    await service.save(
      const HubSettings(
        host: ' 192.168.1.20 ',
        port: 70000,
        slideIntervalSec: 1,
        wakeSensitivity: 0.7,
        wakeKeyword: ' hey sen ',
        alwaysListening: false,
      ),
    );
    final loaded = service.load();
    expect(loaded.host, '192.168.1.20');
    expect(loaded.port, SettingsLimits.maxPort);
    expect(loaded.slideIntervalSec, SettingsLimits.minSlideSec);
    expect(loaded.wakeSensitivity, 0.7);
    expect(loaded.wakeKeyword, 'HEY SEN');
    expect(loaded.alwaysListening, isFalse);
  });

  test('blank keyword falls back to default', () {
    final settings = HubSettings.defaults.copyWith(wakeKeyword: '  ');
    expect(settings.normalized().wakeKeyword, HubDefaults.wakeKeyword);
  });

  test('night dimming defaults and round-trip with clamping', () async {
    SharedPreferences.setMockInitialValues({});
    final service = await SettingsService.create();
    expect(service.load().dim, DimSettings.defaults);

    await service.save(
      HubSettings.defaults.copyWith(
        dim: const DimSettings(
          enabled: false,
          startHour: 99,
          endHour: 5,
          level: 0,
        ),
      ),
    );
    final loaded = service.load().dim;
    expect(loaded.enabled, isFalse);
    expect(loaded.startHour, DimLimits.maxHour);
    expect(loaded.endHour, 5);
    expect(loaded.level, DimLimits.minLevel);
  });

  test('corrupt stored dim values are clamped on load', () async {
    SharedPreferences.setMockInitialValues({
      'dim_start_hour': -4,
      'dim_level': 7.0,
    });
    final dim = (await SettingsService.create()).load().dim;
    expect(dim.startHour, DimLimits.minHour);
    expect(dim.level, DimLimits.maxLevel);
  });

  test('brain: gemini by default only once a key is stored', () async {
    SharedPreferences.setMockInitialValues({});
    final service = await SettingsService.create();
    final fresh = service.load();
    expect(fresh.geminiApiKey, isEmpty);
    expect(fresh.brainMode, BrainMode.gemini);
    expect(fresh.activeBrain, BrainMode.hub);

    await service.save(fresh.copyWith(geminiApiKey: '  AIza-key '));
    final keyed = service.load();
    expect(keyed.geminiApiKey, 'AIza-key');
    expect(keyed.activeBrain, BrainMode.gemini);

    await service.save(keyed.copyWith(brainMode: BrainMode.hub));
    expect(service.load().activeBrain, BrainMode.hub);
  });

  test('save URI targets the hub over http', () {
    final settings = HubSettings.defaults.copyWith(
      host: '10.0.0.2',
      port: 8901,
    );
    expect(settings.saveUri.toString(), 'http://10.0.0.2:8901/save');
  });
}
