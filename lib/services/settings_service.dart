import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants/app_constants.dart';
import '../core/dimming/dim_schedule.dart';
import '../core/members/member_profile.dart';
import '../core/state/brain_mode.dart';
import 'audio/wake_detector.dart';

class HubSettings {
  const HubSettings({
    required this.host,
    required this.port,
    required this.slideIntervalSec,
    required this.wakeSensitivity,
    required this.wakeKeyword,
    required this.alwaysListening,
    this.dim = DimSettings.defaults,
    this.geminiApiKey = HubDefaults.geminiApiKey,
    this.brainMode = HubDefaults.brainMode,
    this.activeMemberId = HubDefaults.activeMemberId,
    this.knowledgePackUrl = HubDefaults.knowledgePackUrl,
    this.updateUrl = HubDefaults.updateUrl,
    this.photoManifestUrl = HubDefaults.photoManifestUrl,
  });

  static const HubSettings defaults = HubSettings(
    host: HubDefaults.host,
    port: HubDefaults.port,
    slideIntervalSec: HubDefaults.slideIntervalSec,
    wakeSensitivity: HubDefaults.wakeSensitivity,
    wakeKeyword: HubDefaults.wakeKeyword,
    alwaysListening: HubDefaults.alwaysListening,
    dim: DimSettings.defaults,
    geminiApiKey: HubDefaults.geminiApiKey,
    brainMode: HubDefaults.brainMode,
    activeMemberId: HubDefaults.activeMemberId,
    knowledgePackUrl: HubDefaults.knowledgePackUrl,
    updateUrl: HubDefaults.updateUrl,
    photoManifestUrl: HubDefaults.photoManifestUrl,
  );

  final String host;
  final int port;
  final int slideIntervalSec;
  final double wakeSensitivity;
  final String wakeKeyword;

  /// Keep the wake word running behind a microphone foreground service.
  final bool alwaysListening;

  /// Night dimming window for the app's screen.
  final DimSettings dim;

  /// Google AI Studio key for direct Gemini calls; empty means none.
  final String geminiApiKey;

  /// Preferred brain; see [activeBrain] for the one actually used.
  final BrainMode brainMode;

  /// Family member Sen is talking to; the knowledge pack may add ids
  /// beyond [MemberProfile.family].
  final String activeMemberId;

  /// Where `sen-pack.json` is downloaded from; empty means none.
  final String knowledgePackUrl;

  /// `latest.json`-style endpoint for APK updates; empty means the hub.
  final String updateUrl;
  /// Where `photos.json` is downloaded from; empty means placeholders.
  final String photoManifestUrl;

  /// Gemini only when chosen and a key exists, otherwise the hub.
  BrainMode get activeBrain {
    if (brainMode == BrainMode.gemini && geminiApiKey.isNotEmpty) {
      return BrainMode.gemini;
    }
    return BrainMode.hub;
  }

  Uri get wsUri => Uri(scheme: HubDefaults.scheme, host: host, port: port);

  Uri get saveUri {
    return Uri(
      scheme: SyncDefaults.scheme,
      host: host,
      port: port,
      path: SyncDefaults.savePath,
    );
  }

  Uri get ttsUri {
    return Uri(
      scheme: SyncDefaults.scheme,
      host: host,
      port: port,
      path: HubTtsDefaults.path,
    );
  }

