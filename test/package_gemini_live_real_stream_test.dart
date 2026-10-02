import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:gemini_live/gemini_live.dart';

void main() {
  test('gemini_live package real bidi audio stream test', () async {
    final envFile = File('/Users/mac/.hermes/.env');
    if (!envFile.existsSync()) return;

    String? apiKey;
    for (final line in envFile.readAsLinesSync()) {
      if (line.startsWith('GOOGLE_API_KEY=')) {
        apiKey = line.split('=')[1].replaceAll('"', '').replaceAll("'", '').trim();
        break;
      }
    }

    if (apiKey == null || apiKey.isEmpty) return;

    final liveService = LiveService(apiKey: apiKey);
    final receivedAudio = <List<int>>[];
    final doneCompleter = Completer<void>();

    final session = await liveService.connect(
      LiveConnectParameters(
        model: LiveModels.gemini38Live,
        callbacks: LiveCallbacks(
          onMessage: (message) {
            final serverContent = message.serverContent;
            if (serverContent != null) {
              final modelTurn = serverContent.modelTurn;
              final parts = modelTurn?.parts;
              if (parts != null) {
                for (final part in parts) {
                  final data = part.inlineData?.data;
                  if (data != null) {
                    receivedAudio.add(base64Decode(data));
                  }
                }
              }
              if (serverContent.turnComplete == true) {
                if (!doneCompleter.isCompleted) doneCompleter.complete();
              }
            }
          },
          onClose: (code, reason) {
            if (!doneCompleter.isCompleted) doneCompleter.complete();
          },
        ),
        config: GenerationConfig(
          responseModalities: [Modality.AUDIO],
          speechConfig: SpeechConfig(
            voiceConfig: VoiceConfig(
              prebuiltVoiceConfig: PrebuiltVoiceConfig(voiceName: 'Puck'),
            ),
          ),
        ),
      ),
    );

    expect(session.setupComplete, isNotNull);

    // Send 1 sec sine tone PCM
    final sampleRate = 16000;
    final pcmBytes = Uint8List(sampleRate * 2);
    final byteData = ByteData.view(pcmBytes.buffer);
    for (int i = 0; i < sampleRate; i++) {
      final sample = (sin(2 * pi * 440 * (i / sampleRate)) * 16000).toInt();
      byteData.setInt16(i * 2, sample, Endian.little);
    }

    session.sendAudio(pcmBytes);
    session.sendMessage(
      LiveClientMessage(
        clientContent: LiveClientContent(turnComplete: true),
      ),
    );

    await doneCompleter.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () => {},
    );

    await session.close();
    expect(receivedAudio.isNotEmpty, isTrue);
  }, timeout: const Timeout(Duration(seconds: 30)));
}
