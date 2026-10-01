import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_display/app.dart';
import 'package:hermes_display/core/state/display_controller.dart';
import 'package:hermes_display/core/dimming/dim_schedule.dart';
import 'package:hermes_display/services/hermes_websocket_client.dart';
import 'package:hermes_display/services/night_dimmer.dart';
import 'package:hermes_display/services/settings_service.dart';
import 'package:hermes_display/ui/screens/ambient_screen.dart';
import 'package:hermes_display/ui/strings.dart';
import 'package:hermes_display/ui/widgets/photo_slideshow.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_screen.dart';
import 'support/fake_transport.dart';

void main() {
  testWidgets('renders ambient UI and reacts to hub state', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = await SettingsService.create();
    final factory = FakeTransportFactory();
    final controller = DisplayController(
      settingsService: settings,
      client: HermesWebSocketClient(transportFactory: factory.call),
    )..start();

    await tester.pumpWidget(
      HermesApp(controller: controller, photos: const []),
    );
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

    await tester.pumpWidget(
      HermesApp(controller: controller, photos: const []),
    );
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
}
