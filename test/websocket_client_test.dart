import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_display/core/state/connection_status.dart';
import 'package:hermes_display/services/hermes_websocket_client.dart';
import 'package:hermes_display/services/protocol/hermes_message.dart';
import 'package:hermes_display/services/reconnect_backoff.dart';

import 'support/fake_transport.dart';

void main() {
  final uri = Uri.parse('ws://hub:8900');
  final backoff = ReconnectBackoff(jitter: 0);

  test('connects and forwards parsed messages', () {
    fakeAsync((async) {
      final factory = FakeTransportFactory();
      final client = HermesWebSocketClient(
        transportFactory: factory.call,
        backoff: backoff,
      );
      final statuses = <ConnectionStatus>[];
      final messages = <HermesMessage>[];
      client.statusChanges.listen(statuses.add);
      client.messages.listen(messages.add);

      client.connect(uri);
      async.flushMicrotasks();
      factory.last.push('{"type":"tts","text":"ok"}');
      factory.last.push('garbage');
      async.flushMicrotasks();

      expect(statuses, [
        ConnectionStatus.connecting,
        ConnectionStatus.connected,
      ]);
      expect(messages.single, isA<SpeechMessage>());
      expect(client.send('x'), isTrue);
      client.dispose();
    });
  });

  test('reconnects with backoff after failures and drops', () {
    fakeAsync((async) {
      final factory = FakeTransportFactory(
        outcomes: [FakeOutcome.reject, FakeOutcome.reject],
      );
      final client = HermesWebSocketClient(
        transportFactory: factory.call,
        backoff: backoff,
      );

      client.connect(uri);
      async.flushMicrotasks();
      expect(client.status, ConnectionStatus.disconnected);
      expect(factory.created, hasLength(1));

      async.elapse(const Duration(seconds: 1));
      expect(factory.created, hasLength(2));

      async.elapse(const Duration(milliseconds: 1999));
      expect(factory.created, hasLength(2));
      async.elapse(const Duration(milliseconds: 1));
      expect(client.status, ConnectionStatus.connected);

      factory.last.drop();
      async.flushMicrotasks();
      expect(client.status, ConnectionStatus.disconnected);
      expect(client.send('x'), isFalse);

      async.elapse(const Duration(seconds: 1));
      expect(factory.created, hasLength(4));
      expect(client.status, ConnectionStatus.connected);
      client.dispose();
    });
  });

  test('disconnect stops retrying', () {
    fakeAsync((async) {
      final factory = FakeTransportFactory(fallback: FakeOutcome.reject);
      final client = HermesWebSocketClient(
        transportFactory: factory.call,
        backoff: backoff,
      );
      client.connect(uri);
      async.flushMicrotasks();
      client.disconnect();
      async.elapse(const Duration(minutes: 5));
      expect(factory.created, hasLength(1));
      client.dispose();
    });
  });

  test('connect to new address closes the old socket', () {
    fakeAsync((async) {
      final factory = FakeTransportFactory();
      final client = HermesWebSocketClient(
        transportFactory: factory.call,
        backoff: backoff,
      );
      client.connect(uri);
      async.flushMicrotasks();
      final first = factory.last;
      client.connect(Uri.parse('ws://other:9000'));
      async.flushMicrotasks();
      expect(first.closed, isTrue);
      expect(factory.last.uri.host, 'other');
      expect(client.status, ConnectionStatus.connected);
      client.dispose();
    });
  });

  test('probe reports reachability and closes socket', () async {
    final factory = FakeTransportFactory(
      outcomes: [FakeOutcome.accept, FakeOutcome.reject],
    );
    final client = HermesWebSocketClient(transportFactory: factory.call);
    expect(await client.probe(uri), isTrue);
    expect(await client.probe(uri), isFalse);
    expect(factory.created.every((t) => t.closed), isTrue);
    await client.dispose();
  });
}
