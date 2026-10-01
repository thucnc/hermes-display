import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'core/state/display_controller.dart';
import 'services/audio/mic_keep_alive.dart';
import 'services/audio/wake_model_installer.dart';
import 'services/hermes_websocket_client.dart';
import 'services/settings_service.dart';
import 'services/wake_word_service.dart';
import 'services/wakelock_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  await WakelockService().attach();
  final settings = await SettingsService.create();
  final installer = WakeModelInstaller();
  final voice = WakeWordService.device(installer)..attachLifecycle();
  final controller = DisplayController(
    settingsService: settings,
    client: HermesWebSocketClient(),
    voice: voice,
    keepAlive: const ChannelKeepAlive(),
    installer: installer,
  )..start();
  runApp(HermesApp(controller: controller));
}
