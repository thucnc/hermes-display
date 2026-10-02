import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_display/app.dart';
import 'package:hermes_display/core/state/display_controller.dart';
import 'package:hermes_display/core/dimming/dim_schedule.dart';
import 'package:hermes_display/services/audio/mic_source.dart';
import 'package:hermes_display/services/hermes_websocket_client.dart';
import 'package:hermes_display/services/night_dimmer.dart';
import 'package:hermes_display/services/settings_service.dart';
import 'package:hermes_display/services/wake_word_service.dart';
import 'package:hermes_display/ui/screens/ambient_screen.dart';
import 'package:hermes_display/ui/strings.dart';
import 'package:hermes_display/ui/theme/app_theme.dart';
import 'package:hermes_display/ui/widgets/member_switcher.dart';
import 'package:hermes_display/ui/widgets/photo_slideshow.dart';
import 'package:hermes_display/ui/widgets/rich_card.dart';
import 'package:hermes_display/ui/widgets/status_badge.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_gemini_service.dart';
import 'support/fake_screen.dart';
import 'support/fake_sync.dart';
import 'support/fake_transport.dart';
import 'support/fake_voice.dart';

void main() {
  testWidgets('renders ambient UI and reacts to hub state', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = await SettingsService.create();
    final factory = FakeTransportFactory();
    final controller = DisplayController(
      settingsService: settings,
      client: HermesWebSocketClient(transportFactory: factory.call),
    )..start();

    await tester.pumpWidget(HermesApp(controller: controller));
    await tester.pump();
    expect(find.text(AppStrings.statusConnected), findsOneWidget);
    expect(find.textContaining(':'), findsWidgets);

    factory.last.push('{"type":"state","state":"listening"}');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text(AppStrings.listening), findsOneWidget);

    factory.last.push('{"type":"state","state":"thinking"}');
    factory.last.push('{"type":"tts","text":"Xin chào"}');
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Xin chào'), findsOneWidget);

    await tester.tap(find.byTooltip(AppStrings.tipSettings));
    // Waveform/pulse animate forever, so pumpAndSettle would never settle.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text(AppStrings.testConnection), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('tapping an avatar switches the active member', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final controller = DisplayController(
      settingsService: await SettingsService.create(),
      client: HermesWebSocketClient(
        transportFactory: FakeTransportFactory().call,
      ),
    )..start();
    await tester.pumpWidget(HermesApp(controller: controller));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(MemberSwitcher), findsOneWidget);

    await tester.tap(find.byKey(MemberSwitcher.keyFor('me')));
    await tester.pump();
    expect(controller.member.id, 'me');

    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('night window lowers opacity; touch brightens', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final screen = FakeScreen();
    final controller = DisplayController(
      settingsService: await SettingsService.create(),
      client: HermesWebSocketClient(
        transportFactory: FakeTransportFactory().call,
      ),
      dimmer: NightDimmer(
        screen: screen,
        clock: () => DateTime(2026, 10, 2, 3),
      ),
    )..start();

    await tester.pumpWidget(HermesApp(controller: controller));
    await tester.pump(const Duration(seconds: 1));
    double slideOpacity() {
      return tester
          .widget<AnimatedOpacity>(
            find
                .ancestor(
                  of: find.byType(PhotoSlideshow),
                  matching: find.byType(AnimatedOpacity),
                )
                .first,
          )
          .opacity;
    }

    expect(slideOpacity(), AmbientScreen.nightOpacity);

    await tester.tapAt(const Offset(400, 300));
    await tester.pump(const Duration(seconds: 1));
    expect(screen.lastBrightness, BrightnessTarget.system);
    expect(slideOpacity(), 1);

    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  group('mic indicator', () {
    Future<DisplayController> pumpWith(
      WidgetTester tester, {
      WakeWordService? voice,
    }) async {
      SharedPreferences.setMockInitialValues({});
      final controller = DisplayController(
        settingsService: await SettingsService.create(),
        client: HermesWebSocketClient(
          transportFactory: FakeTransportFactory().call,
        ),
        voice: voice,
      )..start();
      await tester.pumpWidget(HermesApp(controller: controller));
      await tester.pump(const Duration(seconds: 1));
      return controller;
    }

    WakeWordService voiceWith({
      MicPermission permission = MicPermission.granted,
      bool model = true,
    }) {
      return WakeWordService(
        mic: FakeMic(permission: permission),
        detector: FakeDetector(available: model),
        cue: FakeCue(),
      );
    }

    Future<void> expectMic(
      WidgetTester tester,
      DisplayController controller,
      MicIndicator expected,
      Color color,
    ) async {
      final icon = find.byKey(StatusBadge.micKey);
      expect(icon, findsOneWidget);
      expect(tester.widget<Icon>(icon).icon, StatusBadge.iconFor(expected));
      expect(tester.widget<Icon>(icon).color, color);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    }

    testWidgets('green while the wake word listens', (tester) async {
      final controller = await pumpWith(tester, voice: voiceWith());
      final labelled = find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == AppStrings.micArmed,
      );
      expect(labelled, findsOneWidget);
      await expectMic(
        tester,
        controller,
        MicIndicator.armed,
        AppPalette.online,
      );
    });

    testWidgets('grey when only the mic button works', (tester) async {
      final controller = await pumpWith(tester, voice: voiceWith(model: false));
      await expectMic(
        tester,
        controller,
        MicIndicator.manual,
        AppPalette.textMuted,
      );
    });

    testWidgets('warning when the mic is unavailable', (tester) async {
      final controller = await pumpWith(
        tester,
        voice: voiceWith(permission: MicPermission.denied),
      );
      await expectMic(
        tester,
        controller,
        MicIndicator.unavailable,
        AppPalette.pending,
      );
    });

    testWidgets('hidden without a voice pipeline', (tester) async {
      final controller = await pumpWith(tester);
      expect(find.byKey(StatusBadge.micKey), findsNothing);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    });
  });

  testWidgets('Gemini recipe shows a rich card that saves and stays', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'gemini_api_key': 'key'});
    final gemini = FakeGeminiService();
    final sync = FakeSync();
    final controller = DisplayController(
      settingsService: await SettingsService.create(),
      client: HermesWebSocketClient(
        transportFactory: FakeTransportFactory().call,
      ),
      gemini: gemini,
      sync: sync,
    )..start();
    await tester.pumpWidget(HermesApp(controller: controller));
    await tester.pump();

    controller.sendText('trứng chiên');
    gemini.answer('1. Đập trứng.\n2. Chiên vàng.');
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(RichCard), findsOneWidget);

    await tester.tap(find.text(AppStrings.saveToHermes));
    await tester.pump();
    await tester.pump();
    expect(sync.saved.single.$2.title, 'trứng chiên');
    expect(find.text(AppStrings.savedToBrain), findsOneWidget);

    controller.cancel();
    await tester.pump();
    expect(find.byType(RichCard), findsOneWidget);

    await tester.tap(find.byTooltip(AppStrings.tipClose));
    await tester.pump();
    expect(find.byType(RichCard), findsNothing);

    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
