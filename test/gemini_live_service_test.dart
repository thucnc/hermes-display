import 'dart:convert';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_display/core/constants/app_constants.dart';
import 'package:hermes_display/services/gemini_live_service.dart';

import 'support/fake_transport.dart';

void main() {
  const setup = LiveSetup(
    apiKey: 'k3y',
    instruction: 'Bạn là Sen',
    voice: 'Kore',
  );
  const setupComplete = '{"setupComplete":{}}';
  late FakeTransportFactory sockets;
  late GeminiLiveService live;
  late List<LiveEvent> events;

  void build({FakeOutcome outcome = FakeOutcome.accept}) {
    sockets = FakeTransportFactory(fallback: outcome);
    live = GeminiLiveService(transportFactory: sockets.call);
    events = [];
    live.events.listen(events.add);
  }

  Future<LiveOpen> opened() async {
    final result = live.open(setup);
    await pumpEventQueue();
    sockets.last.push(setupComplete);
    return result;
  }

  Map<String, dynamic> sent(int index) {
    return jsonDecode(sockets.last.sent[index]) as Map<String, dynamic>;
  }

  String serverAudio(List<int> pcm) {
    return jsonEncode({
      'serverContent': {
        'modelTurn': {
          'parts': [
            {
              'inlineData': {
                'mimeType': 'audio/pcm;rate=24000',
                'data': base64Encode(pcm),
              },
            },
          ],
        },
      },
    });
  }

  tearDown(() => live.dispose());

  test('connects to the BidiGenerateContent endpoint with the key', () async {
    build();
    expect(await opened(), LiveOpen.ready);
    final uri = sockets.last.uri;
    expect(uri.scheme, 'wss');
    expect(uri.host, GeminiDefaults.host);
    expect(
      uri.path,
      '/ws/google.ai.generativelanguage.v1alpha.GenerativeService'
      '.BidiGenerateContent',
    );
    expect(uri.queryParameters['key'], 'k3y');
    expect(live.isOpen, isTrue);
  });

  test('first frame is the audio-only setup with voice and persona', () async {
    build();
    await opened();
    final body = sent(0)['setup'] as Map<String, dynamic>;
    expect(body['model'], 'models/gemini-3.8-live');
    final config = body['generationConfig'] as Map<String, dynamic>;
    expect(config['responseModalities'], ['AUDIO']);
    expect(config['speechConfig'], {
      'voiceConfig': {
        'prebuiltVoiceConfig': {'voiceName': 'Kore'},
      },
    });
    expect(body['systemInstruction'], {
      'parts': [
        {'text': 'Bạn là Sen'},
      ],
    });
    expect(body['inputAudioTranscription'], isEmpty);
    expect(body['outputAudioTranscription'], isEmpty);
  });

  test('mic audio before setupComplete is queued, then streamed', () async {
    build();
    final result = live.open(setup);
    live.sendAudio([1, 2, 3, 4]);
    await pumpEventQueue();
    expect(sockets.last.sent, hasLength(1));

    sockets.last.push(setupComplete);
    await result;
    live.sendAudio([5, 6]);
    final chunks = [
      for (var i = 1; i < sockets.last.sent.length; i++)
        ((sent(i)['realtimeInput'] as Map)['mediaChunks'] as List).single,
    ];
    expect(chunks, [
      {
        'mimeType': 'audio/pcm;rate=16000',
        'data': base64Encode([1, 2, 3, 4]),
      },
      {
        'mimeType': 'audio/pcm;rate=16000',
        'data': base64Encode([5, 6]),
      },
    ]);
  });

  test('endAudio flushes the server-side turn', () async {
    build();
    await opened();
    live.endAudio();
    expect(sent(1), {
      'clientContent': {'turnComplete': true},
    });
  });

  test('open on a warm session does not reconnect', () async {
    build();
    await opened();
    expect(await live.open(setup), LiveOpen.ready);
    expect(sockets.created, hasLength(1));
  });

  test('empty key never dials', () async {
    build();
    final result = await live.open(
      const LiveSetup(apiKey: '', instruction: '', voice: 'Puck'),
    );
    expect(result, LiveOpen.noKey);
    expect(sockets.created, isEmpty);
  });

  test('refused socket fails the open', () async {
    build(outcome: FakeOutcome.reject);
    expect(await live.open(setup), LiveOpen.failed);
    expect(live.isOpen, isFalse);
  });

  test('missing setupComplete times out', () {
    fakeAsync((async) {
      build();
      LiveOpen? result;
      live.open(setup).then((value) => result = value);
      async.elapse(GeminiLiveDefaults.setupTimeout);
      expect(result, LiveOpen.failed);
      expect(sockets.last.closed, isTrue);
    });
  });

  group('server content', () {
    test('audio chunks carry PCM and the sample rate', () async {
      build();
      await opened();
      sockets.last.push(serverAudio([9, 8, 7, 6]));
      await pumpEventQueue();
      final audio = events.single as LiveAudio;
      expect(audio.pcm, Uint8List.fromList([9, 8, 7, 6]));
      expect(audio.sampleRate, 24000);
    });

    test('binary frames are decoded as JSON', () async {
      build();
      await opened();
      sockets.last.push(utf8.encode(serverAudio([1, 2])));
      await pumpEventQueue();
      expect(events.single, isA<LiveAudio>());
    });

    test('transcriptions, barge-in and turn end become events', () async {
      build();
      await opened();
      sockets.last
        ..push('{"serverContent":{"inputAudioTranscription":{"text":"mấy giờ"}}}')
        ..push('{"serverContent":{"outputAudioTranscription":{"text":"Ba giờ"}}}')
        ..push('{"serverContent":{"interrupted":true}}')
        ..push('{"serverContent":{"turnComplete":true}}')
        ..push('not json');
      await pumpEventQueue();
      expect(events, [
        isA<LiveHeard>().having((e) => e.text, 'text', 'mấy giờ'),
        isA<LiveSaid>().having((e) => e.text, 'text', 'Ba giờ'),
        isA<LiveInterrupted>(),
        isA<LiveTurnDone>(),
      ]);
    });

    test('a dropped socket reports LiveClosed once', () async {
      build();
      await opened();
      await sockets.last.drop();
      await pumpEventQueue();
      expect(events.single, isA<LiveClosed>());
      expect(live.isOpen, isFalse);
    });

    test('our own close is silent', () async {
      build();
      await opened();
      await live.close();
      await pumpEventQueue();
      expect(events, isEmpty);
      expect(sockets.last.closed, isTrue);
    });
  });
}
