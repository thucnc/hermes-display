import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_display/core/dimming/dim_schedule.dart';
import 'package:hermes_display/services/screen/screen_control.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const control = ChannelScreenControl();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];

  void answer(Object? Function(MethodCall call) reply) {
    messenger.setMockMethodCallHandler(ChannelScreenControl.channel, (
      call,
    ) async {
      calls.add(call);
      return reply(call);
    });
  }

  setUp(calls.clear);
  tearDown(() {
    messenger.setMockMethodCallHandler(ChannelScreenControl.channel, null);
  });

  test('sends level, or null for system brightness', () async {
    answer((_) => null);
    expect(
      await control.setBrightness(const BrightnessTarget.dim(0.05)),
      ScreenResult.ok,
    );
    expect(
      await control.setBrightness(BrightnessTarget.system),
      ScreenResult.ok,
    );
    expect(calls.map((c) => c.method), ['setBrightness', 'setBrightness']);
    expect(calls.first.arguments, {'level': 0.05});
    expect(calls.last.arguments, {'level': null});
  });

  test('wake and release map to native methods', () async {
    answer((_) => null);
    expect(await control.wake(), ScreenResult.ok);
    expect(await control.release(), ScreenResult.ok);
    expect(calls.map((c) => c.method), ['wakeScreen', 'releaseScreen']);
  });

  test('platform errors are reported, not thrown', () async {
    answer((_) => throw PlatformException(code: 'boom'));
    expect(await control.wake(), ScreenResult.failed);
    expect(
      await control.setBrightness(BrightnessTarget.system),
      ScreenResult.failed,
    );
  });

  test('missing native side reports unsupported', () async {
    expect(await control.release(), ScreenResult.unsupported);
  });
}
