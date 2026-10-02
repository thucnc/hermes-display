import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/constants/app_constants.dart';
import 'hub_transport.dart';

/// What a Gemini Live session is opened with.
final class LiveSetup {
  const LiveSetup({
    required this.apiKey,
    required this.instruction,
    this.voice = GeminiLiveDefaults.voice,
  });

  final String apiKey;

  /// System instruction: persona plus member memory.
  final String instruction;
  final String voice;
}

enum LiveOpen { ready, noKey, failed }

sealed class LiveEvent {
  const LiveEvent();
}

/// One chunk of the spoken reply, PCM16 mono at [sampleRate].
final class LiveAudio extends LiveEvent {
  const LiveAudio(this.pcm, this.sampleRate);

  final Uint8List pcm;
  final int sampleRate;
}

/// Fragment of what Gemini heard the user say.
final class LiveHeard extends LiveEvent {
  const LiveHeard(this.text);

  final String text;
}

/// Fragment of the transcript of Gemini's spoken reply.
final class LiveSaid extends LiveEvent {
  const LiveSaid(this.text);

  final String text;
}

/// The user talked over the reply; queued audio is stale.
final class LiveInterrupted extends LiveEvent {
  const LiveInterrupted();
}

final class LiveTurnDone extends LiveEvent {
  const LiveTurnDone();
}

/// The server or network ended the session; [close] never sends this.
final class LiveClosed extends LiveEvent {
  const LiveClosed();
}

abstract final class _Key {
  static const String apiKey = 'key';
  static const String setup = 'setup';
  static const String model = 'model';
  static const String generationConfig = 'generationConfig';
  static const String modalities = 'responseModalities';
  static const String audio = 'AUDIO';
  static const String speechConfig = 'speechConfig';
  static const String voiceConfig = 'voiceConfig';
  static const String prebuilt = 'prebuiltVoiceConfig';
  static const String voiceName = 'voiceName';
  static const String system = 'systemInstruction';
  static const String parts = 'parts';
  static const String text = 'text';
  static const String inputAudioTranscription = 'inputAudioTranscription';
  static const String outputAudioTranscription = 'outputAudioTranscription';
  static const String realtimeInput = 'realtimeInput';
  static const String audioChunk = 'audio';
  static const String mimeType = 'mimeType';
  static const String data = 'data';
  static const String clientContent = 'clientContent';
  static const String setupComplete = 'setupComplete';
  static const String serverContent = 'serverContent';
  static const String modelTurn = 'modelTurn';
  static const String inlineData = 'inlineData';
  static const String heard = 'inputTranscription';
  static const String said = 'outputTranscription';
  static const String interrupted = 'interrupted';
  static const String turnComplete = 'turnComplete';
  static const String tools = 'tools';
  static const String googleSearch = 'google_search';
}

/// Gemini Live (BidiGenerateContent): mic PCM up, spoken reply PCM down.
/// One warm session is reused across turns until [close].
final class GeminiLiveService {
  GeminiLiveService({TransportFactory? transportFactory})
    : _factory = transportFactory ?? WsTransport.new;

  static final RegExp _rate = RegExp(r'rate=(\d+)');
  static const String _audioPrefix = 'audio/';

  final TransportFactory _factory;
  final StreamController<LiveEvent> _events =
      StreamController<LiveEvent>.broadcast();

  HubTransport? _transport;
  StreamSubscription<dynamic>? _subscription;
  Completer<void>? _setupDone;
  Future<LiveOpen>? _opening;

  /// Mic audio sent before the setup handshake finished.
  final List<List<int>> _queued = [];
  bool _endQueued = false;
  bool _ready = false;

  /// Bumped on every open and close so stale sockets are ignored.
  int _generation = 0;

  Stream<LiveEvent> get events => _events.stream;

  bool get isOpen => _ready;

  /// Connects and sends the setup; returns at once on a warm session.
  Future<LiveOpen> open(LiveSetup setup) async {
    if (setup.apiKey.isEmpty) {
      return LiveOpen.noKey;
    }
    if (_ready) {
      return LiveOpen.ready;
    }
    return _opening ??= _connect(setup).whenComplete(() => _opening = null);
  }

  Future<LiveOpen> _connect(LiveSetup setup) async {
    final generation = ++_generation;
    final transport = _factory(_endpoint(setup.apiKey));
    final done = Completer<void>();
    _transport = transport;
    _setupDone = done;
    try {
      await transport.ready.timeout(NetworkTiming.connectTimeout);
      if (generation != _generation) {
        return LiveOpen.failed;
      }
      _subscription = transport.stream.listen(
        (raw) => _onData(raw, generation),
        onError: (Object _) => _onDrop(generation),
        onDone: () => _onDrop(generation),
        cancelOnError: true,
      );
      transport.send(jsonEncode(_setupFrame(setup)));
      await done.future.timeout(GeminiLiveDefaults.setupTimeout);
    } on Object catch (error) {
      debugPrint('Gemini Live unavailable: $error');
      if (generation == _generation) {
        _release();
      }
      return LiveOpen.failed;
    }
    if (generation != _generation) {
      return LiveOpen.failed;
    }
    _ready = true;
    _flushQueued(transport);
    return LiveOpen.ready;
  }

  /// Streams PCM16 16 kHz mono; queued until [open] is ready, dropped
  /// when it fails.
  void sendAudio(List<int> pcm) {
    final transport = _transport;
    if (!_ready || transport == null) {
      _queued.add(pcm);
      return;
    }
    transport.send(_chunkFrame(pcm));
  }

