import 'dart:async';

import '../core/constants/app_constants.dart';
import '../core/state/connection_status.dart';
import 'hub_transport.dart';
import 'protocol/hermes_message.dart';
import 'reconnect_backoff.dart';

/// Persistent connection to the Hermes Voice Bridge with auto-reconnect.
class HermesWebSocketClient {
  HermesWebSocketClient({
    TransportFactory? transportFactory,
    ReconnectBackoff? backoff,
  }) : _factory = transportFactory ?? WsTransport.new,
       _backoff = backoff ?? ReconnectBackoff();

  final TransportFactory _factory;
  final ReconnectBackoff _backoff;
  final StreamController<HermesMessage> _messages =
      StreamController<HermesMessage>.broadcast();
  final StreamController<ConnectionStatus> _statuses =
      StreamController<ConnectionStatus>.broadcast();

  ConnectionStatus _status = ConnectionStatus.disconnected;
  HubTransport? _transport;
  StreamSubscription<dynamic>? _subscription;
  Timer? _retryTimer;
  Uri? _uri;

  /// Bumped on every (re)connect so callbacks from stale sockets are ignored.
  int _generation = 0;
  int _attempt = 0;

  Stream<HermesMessage> get messages => _messages.stream;
  Stream<ConnectionStatus> get statusChanges => _statuses.stream;
  ConnectionStatus get status => _status;

  void connect(Uri uri) {
    _uri = uri;
    _attempt = 0;
    _reset();
    unawaited(_open());
  }

  void disconnect() {
    _uri = null;
    _reset();
    _setStatus(ConnectionStatus.disconnected);
  }

  bool send(String payload) {
    final transport = _liveTransport;
    if (transport == null) {
      return false;
    }
    transport.send(payload);
    return true;
  }

  bool sendAudio(List<int> pcm) {
    final transport = _liveTransport;
    if (transport == null) {
      return false;
    }
    transport.sendBytes(pcm);
    return true;
  }

  HubTransport? get _liveTransport {
    if (_status != ConnectionStatus.connected) {
      return null;
    }
    return _transport;
  }

  /// One-shot reachability check that does not disturb the live connection.
  Future<bool> probe(Uri uri) async {
    final transport = _factory(uri);
    try {
      await transport.ready.timeout(NetworkTiming.probeTimeout);
      return true;
    } on Object {
      return false;
    } finally {
      await _closeQuietly(transport);
    }
  }

  Future<void> dispose() async {
    _uri = null;
    _reset();
    await _messages.close();
    await _statuses.close();
  }

  Future<void> _open() async {
    final uri = _uri;
    if (uri == null) {
      return;
    }
    final generation = ++_generation;
    _setStatus(ConnectionStatus.connecting);
    final transport = _factory(uri);
    _transport = transport;
    try {
      await transport.ready.timeout(NetworkTiming.connectTimeout);
    } on Object {
      _handleDrop(generation);
      return;
    }
    if (generation != _generation) {
      return;
    }
    _attempt = 0;
    _subscription = transport.stream.listen(
      _onData,
      onError: (Object _) => _handleDrop(generation),
      onDone: () => _handleDrop(generation),
      cancelOnError: true,
    );
    _setStatus(ConnectionStatus.connected);
  }

  void _onData(dynamic raw) {
    final message = HermesCodec.decode(raw);
    if (message == null || _messages.isClosed) {
      return;
    }
    _messages.add(message);
  }

  void _handleDrop(int generation) {
    if (generation != _generation) {
      return;
    }
    _release();
    _setStatus(ConnectionStatus.disconnected);
    _scheduleRetry();
  }

  void _scheduleRetry() {
    if (_uri == null) {
      return;
    }
    final delay = _backoff.delayFor(_attempt);
    _attempt++;
    _retryTimer = Timer(delay, () => unawaited(_open()));
  }

  void _reset() {
    _generation++;
    _retryTimer?.cancel();
    _retryTimer = null;
    _release();
  }

  void _release() {
    unawaited(_subscription?.cancel());
    _subscription = null;
    final transport = _transport;
    _transport = null;
    if (transport != null) {
      unawaited(_closeQuietly(transport));
    }
  }

  void _setStatus(ConnectionStatus next) {
    if (next == _status || _statuses.isClosed) {
      return;
    }
    _status = next;
    _statuses.add(next);
  }

  static Future<void> _closeQuietly(HubTransport transport) async {
    try {
      await transport.close();
    } on Object {
      // Socket already dead; nothing to clean up.
    }
  }
}
