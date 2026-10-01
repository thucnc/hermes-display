import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../services/audio/keyword_tokens.dart' as tokens;
import '../../services/audio/mic_keep_alive.dart';
import '../../services/audio/wake_model_installer.dart';
import '../../services/hermes_websocket_client.dart';
import '../../services/protocol/hermes_message.dart';
import '../../services/settings_service.dart';
import '../../services/wake_word_service.dart';
import '../constants/app_constants.dart';
import 'connection_status.dart';
import 'display_state.dart';

enum SendResult { sent, empty, offline }

enum ListenResult { started, busy, offline, noPermission, micUnavailable }

/// Single source of truth for the display. UI reads from here and calls
/// intents; services are never touched by widgets directly.
class DisplayController extends ChangeNotifier {
  DisplayController({
    required SettingsService settingsService,
    required HermesWebSocketClient client,
    WakeWordService? voice,
    MicKeepAlive? keepAlive,
    WakeModelInstaller? installer,
  }) : _settingsService = settingsService,
       _client = client,
       _voice = voice,
       _keepAlive = keepAlive,
       _installer = installer,
       _settings = settingsService.load();

  final SettingsService _settingsService;
  final HermesWebSocketClient _client;

  /// Null on builds without a microphone pipeline; mic button then only
  /// signals the hub.
  final WakeWordService? _voice;

  /// Null: no foreground service; the mic pauses with the app.
  final MicKeepAlive? _keepAlive;

  /// Null: no download; the model must already be on disk.
  final WakeModelInstaller? _installer;
  final List<StreamSubscription<Object?>> _subscriptions = [];
  final ValueNotifier<double> _level = ValueNotifier<double>(0);
  Timer? _watchdog;

  HubSettings _settings;
  DisplayState _state = DisplayState.idle;
  ConnectionStatus _connection = ConnectionStatus.disconnected;
  String _transcript = '';
  String _reply = '';
  String? _lastError;
  VoiceStatus? _voiceStatus;
  bool _starting = false;
  bool _disposed = false;

  HubSettings get settings => _settings;
  DisplayState get state => _state;
  ConnectionStatus get connection => _connection;
  String get transcript => _transcript;
  String get reply => _reply;
  String? get lastError => _lastError;
  VoiceStatus? get voiceStatus => _voiceStatus;

  InstallProgress get modelProgress {
    return _installer?.progress.value ?? InstallProgress.idle;
  }

  /// Settings keyword validation against the installed vocabulary.
  KeywordCheck checkKeyword(String keyword) {
    return _voice?.checkKeyword(keyword) ?? tokens.checkKeyword(keyword, null);
  }

  /// Audio level 0..1, updated at high rate; listen separately to avoid
  /// rebuilding the whole tree.
  ValueListenable<double> get level => _level;

  void start() {
    if (_subscriptions.isNotEmpty) {
      return;
    }
    _subscriptions
      ..add(_client.messages.listen(_onMessage))
      ..add(_client.statusChanges.listen(_onStatus));
    _client.connect(_settings.wsUri);
    _startVoice();
  }

  void _startVoice() {
    final voice = _voice;
    if (voice == null) {
      return;
    }
    _subscriptions.add(voice.events.listen(_onVoice));
    _installer?.progress.addListener(notifyListeners);
    unawaited(_bootVoice(voice));
  }

  Future<void> _bootVoice(WakeWordService voice) async {
    _setVoiceStatus(await voice.start(_settings.wakeConfig));
    await _applyKeepAlive();
    await installModel();
  }

  /// Downloads the keyword model if missing, then arms the wake word.
  /// Safe to call again after a failure (Settings retry button).
  Future<void> installModel() async {
    final installer = _installer;
    final voice = _voice;
    if (installer == null || voice == null) {
      return;
    }
    final model = await installer.ensureInstalled();
    if (model == null || _disposed) {
      return;
    }
    _setVoiceStatus(await voice.reloadModel());
  }

  /// Starts or stops the microphone foreground service to match settings.
  Future<void> _applyKeepAlive() async {
    final voice = _voice;
    final keepAlive = _keepAlive;
    if (voice == null || keepAlive == null) {
      return;
    }
    if (!_settings.alwaysListening || !_micAllowed) {
      voice.setBackgroundMode(BackgroundMode.releaseMic);
      await keepAlive.stop();
      return;
    }
    final running = await keepAlive.start();
    voice.setBackgroundMode(
      running ? BackgroundMode.keepListening : BackgroundMode.releaseMic,
    );
  }

  bool get _micAllowed {
    return switch (_voiceStatus) {
      VoiceStatus.noPermission || VoiceStatus.blocked || null => false,
      _ => true,
    };
  }

  void reconnect() => _client.connect(_settings.wsUri);

  bool transition(DisplayState next) {
    if (!canTransition(_state, next)) {
      return false;
    }
    _state = next;
    _onEnter(next);
    notifyListeners();
    return true;
  }

  SendResult sendText(String raw) {
    final text = raw.trim();
    if (text.isEmpty) {
      return SendResult.empty;
    }
    if (!_client.send(HermesCodec.userText(text))) {
      return SendResult.offline;
    }
    if (!transition(DisplayState.thinking)) {
      _reply = '';
    }
    _transcript = text;
    notifyListeners();
    return SendResult.sent;
  }

