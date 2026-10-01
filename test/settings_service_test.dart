import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_display/core/constants/app_constants.dart';
import 'package:hermes_display/services/settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('loads defaults when empty', () async {
    SharedPreferences.setMockInitialValues({});
    final service = await SettingsService.create();
    final settings = service.load();
    expect(settings.host, HubDefaults.host);
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
      ),
    );
    final loaded = service.load();
    expect(loaded.host, '192.168.1.20');
    expect(loaded.port, SettingsLimits.maxPort);
    expect(loaded.slideIntervalSec, SettingsLimits.minSlideSec);
    expect(loaded.wakeSensitivity, 0.7);
  });
}
