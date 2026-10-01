import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_display/services/audio/mic_coordinator.dart';

void main() {
  test('only one owner at a time', () {
    final mic = MicCoordinator();
    final wake = mic.tryAcquire(MicOwner.wakeWord);
    expect(wake, isNotNull);
    expect(mic.tryAcquire(MicOwner.voiceTurn), isNull);
    expect(mic.owner, MicOwner.wakeWord);

    expect(mic.release(wake!), isTrue);
    expect(mic.owner, isNull);
    expect(mic.tryAcquire(MicOwner.voiceTurn), isNotNull);
  });

  test('stale lease cannot release the current owner', () {
    final mic = MicCoordinator();
    final first = mic.tryAcquire(MicOwner.wakeWord)!;
    mic.release(first);
    mic.tryAcquire(MicOwner.voiceTurn);

    expect(mic.release(first), isFalse);
    expect(mic.owner, MicOwner.voiceTurn);
  });

  test('announces ownership changes', () async {
    final mic = MicCoordinator();
    final seen = <MicOwner?>[];
    mic.changes.listen(seen.add);
    final lease = mic.tryAcquire(MicOwner.voiceTurn)!;
    mic.release(lease);
    await pumpEventQueue();
    expect(seen, [MicOwner.voiceTurn, null]);
  });
}
