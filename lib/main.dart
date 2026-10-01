import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'core/state/display_controller.dart';
import 'services/hermes_websocket_client.dart';
import 'services/settings_service.dart';
import 'services/wakelock_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  await WakelockService().attach();
  final settings = await SettingsService.create();
  final controller = DisplayController(
    settingsService: settings,
    client: HermesWebSocketClient(),
  )..start();
  runApp(HermesApp(controller: controller));
}
