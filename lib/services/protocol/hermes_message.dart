import 'dart:convert';

import '../../core/state/display_state.dart';

/// JSON keys of the Hermes Voice Bridge wire protocol.
abstract final class WireKey {
  static const String type = 'type';
  static const String state = 'state';
  static const String text = 'text';
  static const String level = 'level';
  static const String isFinal = 'final';
}

/// Message `type` values. Incoming: state, tts, transcript, level, error.
/// Outgoing: text_input, wake, cancel.
abstract final class WireType {
  static const String state = 'state';
  static const String tts = 'tts';
  static const String transcript = 'transcript';
  static const String level = 'level';
  static const String error = 'error';
  static const String textInput = 'text_input';
  static const String wake = 'wake';
  static const String cancel = 'cancel';
}

sealed class HermesMessage {
  const HermesMessage();
}

final class StateMessage extends HermesMessage {
  const StateMessage(this.state);
  final DisplayState state;
}

final class SpeechMessage extends HermesMessage {
  const SpeechMessage(this.text);
  final String text;
}

final class TranscriptMessage extends HermesMessage {
  const TranscriptMessage(this.text, {required this.isFinal});
  final String text;
  final bool isFinal;
}

final class LevelMessage extends HermesMessage {
  const LevelMessage(this.level);
  final double level;
}

final class ErrorMessage extends HermesMessage {
  const ErrorMessage(this.text);
  final String text;
}

abstract final class HermesCodec {
  static const double _minLevel = 0;
  static const double _maxLevel = 1;

  /// Returns null for anything malformed; the bridge must never crash us.
  static HermesMessage? decode(Object? raw) {
    if (raw is! String) {
      return null;
    }
    final Object? json;
    try {
      json = jsonDecode(raw);
    } on FormatException {
      return null;
    }
    if (json is! Map<String, dynamic>) {
      return null;
    }
    return _fromMap(json);
  }

  static String userText(String text) {
    return jsonEncode({WireKey.type: WireType.textInput, WireKey.text: text});
  }

  static String command(String type) => jsonEncode({WireKey.type: type});

  static HermesMessage? _fromMap(Map<String, dynamic> map) {
    final text = _string(map[WireKey.text]);
    switch (map[WireKey.type]) {
      case WireType.state:
        final state = DisplayState.fromWire(_string(map[WireKey.state]));
        return state == null ? null : StateMessage(state);
      case WireType.tts:
        return text == null ? null : SpeechMessage(text);
      case WireType.transcript:
        final isFinal = map[WireKey.isFinal] == true;
        return text == null ? null : TranscriptMessage(text, isFinal: isFinal);
      case WireType.level:
        final level = map[WireKey.level];
        if (level is! num) {
          return null;
        }
        return LevelMessage(level.toDouble().clamp(_minLevel, _maxLevel));
      case WireType.error:
        return ErrorMessage(text ?? '');
    }
    return null;
  }

  static String? _string(Object? value) => value is String ? value : null;
}
