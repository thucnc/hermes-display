import 'dart:async';

import 'package:hermes_display/services/hub_transport.dart';

enum FakeOutcome { accept, reject }

class FakeTransport implements HubTransport {
  FakeTransport(this.uri, {required FakeOutcome outcome}) {
    if (outcome == FakeOutcome.accept) {
      _ready.complete();
      return;
    }
    _ready.completeError(StateError('refused'));
  }

  final Uri uri;
  final Completer<void> _ready = Completer<void>();
  final StreamController<dynamic> _incoming = StreamController<dynamic>();
  final List<String> sent = [];
  final List<List<int>> sentBytes = [];
  bool closed = false;

  @override
  Future<void> get ready => _ready.future;

  @override
  Stream<dynamic> get stream => _incoming.stream;

  @override
  void send(String data) => sent.add(data);

  @override
  void sendBytes(List<int> data) => sentBytes.add(data);

  @override
  Future<void> close() async {
    closed = true;
  }

  void push(Object data) => _incoming.add(data);

  Future<void> drop() => _incoming.close();
}

/// Records every transport it creates; outcomes are consumed in order,
/// then [fallback] applies.
class FakeTransportFactory {
  FakeTransportFactory({
    List<FakeOutcome> outcomes = const [],
    this.fallback = FakeOutcome.accept,
  }) : _outcomes = List.of(outcomes);

  final List<FakeOutcome> _outcomes;
  final FakeOutcome fallback;
  final List<FakeTransport> created = [];

  FakeTransport get last => created.last;

  HubTransport call(Uri uri) {
    final outcome = _outcomes.isEmpty ? fallback : _outcomes.removeAt(0);
    final transport = FakeTransport(uri, outcome: outcome);
    created.add(transport);
    return transport;
  }
}