  /// Mic button and wake word entry point: cue, listening, then capture.
  Future<ListenResult> listen() async {
    final voice = _voice;
    if (voice == null) {
      return wake() ? ListenResult.started : ListenResult.offline;
    }
    if (_state == DisplayState.listening || _starting) {
      return ListenResult.busy;
    }
    if (_connection != ConnectionStatus.connected) {
      await voice.endCapture();
      return ListenResult.offline;
    }
    _starting = true;
    try {
      return await _beginListening(voice);
    } finally {
      _starting = false;
    }
  }

  Future<ListenResult> _beginListening(WakeWordService voice) async {
    await voice.playCue();
    final status = await voice.beginCapture();
    _setVoiceStatus(status);
    if (status != VoiceStatus.ready) {
      await voice.endCapture();
      return _failureFor(status);
    }
    if (!wake()) {
      await voice.endCapture();
      return ListenResult.offline;
    }
    return ListenResult.started;
  }

  static ListenResult _failureFor(VoiceStatus status) {
    return switch (status) {
      VoiceStatus.noPermission ||
      VoiceStatus.blocked => ListenResult.noPermission,
      _ => ListenResult.micUnavailable,
    };
  }

  bool wake() {
    if (!_client.send(HermesCodec.command(WireType.wake))) {
      return false;
    }
    return transition(DisplayState.listening);
  }

  void cancel() {
    _client.send(HermesCodec.command(WireType.cancel));
    _forceIdle();
  }

  Future<void> applySettings(HubSettings next) async {
    final normalized = next.normalized();
    final addressChanged = !normalized.sameAddress(_settings);
    final modeChanged = normalized.alwaysListening != _settings.alwaysListening;
    _settings = normalized;
    await _settingsService.save(normalized);
    notifyListeners();
    if (addressChanged) {
      _client.connect(normalized.wsUri);
    }
    await _voice?.configure(normalized.wakeConfig);
    if (modeChanged) {
      await _applyKeepAlive();
    }
  }

  Future<bool> testConnection(HubSettings candidate) {
    return _client.probe(candidate.normalized().wsUri);
  }

  void _onEnter(DisplayState next) {
    _armWatchdog(next);
    if (next != DisplayState.listening) {
      unawaited(_voice?.endCapture());
    }
    if (next == DisplayState.idle) {
      _transcript = '';
      _reply = '';
      _level.value = 0;
      return;
    }
    if (next == DisplayState.listening) {
      _transcript = '';
      _reply = '';
      return;
    }
    if (next == DisplayState.thinking) {
      _reply = '';
    }
  }

  void _armWatchdog(DisplayState current) {
    _watchdog?.cancel();
    if (current == DisplayState.idle) {
      return;
    }
    _watchdog = Timer(StateTiming.activeTimeout, _forceIdle);
  }

  void _onMessage(HermesMessage message) {
    _armWatchdog(_state);
    switch (message) {
      case StateMessage(:final state):
        transition(state);
      case SpeechMessage(:final text):
        _reply = text;
        if (!transition(DisplayState.speaking)) {
          notifyListeners();
        }
      case TranscriptMessage(:final text):
        _transcript = text;
        notifyListeners();
      case LevelMessage(:final level):
        _level.value = level;
      case ErrorMessage(:final text):
        _lastError = text;
        _forceIdle();
    }
  }

  void _onVoice(VoiceEvent event) {
    switch (event) {
      case WakeHeard():
        unawaited(_onWake());
      case SpeechAudio(:final pcm, :final level):
        if (_state != DisplayState.listening) {
          return;
        }
        _client.sendAudio(pcm);
        _level.value = level;
      case CaptureDone(:final reason):
        _onCaptureDone(reason);
    }
  }

  Future<void> _onWake() async {
    final result = await listen();
    if (result == ListenResult.started) {
      return;
    }
    await _voice?.endCapture();
  }

  void _onCaptureDone(CaptureEnd reason) {
    if (_state != DisplayState.listening) {
      return;
    }
    switch (reason) {
      case CaptureEnd.speechEnded:
      case CaptureEnd.maxLength:
        _client.send(HermesCodec.command(WireType.audioEnd));
        transition(DisplayState.thinking);
      case CaptureEnd.noSpeech:
      case CaptureEnd.stopped:
        cancel();
    }
  }

  void _setVoiceStatus(VoiceStatus status) {
    if (_disposed || status == _voiceStatus) {
      return;
    }
    _voiceStatus = status;
    notifyListeners();
  }

  void _onStatus(ConnectionStatus status) {
    _connection = status;
    if (status == ConnectionStatus.connected) {
      _lastError = null;
    }
    if (status != ConnectionStatus.connected) {
      _resetToIdle();
    }
    notifyListeners();
  }

  void _forceIdle() {
    if (!_resetToIdle()) {
      return;
    }
    notifyListeners();
  }

  bool _resetToIdle() {
    if (_state == DisplayState.idle) {
      return false;
    }
    _state = DisplayState.idle;
    _onEnter(DisplayState.idle);
    return true;
  }

  @override
  void dispose() {
    _disposed = true;
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _watchdog?.cancel();
    _installer?.progress.removeListener(notifyListeners);
    unawaited(_keepAlive?.stop());
    _client.dispose();
    _voice?.dispose();
    _level.dispose();
    super.dispose();
  }
}
