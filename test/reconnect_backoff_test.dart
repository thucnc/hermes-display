import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_display/services/reconnect_backoff.dart';

void main() {
  final backoff = ReconnectBackoff(
    base: const Duration(seconds: 1),
    max: const Duration(seconds: 30),
    jitter: 0,
  );

  test('grows exponentially', () {
    expect(backoff.delayFor(0), const Duration(seconds: 1));
    expect(backoff.delayFor(1), const Duration(seconds: 2));
    expect(backoff.delayFor(3), const Duration(seconds: 8));
  });

  test('caps at max even for huge attempts', () {
    expect(backoff.delayFor(10), const Duration(seconds: 30));
    expect(backoff.delayFor(1 << 20), const Duration(seconds: 30));
  });

  test('jitter stays within bounds', () {
    final jittered = ReconnectBackoff(
      base: const Duration(seconds: 10),
      max: const Duration(seconds: 30),
      jitter: 0.2,
    );
    for (var i = 0; i < 50; i++) {
      final ms = jittered.delayFor(0).inMilliseconds;
      expect(ms, inInclusiveRange(8000, 12000));
    }
  });
}