  /// End of the user's speech: Gemini answers what it has heard.
  void endAudio() {
    final transport = _transport;
    if (!_ready || transport == null) {
      _endQueued = true;
      return;
    }
    transport.send(_endFrame);
  }

  /// Sends a text user turn; Gemini speaks and streams the reply.
  void sendText(String text) {
    final transport = _transport;
    if (!_ready || transport == null) {
      return;
    }
    transport.send(
      jsonEncode({
        _Key.clientContent: {
          'turns': [
            {
              'role': 'user',
              _Key.parts: [
                {_Key.text: text},
              ],
            },
          ],
          _Key.turnComplete: true,
        },
      }),
    );
  }

  Future<void> close() async {
    _generation++;
    _release();
  }

  Future<void> dispose() async {
    await close();
    await _events.close();
  }

  void _flushQueued(HubTransport transport) {
    for (final pcm in _queued) {
      transport.send(_chunkFrame(pcm));
    }
    _queued.clear();
    if (_endQueued) {
      _endQueued = false;
      transport.send(_endFrame);
    }
  }

  void _onData(dynamic raw, int generation) {
    if (generation != _generation) {
      return;
    }
    final json = _decode(raw);
    debugPrint('Gemini Live WS incoming message: ${raw is List<int> ? utf8.decode(raw, allowMalformed: true) : raw}');
    if (json == null) {
      return;
    }
    if (json.containsKey(_Key.setupComplete)) {
      final done = _setupDone;
      if (done != null && !done.isCompleted) {
        done.complete();
      }
      return;
    }
    final content = _map(json[_Key.serverContent]);
    if (content == null) {
      return;
    }
    _parseContent(content).forEach(_emit);
  }

  static Iterable<LiveEvent> _parseContent(Map<String, dynamic> content) {
    final heard = _map(content[_Key.heard])?[_Key.text];
    final said = _map(content[_Key.said])?[_Key.text];
    final parts = _map(content[_Key.modelTurn])?[_Key.parts];
    return [
      if (heard is String && heard.isNotEmpty) LiveHeard(heard),
      if (parts is List)
        for (final part in parts) ?_audioOf(_map(part)),
      if (said is String && said.isNotEmpty) LiveSaid(said),
      if (content[_Key.interrupted] == true) const LiveInterrupted(),
      if (content[_Key.turnComplete] == true) const LiveTurnDone(),
    ];
  }

  static LiveAudio? _audioOf(Map<String, dynamic>? part) {
    final inline = _map(part?[_Key.inlineData]);
    final mime = inline?[_Key.mimeType];
    final data = inline?[_Key.data];
    if (mime is! String || !mime.startsWith(_audioPrefix) || data is! String) {
      return null;
    }
    final rate = int.tryParse(_rate.firstMatch(mime)?.group(1) ?? '');
    try {
      return LiveAudio(
        base64Decode(data),
        rate ?? GeminiLiveDefaults.outputRate,
      );
    } on FormatException {
      return null;
    }
  }

  void _onDrop(int generation) {
    if (generation != _generation) {
      return;
    }
    final wasReady = _ready;
    _release();
    final done = _setupDone;
    if (done != null && !done.isCompleted) {
      done.completeError(StateError('closed during setup'));
    }
    if (wasReady) {
      _emit(const LiveClosed());
    }
  }

  void _emit(LiveEvent event) {
    if (_events.isClosed) {
      return;
    }
    _events.add(event);
  }

  void _release() {
    _ready = false;
    _queued.clear();
    _endQueued = false;
    unawaited(_subscription?.cancel());
    _subscription = null;
    final transport = _transport;
    _transport = null;
    if (transport != null) {
      unawaited(_closeQuietly(transport));
    }
  }

  static Future<void> _closeQuietly(HubTransport transport) async {
    try {
      await transport.close();
    } on Object {
      // Socket already dead; nothing to clean up.
    }
  }

  static Uri _endpoint(String apiKey) {
    return Uri(
      scheme: GeminiLiveDefaults.scheme,
      host: GeminiDefaults.host,
      path: GeminiLiveDefaults.path,
      queryParameters: {_Key.apiKey: apiKey},
    );
  }

  static Map<String, Object?> _setupFrame(LiveSetup setup) {
    return {
      _Key.setup: {
        _Key.model: GeminiLiveDefaults.model,
        _Key.generationConfig: {
          _Key.modalities: [_Key.audio],
          _Key.speechConfig: {
            _Key.voiceConfig: {
              _Key.prebuilt: {_Key.voiceName: setup.voice},
            },
          },
        },
        _Key.system: {
          _Key.parts: [
            {_Key.text: setup.instruction},
          ],
        },
        _Key.tools: [
          {_Key.googleSearch: <String, Object?>{}},
        ],
        _Key.inputAudioTranscription: <String, Object?>{},
        _Key.outputAudioTranscription: <String, Object?>{},
      },
    };
  }

  static final String _endFrame = jsonEncode({
    _Key.clientContent: {_Key.turnComplete: true},
  });

  static String _chunkFrame(List<int> pcm) {
    return jsonEncode({
      _Key.realtimeInput: {
        _Key.audioChunk: {
          _Key.mimeType: GeminiLiveDefaults.inputMime,
          _Key.data: base64Encode(pcm),
        },
      },
    });
  }

  /// The server sends JSON as text or as UTF-8 binary frames.
  static Map<String, dynamic>? _decode(dynamic raw) {
    try {
      final text = raw is List<int> ? utf8.decode(raw) : raw;
      return text is String ? _map(jsonDecode(text)) : null;
    } on FormatException {
      return null;
    }
  }

  static Map<String, dynamic>? _map(Object? value) {
    return value is Map<String, dynamic> ? value : null;
  }
}
