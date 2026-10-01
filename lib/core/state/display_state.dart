enum DisplayState {
  idle,
  listening,
  thinking,
  speaking;

  static DisplayState? fromWire(String? raw) {
    if (raw == null) {
      return null;
    }
    return values.asNameMap()[raw.toLowerCase()];
  }
}

/// Legal edges of the display state machine. Any state may drop to idle.
const Map<DisplayState, Set<DisplayState>> kAllowedTransitions = {
  DisplayState.idle: {
    DisplayState.listening,
    DisplayState.thinking,
    DisplayState.speaking,
  },
  DisplayState.listening: {DisplayState.idle, DisplayState.thinking},
  DisplayState.thinking: {DisplayState.idle, DisplayState.speaking},
  DisplayState.speaking: {
    DisplayState.idle,
    DisplayState.listening,
    DisplayState.thinking,
  },
};

bool canTransition(DisplayState from, DisplayState to) {
  if (from == to) {
    return false;
  }
  return kAllowedTransitions[from]?.contains(to) ?? false;
}
