import 'package:web_socket_channel/io.dart';

import '../core/constants/app_constants.dart';

/// Minimal socket contract so the client can be tested without a network.
abstract interface class HubTransport {
  Future<void> get ready;
  Stream<dynamic> get stream;
  void send(String data);
  Future<void> close();
}

typedef TransportFactory = HubTransport Function(Uri uri);

final class WsTransport implements HubTransport {
  WsTransport(Uri uri)
    : _channel = IOWebSocketChannel.connect(
        uri,
        pingInterval: NetworkTiming.pingInterval,
        connectTimeout: NetworkTiming.connectTimeout,
      );

  final IOWebSocketChannel _channel;

  @override
  Future<void> get ready => _channel.ready;

  @override
  Stream<dynamic> get stream => _channel.stream;

  @override
  void send(String data) => _channel.sink.add(data);

  @override
  Future<void> close() async => _channel.sink.close();
}
