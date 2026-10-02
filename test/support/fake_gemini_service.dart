import 'dart:async';
import 'dart:typed_data';

import 'package:hermes_display/services/gemini_service.dart';

/// Answers are completed by the test, so turn ordering is controllable.
class FakeGeminiService implements GeminiService {
  final List<String> prompts = [];
  final List<Uint8List> audios = [];
  final List<String> keys = [];
  final List<String> contexts = [];
  final List<Completer<GeminiReply>> pending = [];

  @override
  Future<GeminiReply> ask(
    String prompt,
    String apiKey, {
    String memoryContext = '',
  }) {
    prompts.add(prompt);
    keys.add(apiKey);
    contexts.add(memoryContext);
    final completer = Completer<GeminiReply>();
    pending.add(completer);
    return completer.future;
  }

  @override
  Future<GeminiReply> askAudio(
    Uint8List wav,
    String apiKey, {
    String memoryContext = '',
  }) {
    audios.add(wav);
    keys.add(apiKey);
    contexts.add(memoryContext);
    final completer = Completer<GeminiReply>();
    pending.add(completer);
    return completer.future;
  }

  void answer(String text, {String transcript = ''}) => pending
      .removeAt(0)
      .complete(GeminiReply.of(text, transcript: transcript));

  void fail(String message) {
    pending.removeAt(0).completeError(GeminiException(message));
  }
}
