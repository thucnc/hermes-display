import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../services/hermes_websocket_client.dart';
import '../../services/protocol/hermes_message.dart';
import '../../services/settings_service.dart';
import '../constants/app_constants.dart';
import 'connection_status.dart';
import 'display_state.dart';

enum SendResult { sent, empty, offline }

/// Single source of truth for the display. UI reads from here and calls
/// intents; services are never touched by widgets directly.
class DisplayController extends ChangeNotifier {
  DisplayController({
    required SettingsService settingsService,
    required HermesWebSocketClient client,
  }) : _settingsService = settingsService,
       _client = client,
       _settings = settingsService.load();

  final SettingsService _settingsService;
  final HermesWebSocketClient _client;
  final List<StreamSubscription<Object?>> _subscriptions = [];
  final ValueNotifier<double> _level = ValueNotifier<double>(0);
  Timer? _watchdog;

  HubSettings _settings;
  DisplayState _state = DisplayState.idle;
  ConnectionStatus _connection = ConnectionStatus.disconnected;
  String _transcript = '';
  String _reply = '';
  String? _lastError;

  HubSettings get settings => _settings;
  DisplayState get state => _state;
  ConnectionStatus get connection => _connection;
  String get transcript => _transcript;
  String get reply => _reply;
  String? get lastError => _lastError;

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
    _settings = normalized;
    await _settingsService.save(normalized);
    notifyListeners();
    if (addressChanged) {
      _client.connect(normalized.wsUri);
    }
  }

  Future<bool> testConnection(HubSettings candidate) {
    return _client.probe(candidate.normalized().wsUri);
  }

  void _onEnter(DisplayState next) {
    _armWatchdog(next);
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
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _watchdog?.cancel();
    _client.dispose();
    _level.dispose();
    super.dispose();
  }
}
