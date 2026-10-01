import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:hermes_display/services/audio/wake_model_installer.dart';

enum Serve { exact, truncated, endless }

/// In-memory stand-in for the model mirror.
class FakeModelServer implements ModelHttp {
  FakeModelServer(this.files);

  static const int _chunk = 4;

  final Map<String, List<int>> files;
  final Map<String, Serve> modes = {};
  final List<Uri> requests = [];
  bool endlessCancelled = false;
  int endlessSent = 0;

  @override
  Future<ModelResponse> get(Uri uri) async {
    requests.add(uri);
    final name = uri.pathSegments.last;
    final bytes = files[name];
    if (bytes == null) {
      return ModelResponse(HttpStatus.notFound, const Stream.empty());
    }
    return ModelResponse(HttpStatus.ok, _body(bytes, modes[name]));
  }

  Stream<List<int>> _body(List<int> bytes, Serve? mode) {
    if (mode == Serve.truncated) {
      return Stream.value(bytes.sublist(0, bytes.length - 1));
    }
    if (mode == Serve.endless) {
      return _endless();
    }
    final chunks = <List<int>>[];
    for (var i = 0; i < bytes.length; i += _chunk) {
      chunks.add(bytes.sublist(i, (i + _chunk).clamp(0, bytes.length)));
    }
    return Stream.fromIterable(chunks);
  }

  Stream<List<int>> _endless() {
    late final StreamController<List<int>> out;
    Timer? timer;
    out = StreamController<List<int>>(
      onListen: () {
        timer = Timer.periodic(Duration.zero, (_) {
          endlessSent++;
          out.add(List<int>.filled(_chunk, 1));
        });
      },
      onCancel: () {
        endlessCancelled = true;
        timer?.cancel();
      },
    );
    return out.stream;
  }
}

ModelArtifact artifactFor(String name, List<int> bytes) {
  return ModelArtifact(name, bytes.length, sha256.convert(bytes).toString());
}
