import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../core/update/app_release.dart';

enum InstallResult {
  /// The system installer is showing.
  started,

  /// "Install unknown apps" was off; its settings page is now open.
  needsPermission,

  /// Not Android, or no APK ready.
  unsupported,
  failed,
}

/// Installed version and the system package installer.
/// Implementations report failures instead of throwing.
abstract interface class AppPlatform {
  /// Null when the platform cannot tell (tests, non-Android).
  Future<AppVersion?> version();

  /// Hands the APK at [path] (inside the app cache's update dir) to the
  /// system installer.
  Future<InstallResult> install(String path);
}

/// Android `MainActivity` handler on `hermes_display/updater`.
final class ChannelAppPlatform implements AppPlatform {
  const ChannelAppPlatform();

  @visibleForTesting
  static const MethodChannel channel = MethodChannel('hermes_display/updater');
  static const String _version = 'version';
  static const String _install = 'install';
  static const String _pathArg = 'path';
  static const String _codeKey = 'versionCode';
  static const String _nameKey = 'versionName';
  static const String _started = 'started';
  static const String _permission = 'permission';

  @override
  Future<AppVersion?> version() async {
    try {
      final map = await channel.invokeMapMethod<String, Object?>(_version);
      final code = map?[_codeKey];
      final name = map?[_nameKey];
      if (code is! int) {
        return null;
      }
      return AppVersion(code, name is String ? name : '');
    } on MissingPluginException {
      return null;
    } on Object catch (error) {
      debugPrint('Updater version failed: $error');
      return null;
    }
  }

  @override
  Future<InstallResult> install(String path) async {
    try {
      final reply = await channel.invokeMethod<String>(_install, {
        _pathArg: path,
      });
      return switch (reply) {
        _started => InstallResult.started,
        _permission => InstallResult.needsPermission,
        _ => InstallResult.failed,
      };
    } on MissingPluginException {
      return InstallResult.unsupported;
    } on Object catch (error) {
      debugPrint('Updater install failed: $error');
      return InstallResult.failed;
    }
  }
}
