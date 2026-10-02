import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_display/core/photos/photo_frame.dart';
import 'package:hermes_display/core/state/display_controller.dart';
import 'package:hermes_display/services/hermes_websocket_client.dart';
import 'package:hermes_display/services/photo_manifest_service.dart';
import 'package:hermes_display/services/settings_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_gemini_service.dart';
import 'support/fake_transport.dart';
import 'support/photo_fixture.dart';

void main() {
  late SharedPreferences prefs;
  late FakeGeminiService gemini;
  late List<Uri> requests;

  Future<DisplayController> build({String photoUrl = photoManifestUrl}) async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    await SettingsService(prefs).save(
      HubSettings.defaults.copyWith(
        geminiApiKey: 'key',
        photoManifestUrl: photoUrl,
      ),
    );
    gemini = FakeGeminiService();
    requests = [];
    final frame = PhotoFrame(
      manifests: PhotoManifestService(
        prefs: prefs,
        client: MockClient((request) async {
          requests.add(request.url);
          return http.Response.bytes(utf8.encode(photoManifestJson), 200);
        }),
      ),
      clock: () => photoToday,
      random: Random(1),
    );
    final controller = DisplayController(
      settingsService: SettingsService(prefs),
      client: HermesWebSocketClient(
        transportFactory: FakeTransportFactory().call,
      ),
      gemini: gemini,
      photos: frame,
    )..start();
    await pumpEventQueue();
    return controller;
  }

  test('start boots the frame from the saved URL', () async {
    final controller = await build();
    expect(requests.single, Uri.parse(photoManifestUrl));
    expect(controller.photos.showsFamily, isTrue);
    controller.dispose();
  });

  test('"ảnh này chụp ở đâu?" sends the photo on screen to Gemini', () async {
    final controller = await build();
    expect(controller.photos.current!.id, 'zoo');

    controller.sendText('Sen ơi, ảnh này chụp ở đâu?');
    await pumpEventQueue();
    final context = gemini.contexts.single;
    expect(context, contains('Bé Na đi sở thú'));
    expect(context, contains('chụp ở: Thảo Cầm Viên'));
    expect(context, contains('ngày chụp: 02/10/2023 (3 năm trước)'));
    expect(context, contains('có: Bé'));
    controller.dispose();
  });

  test('other questions do not carry the photo', () async {
    final controller = await build();
    controller.sendText('Hôm nay thời tiết thế nào?');
    await pumpEventQueue();
    expect(gemini.contexts.single, isNot(contains('Ảnh gia đình')));
    controller.dispose();
  });

  test('placeholder photos add nothing to Gemini', () async {
    final controller = await build(photoUrl: '');
    controller.sendText('Ảnh này ở đâu?');
    await pumpEventQueue();
    expect(gemini.contexts.single, isNot(contains('Ảnh gia đình')));
    controller.dispose();
  });

  test('member switch reorders the frame', () async {
    final controller = await build();
    controller.selectMember('thuc');
    expect(controller.photos.order[2].id, 'dalat');
    controller.selectMember('be');
    expect(controller.photos.order[2].id, 'bday');
    controller.dispose();
  });

  test('a new photo URL in settings reboots the frame', () async {
    final controller = await build(photoUrl: '');
    expect(requests, isEmpty);
    expect(controller.isPhotoUrl(photoManifestUrl), isTrue);
    expect(controller.isPhotoUrl('nope'), isFalse);
    await controller.applySettings(
      controller.settings.copyWith(photoManifestUrl: photoManifestUrl),
    );
    await pumpEventQueue();
    expect(requests.single, Uri.parse(photoManifestUrl));
    expect(controller.photos.showsFamily, isTrue);
    await controller.applySettings(controller.settings.copyWith(port: 9000));
    await pumpEventQueue();
    expect(requests, hasLength(1));
    expect(SettingsService(prefs).load().photoManifestUrl, photoManifestUrl);
    controller.dispose();
  });
}
