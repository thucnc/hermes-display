import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/state/display_controller.dart';
import 'services/audio/mic_keep_alive.dart';
import 'services/audio/tts_player.dart';
import 'services/audio/wake_model_installer.dart';
import 'services/gemini_service.dart';
import 'services/hermes_sync_service.dart';
import 'services/hermes_websocket_client.dart';
import 'services/hub_tts_service.dart';
import 'services/night_dimmer.dart';
import 'services/screen/screen_control.dart';
import 'services/sen_memory_service.dart';
import 'services/sen_pack_service.dart';
import 'services/settings_service.dart';
import 'services/wake_word_service.dart';
import 'services/wakelock_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  await WakelockService().attach();
  final prefs = await SharedPreferences.getInstance();
  final settings = SettingsService(prefs);
  final memory = await SqfliteSenMemoryService.device();
  final installer = WakeModelInstaller();
  final voice = WakeWordService.device(installer)..attachLifecycle();
  const screen = ChannelScreenControl();
  final dimmer = NightDimmer(screen: screen)..attachLifecycle();
  final controller = DisplayController(
    settingsService: settings,
    client: HermesWebSocketClient(),
    voice: voice,
    keepAlive: const ChannelKeepAlive(),
    installer: installer,
    screen: screen,
    dimmer: dimmer,
    tts: DeviceTtsPlayer(),
    gemini: HttpGeminiService(),
    sync: HermesSyncService(),
    hubTts: HubTtsService(),
    memory: memory,
    pack: SenPackService(prefs: prefs, memory: memory),
  )..start();
  runApp(HermesApp(controller: controller));
}