  /// [updateUrl] when it is a valid http(s) URL, else the hub's
  /// [UpdateDefaults.latestPath].
  Uri get updateUri {
    final custom = Uri.tryParse(updateUrl);
    if (updateUrl.isNotEmpty && custom != null && custom.host.isNotEmpty) {
      return custom;
    }
    return Uri(
      scheme: UpdateDefaults.scheme,
      host: host,
      port: port,
      path: UpdateDefaults.latestPath,
    );
  }

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
    DimSettings? dim,
    String? geminiApiKey,
    BrainMode? brainMode,
    String? activeMemberId,
    String? knowledgePackUrl,
    String? updateUrl,
    String? photoManifestUrl,
  }) {
    return HubSettings(
      host: host ?? this.host,
      port: port ?? this.port,
      slideIntervalSec: slideIntervalSec ?? this.slideIntervalSec,
      wakeSensitivity: wakeSensitivity ?? this.wakeSensitivity,
      wakeKeyword: wakeKeyword ?? this.wakeKeyword,
      alwaysListening: alwaysListening ?? this.alwaysListening,
      dim: dim ?? this.dim,
      geminiApiKey: geminiApiKey ?? this.geminiApiKey,
      brainMode: brainMode ?? this.brainMode,
      activeMemberId: activeMemberId ?? this.activeMemberId,
      knowledgePackUrl: knowledgePackUrl ?? this.knowledgePackUrl,
      updateUrl: updateUrl ?? this.updateUrl,
      photoManifestUrl: photoManifestUrl ?? this.photoManifestUrl,
    );
  }

  /// Clamps every field into its legal range; blank host/keyword/member
  /// fall back. Keywords are upper-cased to match the spotter's
  /// vocabulary.
  HubSettings normalized() {
    final trimmed = host.trim();
    final keyword = wakeKeyword.trim().toUpperCase();
    final memberId = activeMemberId.trim();
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
      dim: dim.normalized(),
      geminiApiKey: geminiApiKey.trim(),
      brainMode: brainMode,
      activeMemberId: memberId.isEmpty ? HubDefaults.activeMemberId : memberId,
      knowledgePackUrl: knowledgePackUrl.trim(),
      updateUrl: updateUrl.trim(),
      photoManifestUrl: photoManifestUrl.trim(),
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
  static const String dimEnabled = 'dim_enabled';
  static const String dimStart = 'dim_start_hour';
  static const String dimEnd = 'dim_end_hour';
  static const String dimLevel = 'dim_level';
  static const String geminiApiKey = 'gemini_api_key';
  static const String brainMode = 'brain_mode';
  static const String activeMember = 'active_member_id';
  static const String packUrl = 'knowledge_pack_url';
  static const String updateUrl = 'update_url';
  static const String photoUrl = 'photo_manifest_url';
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
      dim: _loadDim(fallback.dim),
      geminiApiKey:
          _prefs.getString(_PrefKey.geminiApiKey) ?? fallback.geminiApiKey,
      brainMode:
          BrainMode.fromName(_prefs.getString(_PrefKey.brainMode)) ??
          fallback.brainMode,
      activeMemberId:
          _prefs.getString(_PrefKey.activeMember) ?? fallback.activeMemberId,
      knowledgePackUrl:
          _prefs.getString(_PrefKey.packUrl) ?? fallback.knowledgePackUrl,
      updateUrl: _prefs.getString(_PrefKey.updateUrl) ?? fallback.updateUrl,
      photoManifestUrl:
          _prefs.getString(_PrefKey.photoUrl) ?? fallback.photoManifestUrl,
    ).normalized();
  }

  DimSettings _loadDim(DimSettings fallback) {
    return DimSettings(
      enabled: _prefs.getBool(_PrefKey.dimEnabled) ?? fallback.enabled,
      startHour: _prefs.getInt(_PrefKey.dimStart) ?? fallback.startHour,
      endHour: _prefs.getInt(_PrefKey.dimEnd) ?? fallback.endHour,
      level: _prefs.getDouble(_PrefKey.dimLevel) ?? fallback.level,
    );
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
      _prefs.setBool(_PrefKey.dimEnabled, value.dim.enabled),
      _prefs.setInt(_PrefKey.dimStart, value.dim.startHour),
      _prefs.setInt(_PrefKey.dimEnd, value.dim.endHour),
      _prefs.setDouble(_PrefKey.dimLevel, value.dim.level),
      _prefs.setString(_PrefKey.geminiApiKey, value.geminiApiKey),
      _prefs.setString(_PrefKey.brainMode, value.brainMode.name),
      _prefs.setString(_PrefKey.activeMember, value.activeMemberId),
      _prefs.setString(_PrefKey.packUrl, value.knowledgePackUrl),
      _prefs.setString(_PrefKey.updateUrl, value.updateUrl),
      _prefs.setString(_PrefKey.photoUrl, value.photoManifestUrl),
    ]);
  }
}
