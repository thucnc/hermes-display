import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_display/services/audio/wake_model_installer.dart';

import 'support/fake_model_server.dart';

void main() {
  const version = 'test-v1';
  final base = Uri.parse('https://mirror.test/model');
  final payload = {
    'encoder.int8.onnx': utf8.encode('encoder-weights'),
    'decoder.onnx': utf8.encode('decoder-weights'),
    'joiner.int8.onnx': utf8.encode('joiner-weights'),
    'tokens.txt': utf8.encode('▁HE 49\nY 17\n'),
  };

  late Directory root;
  late FakeModelServer server;

  KwsModelSpec spec({String v = version, Map<String, String>? hashes}) {
    return KwsModelSpec(
      version: v,
      baseUri: base,
      encoder: artifactFor('encoder.int8.onnx', payload['encoder.int8.onnx']!),
      decoder: artifactFor('decoder.onnx', payload['decoder.onnx']!),
      joiner: _withHash(
        artifactFor('joiner.int8.onnx', payload['joiner.int8.onnx']!),
        hashes?['joiner.int8.onnx'],
      ),
      tokens: artifactFor('tokens.txt', payload['tokens.txt']!),
    );
  }

  WakeModelInstaller installer({KwsModelSpec? using}) {
    return WakeModelInstaller(
      root: () async => root,
      http: server,
      spec: using ?? spec(),
    );
  }

  Directory modelDir() => Directory('${root.path}/${KwsLayout.dirName}');
  Directory stagingDir() => Directory('${root.path}/${KwsLayout.stagingName}');

  setUp(() {
    root = Directory.systemTemp.createTempSync('kws_test');
    server = FakeModelServer(Map.of(payload));
  });

  tearDown(() => root.deleteSync(recursive: true));

  test('downloads, verifies and promotes all files', () async {
    final subject = installer();
    final model = await subject.ensureInstalled();

    expect(model, isNotNull);
    expect(server.requests, hasLength(4));
    expect(server.requests.first.toString(), startsWith('$base/'));
    expect(File(model!.encoder).readAsBytesSync(), payload['encoder.int8.onnx']);
    expect(
      File('${modelDir().path}/${KwsLayout.marker}').readAsStringSync(),
      version,
    );
    expect(stagingDir().existsSync(), isFalse);
    expect(subject.progress.value.phase, InstallPhase.ready);
  });

  test('bad hash promotes nothing and cleans staging', () async {
    final subject = installer(
      using: spec(hashes: {'joiner.int8.onnx': '0' * 64}),
    );
    expect(await subject.ensureInstalled(), isNull);

    expect(modelDir().existsSync(), isFalse);
    expect(stagingDir().existsSync(), isFalse);
    expect(subject.progress.value.phase, InstallPhase.failed);
    expect(subject.progress.value.fault, InstallFault.integrity);
  });

  test('truncated download is rejected', () async {
    server.modes['decoder.onnx'] = Serve.truncated;
    final subject = installer();
    expect(await subject.ensureInstalled(), isNull);
    expect(subject.progress.value.fault, InstallFault.truncated);
    expect(modelDir().existsSync(), isFalse);
  });

  test('oversize stream is cut off early', () async {
    server.modes['encoder.int8.onnx'] = Serve.endless;
    final subject = installer();
    expect(await subject.ensureInstalled(), isNull);

    expect(subject.progress.value.fault, InstallFault.oversize);
    expect(server.endlessCancelled, isTrue);
    final limitChunks = payload['encoder.int8.onnx']!.length ~/ 4 + 2;
    expect(server.endlessSent, lessThanOrEqualTo(limitChunks));
    expect(stagingDir().existsSync(), isFalse);
  });

  test('missing file on the mirror fails as network', () async {
    server.files.remove('tokens.txt');
    final subject = installer();
    expect(await subject.ensureInstalled(), isNull);
    expect(subject.progress.value.fault, InstallFault.network);
  });

  test('already installed model needs no network', () async {
    await installer().ensureInstalled();
    server.requests.clear();

    final fresh = installer();
    expect(await fresh.installed(), isNotNull);
    expect(await fresh.ensureInstalled(), isNotNull);
    expect(server.requests, isEmpty);
  });

  test('marker for another version triggers reinstall', () async {
    await installer().ensureInstalled();
    server.requests.clear();

    final upgraded = installer(using: spec(v: 'test-v2'));
    expect(await upgraded.installed(), isNull);
    expect(await upgraded.ensureInstalled(), isNotNull);
    expect(server.requests, hasLength(4));
    expect(
      File('${modelDir().path}/${KwsLayout.marker}').readAsStringSync(),
      'test-v2',
    );
  });

  test('tampered file with correct size is not trusted', () async {
    await installer().ensureInstalled();
    final joiner = File('${modelDir().path}/joiner.int8.onnx');
    final bytes = joiner.readAsBytesSync();
    bytes[0] = bytes[0] ^ 1;
    joiner.writeAsBytesSync(bytes);

    expect(await installer().installed(), isNull);
  });

  test('partial dir without marker is not trusted', () async {
    modelDir().createSync();
    for (final entry in payload.entries) {
      File('${modelDir().path}/${entry.key}').writeAsBytesSync(entry.value);
    }
    expect(await installer().installed(), isNull);
  });

  test('concurrent callers share one download', () async {
    final subject = installer();
    final results = await Future.wait([
      subject.ensureInstalled(),
      subject.ensureInstalled(),
    ]);
    expect(results.every((m) => m != null), isTrue);
    expect(server.requests, hasLength(4));
  });
}

ModelArtifact _withHash(ModelArtifact artifact, String? hash) {
  if (hash == null) {
    return artifact;
  }
  return ModelArtifact(artifact.fileName, artifact.byteLength, hash);
}
