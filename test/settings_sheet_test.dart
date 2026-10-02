import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_display/core/state/brain_mode.dart';
import 'package:hermes_display/core/state/display_controller.dart';
import 'package:hermes_display/services/hermes_websocket_client.dart';
import 'package:hermes_display/services/sen_pack_service.dart';
import 'package:hermes_display/services/settings_service.dart';
import 'package:hermes_display/ui/strings.dart';
import 'package:hermes_display/ui/widgets/settings_sheet.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_transport.dart';
import 'support/sen_pack_fixture.dart';

void main() {
  late DisplayController controller;

  Future<void> open(WidgetTester tester, {MockClient? packHost}) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    controller = DisplayController(
      settingsService: SettingsService(prefs),
      client: HermesWebSocketClient(
        transportFactory: FakeTransportFactory().call,
      ),
      pack: packHost == null
          ? null
          : SenPackService(prefs: prefs, client: packHost),
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

  testWidgets('saves the Gemini key (obscured) and brain mode', (tester) async {
    await open(tester);
    final keyField = find.widgetWithText(TextFormField, AppStrings.geminiKey);
    await tester.ensureVisible(keyField);
    await tester.enterText(keyField, 'AIza-secret');
    final editable = tester.widget<EditableText>(
      find.descendant(of: keyField, matching: find.byType(EditableText)),
    );
    expect(editable.obscureText, isTrue);

    await tester.ensureVisible(find.text(AppStrings.brainHub));
    await tester.tap(find.text(AppStrings.brainHub));
    await tester.pump();
    await tester.ensureVisible(find.text(AppStrings.save));
    await tester.tap(find.text(AppStrings.save));
    await tester.pumpAndSettle();
    expect(controller.settings.geminiApiKey, 'AIza-secret');
    expect(controller.settings.brainMode, BrainMode.hub);
  });

  group('knowledge pack', () {
    const url = 'https://fam.pages.dev/sen-pack.json';
    final packField = find.widgetWithText(TextFormField, AppStrings.packUrl);

    Future<void> tapSync(WidgetTester tester) async {
      await tester.ensureVisible(find.text(AppStrings.syncNow));
      await tester.tap(find.text(AppStrings.syncNow));
    }

    testWidgets('sync now shows progress, then what was loaded', (
      tester,
    ) async {
      await open(
        tester,
        packHost: MockClient((_) async {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          return http.Response.bytes(utf8.encode(senPackJson), 200);
        }),
      );
      await tester.ensureVisible(packField);
      await tester.enterText(packField, url);
      await tapSync(tester);
      await tester.pump();
      expect(find.text(AppStrings.syncing), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 20));
      await tester.pumpAndSettle();
      expect(
        find.text(
          '${AppStrings.syncUpdated}: 3 ${AppStrings.syncMembers}, 3 '
          '${AppStrings.syncSkills}, 1 ${AppStrings.syncRituals} '
          '(a1b2c3d4e5f6)',
        ),
        findsOneWidget,
      );
      expect(controller.members.map((m) => m.id), ['thuc', 'be', 'ong']);
    });

    testWidgets('sync failure is reported', (tester) async {
      await open(
        tester,
        packHost: MockClient((_) async => http.Response('nope', 500)),
      );
      await tester.ensureVisible(packField);
      await tester.enterText(packField, url);
      await tapSync(tester);
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.syncFailed), findsOneWidget);
    });

    testWidgets('a bad URL is rejected before any request', (tester) async {
      var requests = 0;
      await open(
        tester,
        packHost: MockClient((_) async {
          requests++;
          return http.Response('', 200);
        }),
      );
      await tester.ensureVisible(packField);
      await tester.enterText(packField, 'ftp://nope');
      await tapSync(tester);
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.invalidPackUrl), findsOneWidget);
      expect(find.text(AppStrings.syncInvalid), findsOneWidget);
      expect(requests, 0);
    });

    testWidgets('saves the pack URL', (tester) async {
      await open(tester);
      await tester.ensureVisible(packField);
      await tester.enterText(packField, ' $url ');
      await tester.ensureVisible(find.text(AppStrings.save));
      await tester.tap(find.text(AppStrings.save));
      await tester.pumpAndSettle();
      expect(controller.settings.knowledgePackUrl, url);
    });
  });
}
