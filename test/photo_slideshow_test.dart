import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_display/core/photos/photo_frame.dart';
import 'package:hermes_display/services/photo_manifest_service.dart';
import 'package:hermes_display/ui/strings.dart';
import 'package:hermes_display/ui/widgets/photo_caption.dart';
import 'package:hermes_display/ui/widgets/photo_slideshow.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/photo_fixture.dart';

void main() {
  const interval = Duration(seconds: 5);

  Future<PhotoFrame> familyFrame({FakePhotoCache? cache}) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final frame = PhotoFrame(
      manifests: PhotoManifestService(
        prefs: prefs,
        client: MockClient(
          (_) async => http.Response.bytes(utf8.encode(photoManifestJson), 200),
        ),
      ),
      cache: cache,
      clock: () => photoToday,
      random: Random(1),
    )..setMember('be');
    await frame.boot(photoManifestUrl);
    return frame;
  }

  Widget host(PhotoFrame frame) {
    return MaterialApp(
      home: Stack(
        children: [
          PhotoSlideshow(interval: interval, frame: frame),
          Align(child: PhotoCaption(frame: frame)),
        ],
      ),
    );
  }

  ImageProvider? shownImage(WidgetTester tester) {
    final images = tester.widgetList<Image>(find.byType(Image));
    return images.isEmpty ? null : images.last.image;
  }

  testWidgets('empty frame shows the gradient and no caption', (tester) async {
    final frame = PhotoFrame();
    await tester.pumpWidget(host(frame));
    expect(find.byType(Image), findsNothing);
    expect(find.byType(DecoratedBox), findsWidgets);
    expect(find.text(AppStrings.onThisDay), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('placeholder deck streams from the network', (tester) async {
    final frame = PhotoFrame(deck: const ['https://picsum.photos/a']);
    await tester.runAsync(() => frame.boot(''));
    await tester.pumpWidget(host(frame));
    final image = shownImage(tester);
    expect(image, isA<NetworkImage>());
    expect((image! as NetworkImage).url, 'https://picsum.photos/a');
    expect(find.byType(PhotoCaption), findsOneWidget);
    expect(find.byType(Text), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('on-this-day photo gets the badge, timer advances', (
    tester,
  ) async {
    final frame = await tester.runAsync(
      () => familyFrame(cache: FakePhotoCache()),
    );
    await tester.pumpWidget(host(frame!));
    await tester.pump();
    expect(find.text(AppStrings.onThisDay), findsOneWidget);
    expect(
      find.text('Ngày này 3 năm trước (2023): Bé Na đi sở thú'),
      findsOneWidget,
    );
    expect((shownImage(tester)! as FileImage).file.path, '/cache/zoo.webp');

    await tester.pump(interval);
    await tester.pump(interval);
    await tester.pump(const Duration(seconds: 2));
    expect(frame.current!.id, 'bday');
    expect(find.text(AppStrings.onThisDay), findsNothing);
    expect(find.text('Sinh nhật Bé Na'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('interval change restarts the timer', (tester) async {
    final frame = PhotoFrame(deck: const ['a://1', 'a://2', 'a://3']);
    await tester.runAsync(() => frame.boot(''));
    await tester.pumpWidget(host(frame));
    final serial = frame.slide.serial;
    await tester.pumpWidget(
      MaterialApp(
        home: PhotoSlideshow(interval: interval * 2, frame: frame),
      ),
    );
    await tester.pump(interval);
    expect(frame.slide.serial, serial);
    await tester.pump(interval);
    expect(frame.slide.serial, serial + 1);
    await tester.pumpWidget(const SizedBox());
  });
}
