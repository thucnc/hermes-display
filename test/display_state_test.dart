import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_display/core/state/display_state.dart';

void main() {
  test('every state can return to idle', () {
    for (final state in DisplayState.values) {
      if (state == DisplayState.idle) {
        continue;
      }
      expect(canTransition(state, DisplayState.idle), isTrue);
    }
  });

  test('voice loop edges are legal', () {
    expect(canTransition(DisplayState.idle, DisplayState.listening), isTrue);
    expect(
      canTransition(DisplayState.listening, DisplayState.thinking),
      isTrue,
    );
    expect(canTransition(DisplayState.thinking, DisplayState.speaking), isTrue);
    expect(
      canTransition(DisplayState.speaking, DisplayState.listening),
      isTrue,
    );
  });

  test('illegal edges and self-loops are rejected', () {
    expect(
      canTransition(DisplayState.listening, DisplayState.speaking),
      isFalse,
    );
    expect(
      canTransition(DisplayState.thinking, DisplayState.listening),
      isFalse,
    );
    expect(canTransition(DisplayState.idle, DisplayState.idle), isFalse);
  });
}
