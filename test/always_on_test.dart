import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_display/core/state/display_controller.dart';
import 'package:hermes_display/services/audio/mic_source.dart';
import 'package:hermes_display/services/audio/wake_model_installer.dart';
import 'package:hermes_display/services/hermes_websocket_client.dart';
import 'package:hermes_display/services/settings_service.dart';
import 'package:hermes_display/services/wake_word_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_keep_alive.dart';
import 'support/fake_model_server.dart';
import 'support/fake_transport.dart';
import 'support/fake_voice.dart';

void main() {
  late FakeMic mic;
  late FakeKeepAlive keepAlive;
  late WakeWordService voice;
  late DisplayController controller;

  Future<void> build({
    bool alwaysOn = true,
    MicPermission permission = MicPermission.granted,
    KeepAliveHealth health = KeepAliveHealth.ok,
    WakeModelInstaller? installer,
    FakeDetector? detector,
  }) async {
    SharedPreferences.setMockInitialValues({'always_listening': alwaysOn});
    mic = FakeMic(permission: permission);
    keepAlive = FakeKeepAlive(health: health);
    voice = WakeWordService(
      mic: mic,
      detector: detector ?? FakeDetector(),
      cue: FakeCue(),
    );
    controller = DisplayController(
      settingsService: await SettingsService.create(),
      client: HermesWebSocketClient(
        transportFactory: FakeTransportFactory(fallback: FakeOutcome.accept)
            .call,
      ),
      voice: voice,
      keepAlive: keepAlive,
      installer: installer,
    )..start();
    await pumpEventQueue();
  }

  tearDown(() => controller.dispose());

  test('always listening keeps the mic through screen-off', () async {
    await build();
    expect(keepAlive.running, isTrue);

    voice.handleLifecycle(AppLifecycleState.hidden);
    voice.handleLifecycle(AppLifecycleState.paused);
    await pumpEventQueue();
    expect(mic.isOpen, isTrue);
    expect(voice.phase, VoicePhase.armed);
  });

  test('turning it off stops the service and restores pausing', () async {
    await build();
    await controller.applySettings(
      controller.settings.copyWith(alwaysListening: false),
    );
    expect(keepAlive.running, isFalse);
    expect(keepAlive.stops, 1);

    voice.handleLifecycle(AppLifecycleState.paused);
    await pumpEventQueue();
    expect(mic.isOpen, isFalse);
  });

  test('disabled setting never starts the service', () async {
    await build(alwaysOn: false);
    expect(keepAlive.starts, 0);
    voice.handleLifecycle(AppLifecycleState.paused);
    await pumpEventQueue();
    expect(mic.isOpen, isFalse);
  });

  test('no mic permission, no foreground service', () async {
    await build(permission: MicPermission.permanentlyDenied);
    expect(keepAlive.starts, 0);
  });

  test('refused service falls back to pausing', () async {
    await build(health: KeepAliveHealth.refused);
    expect(keepAlive.starts, 1);
    voice.handleLifecycle(AppLifecycleState.paused);
    await pumpEventQueue();
    expect(mic.isOpen, isFalse);
  });

  group('model install', () {
    late Directory root;

    setUp(() => root = Directory.systemTemp.createTempSync('kws_ctrl'));
    tearDown(() => root.deleteSync(recursive: true));

    WakeModelInstaller installerWith(FakeModelServer server) {
      final files = server.files;
      ModelArtifact a(String name) => artifactFor(name, files[name]!);
      return WakeModelInstaller(
        root: () async => root,
        http: server,
        spec: KwsModelSpec(
          version: 'ctrl-v1',
          baseUri: Uri.parse('https://mirror.test'),
          encoder: a('e.onnx'),
          decoder: a('d.onnx'),
          joiner: a('j.onnx'),
          tokens: a('tokens.txt'),
        ),
      );
    }

    FakeModelServer serverWith() {
      return FakeModelServer({
        'e.onnx': utf8.encode('e'),
        'd.onnx': utf8.encode('d'),
        'j.onnx': utf8.encode('j'),
        'tokens.txt': utf8.encode('Y 17\n'),
      });
    }

    test('installs in the background, then arms the wake word', () async {
      final installer = installerWith(serverWith());
      await build(
        installer: installer,
        detector: FakeDetector(locate: installer.installed),
      );
      // Joins the controller's in-flight install (real file I/O).
      await installer.ensureInstalled();
      await pumpEventQueue();

      expect(controller.modelProgress.phase, InstallPhase.ready);
      expect(controller.voiceStatus, VoiceStatus.ready);
      expect(mic.isOpen, isTrue);
    });

    test('failed install leaves manual capture working', () async {
      final server = serverWith()..files.remove('tokens.txt');
      final installer = installerWith(serverWith());
      final broken = WakeModelInstaller(
        root: () async => root,
        http: server,
        spec: KwsModelSpec(
          version: 'ctrl-v1',
          baseUri: Uri.parse('https://mirror.test'),
          encoder: artifactFor('e.onnx', utf8.encode('e')),
          decoder: artifactFor('d.onnx', utf8.encode('d')),
          joiner: artifactFor('j.onnx', utf8.encode('j')),
          tokens: artifactFor('tokens.txt', utf8.encode('Y 17\n')),
        ),
      );
      await build(
        installer: broken,
        detector: FakeDetector(locate: installer.installed),
      );
      await broken.ensureInstalled();
      await pumpEventQueue();

      expect(controller.modelProgress.phase, InstallPhase.failed);
      expect(controller.voiceStatus, VoiceStatus.manualOnly);
      expect(await controller.listen(), ListenResult.started);
    });
  });
}
