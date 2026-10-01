import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'core/state/display_controller.dart';
import 'services/hermes_websocket_client.dart';
import 'services/settings_service.dart';
import 'services/wake_word_service.dart';
import 'services/wakelock_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  await WakelockService().attach();
  final settings = await SettingsService.create();
  final voice = WakeWordService.device()..attachLifecycle();
  final controller = DisplayController(
    settingsService: settings,
    client: HermesWebSocketClient(),
    voice: voice,
  )..start();
  runApp(HermesApp(controller: controller));
}
