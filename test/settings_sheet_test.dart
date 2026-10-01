import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_display/core/state/display_controller.dart';
import 'package:hermes_display/services/hermes_websocket_client.dart';
import 'package:hermes_display/services/settings_service.dart';
import 'package:hermes_display/ui/strings.dart';
import 'package:hermes_display/ui/widgets/settings_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_transport.dart';

void main() {
  late DisplayController controller;

  Future<void> open(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    controller = DisplayController(
      settingsService: await SettingsService.create(),
      client: HermesWebSocketClient(
        transportFactory: FakeTransportFactory().call,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showSettingsSheet(context, controller),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  tearDown(() => controller.dispose());

  testWidgets('shows model status and always-listening on', (tester) async {
    await open(tester);
    expect(find.text(AppStrings.modelIdle), findsOneWidget);
    final toggle = tester.widget<SwitchListTile>(
      find.widgetWithText(SwitchListTile, AppStrings.alwaysListening),
    );
    expect(toggle.value, isTrue);
  });

  testWidgets('rejects a keyword the model cannot spot', (tester) async {
    await open(tester);
    await tester.enterText(
      find.widgetWithText(TextFormField, AppStrings.wakeKeyword),
      'xin chào',
    );
    await tester.ensureVisible(find.text(AppStrings.save));
    await tester.tap(find.text(AppStrings.save));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.keywordUnsupported), findsOneWidget);
    expect(controller.settings.wakeKeyword, 'HEY SEN');
  });

  testWidgets('saves the always-listening toggle', (tester) async {
    await open(tester);
    await tester.ensureVisible(find.text(AppStrings.alwaysListening));
    await tester.tap(find.text(AppStrings.alwaysListening));
    await tester.pump();
    await tester.ensureVisible(find.text(AppStrings.save));
    await tester.tap(find.text(AppStrings.save));
    await tester.pumpAndSettle();
    expect(controller.settings.alwaysListening, isFalse);
  });

  testWidgets('night dimming: on by default, edits persist', (tester) async {
    await open(tester);
    final toggle = tester.widget<SwitchListTile>(
      find.widgetWithText(SwitchListTile, AppStrings.nightDim),
    );
    expect(toggle.value, isTrue);

    final start = find.widgetWithText(
      DropdownButtonFormField<int>,
      AppStrings.dimStart,
    );
    await tester.ensureVisible(start);
    await tester.tap(start);
    await tester.pumpAndSettle();
    await tester.tap(find.text('22:00').last);
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text(AppStrings.nightDim));
    await tester.tap(find.text(AppStrings.nightDim));
    await tester.pump();
    await tester.ensureVisible(find.text(AppStrings.save));
    await tester.tap(find.text(AppStrings.save));
    await tester.pumpAndSettle();
    expect(controller.settings.dim.startHour, 22);
    expect(controller.settings.dim.enabled, isFalse);
  });
}
