import 'package:hermes_display/core/update/app_release.dart';
import 'package:hermes_display/services/update/app_platform.dart';

/// Installed build plus a record of installer launches.
class FakeAppPlatform implements AppPlatform {
  FakeAppPlatform({this.installed = const AppVersion(4, '0.5.1')});

  /// Null models a platform without the updater channel.
  AppVersion? installed;
  InstallResult reply = InstallResult.started;
  final List<String> installs = [];

  @override
  Future<AppVersion?> version() async => installed;

  @override
  Future<InstallResult> install(String path) async {
    installs.add(path);
    return reply;
  }
}
