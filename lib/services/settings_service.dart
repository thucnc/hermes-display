import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants/app_constants.dart';
import 'audio/wake_detector.dart';

class HubSettings {
  const HubSettings({
    required this.host,
    required this.port,
    required this.slideIntervalSec,
    required this.wakeSensitivity,
    required this.wakeKeyword,
    required this.alwaysListening,
  });

  static const HubSettings defaults = HubSettings(
    host: HubDefaults.host,
    port: HubDefaults.port,
    slideIntervalSec: HubDefaults.slideIntervalSec,
    wakeSensitivity: HubDefaults.wakeSensitivity,
    wakeKeyword: HubDefaults.wakeKeyword,
    alwaysListening: HubDefaults.alwaysListening,
  );

  final String host;
  final int port;
  final int slideIntervalSec;
  final double wakeSensitivity;
  final String wakeKeyword;

  /// Keep the wake word running behind a microphone foreground service.
  final bool alwaysListening;

  Uri get wsUri => Uri(scheme: HubDefaults.scheme, host: host, port: port);

  Duration get slideInterval => Duration(seconds: slideIntervalSec);

  WakeConfig get wakeConfig {
    return WakeConfig(keyword: wakeKeyword, sensitivity: wakeSensitivity);
  }

  bool sameAddress(HubSettings other) {
    return host == other.host && port == other.port;
  }

  HubSettings copyWith({
    String? host,
    int? port,
    int? slideIntervalSec,
    double? wakeSensitivity,
    String? wakeKeyword,
    bool? alwaysListening,
  }) {
    return HubSettings(
      host: host ?? this.host,
      port: port ?? this.port,
      slideIntervalSec: slideIntervalSec ?? this.slideIntervalSec,
      wakeSensitivity: wakeSensitivity ?? this.wakeSensitivity,
      wakeKeyword: wakeKeyword ?? this.wakeKeyword,
      alwaysListening: alwaysListening ?? this.alwaysListening,
    );
  }

  /// Clamps every field into its legal range; blank host/keyword fall
  /// back. Keywords are upper-cased to match the spotter's vocabulary.
  HubSettings normalized() {
    final trimmed = host.trim();
    final keyword = wakeKeyword.trim().toUpperCase();
    return HubSettings(
      host: trimmed.isEmpty ? HubDefaults.host : trimmed,
      port: port.clamp(SettingsLimits.minPort, SettingsLimits.maxPort),
      slideIntervalSec: slideIntervalSec.clamp(
        SettingsLimits.minSlideSec,
        SettingsLimits.maxSlideSec,
      ),
      wakeSensitivity: wakeSensitivity.clamp(
        SettingsLimits.minSensitivity,
        SettingsLimits.maxSensitivity,
      ),
      wakeKeyword: keyword.isEmpty ? HubDefaults.wakeKeyword : keyword,
      alwaysListening: alwaysListening,
    );
  }
}

abstract final class _PrefKey {
  static const String host = 'hub_host';
  static const String port = 'hub_port';
  static const String slideInterval = 'slide_interval_sec';
  static const String wakeSensitivity = 'wake_sensitivity';
  static const String wakeKeyword = 'wake_keyword';
  static const String alwaysListening = 'always_listening';
}

class SettingsService {
  SettingsService(this._prefs);

  static Future<SettingsService> create() async {
    return SettingsService(await SharedPreferences.getInstance());
  }

  final SharedPreferences _prefs;

  HubSettings load() {
    const fallback = HubSettings.defaults;
    return HubSettings(
      host: _prefs.getString(_PrefKey.host) ?? fallback.host,
      port: _prefs.getInt(_PrefKey.port) ?? fallback.port,
      slideIntervalSec:
          _prefs.getInt(_PrefKey.slideInterval) ?? fallback.slideIntervalSec,
      wakeSensitivity:
          _prefs.getDouble(_PrefKey.wakeSensitivity) ??
          fallback.wakeSensitivity,
      wakeKeyword:
          _prefs.getString(_PrefKey.wakeKeyword) ?? fallback.wakeKeyword,
      alwaysListening:
          _prefs.getBool(_PrefKey.alwaysListening) ?? fallback.alwaysListening,
    ).normalized();
  }

  Future<void> save(HubSettings settings) async {
    final value = settings.normalized();
    await Future.wait([
      _prefs.setString(_PrefKey.host, value.host),
      _prefs.setInt(_PrefKey.port, value.port),
      _prefs.setInt(_PrefKey.slideInterval, value.slideIntervalSec),
      _prefs.setDouble(_PrefKey.wakeSensitivity, value.wakeSensitivity),
      _prefs.setString(_PrefKey.wakeKeyword, value.wakeKeyword),
      _prefs.setBool(_PrefKey.alwaysListening, value.alwaysListening),
    ]);
  }
}
