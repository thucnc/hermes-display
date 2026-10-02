import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

/// One pinned model file: fetched from `<baseUri>/<fileName>`.
final class ModelArtifact {
  const ModelArtifact(this.fileName, this.byteLength, this.sha256);

  final String fileName;
  final int byteLength;
  final String sha256;
}

/// What to install and where it comes from.
final class KwsModelSpec {
  const KwsModelSpec({
    required this.version,
    required this.baseUri,
    required this.encoder,
    required this.decoder,
    required this.joiner,
    required this.tokens,
  });

  /// sherpa-onnx `kws-zipformer-gigaspeech-3.3M-2024-01-01`, the files
  /// linked from sherpa-onnx's KWS docs. Hashes checked against ModelScope.
  static final KwsModelSpec gigaspeech = KwsModelSpec(
    version: 'gigaspeech-3.3m-2024-01-01-int8-v1',
    baseUri: Uri.parse(
      'https://www.modelscope.cn/models/pkufool/'
      'sherpa-onnx-kws-zipformer-gigaspeech-3.3M-2024-01-01/resolve/master',
    ),
    encoder: const ModelArtifact(
      'encoder-epoch-12-avg-2-chunk-16-left-64.int8.onnx',
      4843477,
      '1e721676515bcd42a186979733981213c66c80db680e1cc582dfedf3be76e678',
    ),
    decoder: const ModelArtifact(
      'decoder-epoch-12-avg-2-chunk-16-left-64.onnx',
      1018519,
      'f61ebd3eed3773a44d088d53dfae92dbb6aec4839f4dcaee2d402414741663a3',
    ),
    joiner: const ModelArtifact(
      'joiner-epoch-12-avg-2-chunk-16-left-64.int8.onnx',
      165845,
      'eae9da0c7e1e6c6a3f4cc42d167899c388f6c6701b94cb96320e4f55df79624c',
    ),
    tokens: const ModelArtifact(
      'tokens.txt',
      5006,
      'fd2ded4050a55d2b1578870ba8697d02371980217806b7558bd0a5cc60f3ba53',
    ),
  );

  final String version;
  final Uri baseUri;
  final ModelArtifact encoder;
  final ModelArtifact decoder;
  final ModelArtifact joiner;
  final ModelArtifact tokens;

  List<ModelArtifact> get artifacts => [encoder, decoder, joiner, tokens];

  int get totalBytes {
    return artifacts.fold(0, (sum, artifact) => sum + artifact.byteLength);
  }
}

abstract final class KwsLayout {
  static const String dirName = 'kws';
  static const String stagingName = 'kws.installing';
  static const String marker = 'installed.version';
  static const String keywords = 'keywords.txt';
}

/// Paths of a verified install.
final class KwsModelDir {
  const KwsModelDir({
    required this.directory,
    required this.encoder,
    required this.decoder,
    required this.joiner,
    required this.tokens,
  });

  final String directory;
  final String encoder;
  final String decoder;
  final String joiner;
  final String tokens;

  String get keywords => '$directory/${KwsLayout.keywords}';
}

final class ModelResponse {
  const ModelResponse(this.statusCode, this.body);

  final int statusCode;
  final Stream<List<int>> body;
}

/// HTTP seam so tests serve bytes from memory.
abstract interface class ModelHttp {
  Future<ModelResponse> get(Uri uri);
}

final class IoModelHttp implements ModelHttp {
  IoModelHttp({HttpClient? client})
    : _client = client ?? (HttpClient()..connectionTimeout = _connectTimeout);

  static const Duration _connectTimeout = Duration(seconds: 15);

  /// Abort when the mirror stalls mid-file.
  static const Duration _idleTimeout = Duration(seconds: 30);

  final HttpClient _client;

  @override
  Future<ModelResponse> get(Uri uri) async {
    final request = await _client.getUrl(uri);
    final response = await request.close();
    return ModelResponse(response.statusCode, response.timeout(_idleTimeout));
  }
}

enum InstallPhase { idle, downloading, verifying, ready, failed }

enum InstallFault { none, network, truncated, oversize, integrity, storage }

final class InstallProgress {
  const InstallProgress(
    this.phase, {
    this.receivedBytes = 0,
    this.totalBytes = 0,
    this.fault = InstallFault.none,
  });

  static const InstallProgress idle = InstallProgress(InstallPhase.idle);

  final InstallPhase phase;
  final int receivedBytes;
  final int totalBytes;
  final InstallFault fault;

  /// 0..1, or 0 when the size is unknown.
  double get fraction {
    if (totalBytes <= 0) {
      return 0;
    }
    return (receivedBytes / totalBytes).clamp(0.0, 1.0);
  }
}

final class _InstallError implements Exception {
  const _InstallError(this.fault, this.detail);

  final InstallFault fault;
  final String detail;

  @override
  String toString() => 'Wake model ${fault.name}: $detail';
}

/// Downloads the keyword model into `<app files>/kws/`.
///
/// Every file is pinned by length and SHA-256 and lands in a staging dir
/// first; the staging dir replaces `kws/` only after all of them pass, with
/// the version marker written last. An existing install is re-hashed once
/// per process before it is trusted.
class WakeModelInstaller {
  WakeModelInstaller({
    Future<Directory> Function()? root,
    ModelHttp? http,
    KwsModelSpec? spec,
  }) : _root = root ?? getApplicationSupportDirectory,
       _http = http ?? IoModelHttp(),
       _spec = spec ?? KwsModelSpec.gigaspeech;

  final Future<Directory> Function() _root;
  final ModelHttp _http;
  final KwsModelSpec _spec;
  final ValueNotifier<InstallProgress> _progress =
      ValueNotifier<InstallProgress>(InstallProgress.idle);

  KwsModelDir? _verified;
  Future<KwsModelDir?>? _running;

  ValueListenable<InstallProgress> get progress => _progress;

  /// Verified install or null; never downloads.
  Future<KwsModelDir?> installed() async {
    final cached = _verified;
    if (cached != null) {
      return cached;
    }
    final base = await _root();
    final dir = Directory('${base.path}/${KwsLayout.dirName}');
    try {
      _verified = await _verify(dir);
    } on FileSystemException catch (error) {
      debugPrint('Wake model check failed: $error');
      _verified = null;
    }
    if (_verified != null) {
      _progress.value = const InstallProgress(InstallPhase.ready);
    }
    return _verified;
  }

  /// Installs when missing or stale. Concurrent calls share one run.
  Future<KwsModelDir?> ensureInstalled() {
    return _running ??= _ensure().whenComplete(() => _running = null);
  }

  Future<KwsModelDir?> _ensure() async {
    final existing = await installed();
    if (existing != null) {
      return existing;
    }
    final base = await _root();
    final staging = Directory('${base.path}/${KwsLayout.stagingName}');
    try {
      return await _install(base, staging);
    } on Object catch (error) {
      debugPrint('$error');
      final fault = error is _InstallError ? error.fault : InstallFault.network;
      _progress.value = InstallProgress(InstallPhase.failed, fault: fault);
      await _deleteQuietly(staging);
      return null;
    }
  }

  Future<KwsModelDir?> _install(Directory base, Directory staging) async {
    await _deleteQuietly(staging);
    await staging.create(recursive: true);
    var received = 0;
    final fromAssets = await _copyFromAssets(staging);
    if (!fromAssets) {
      for (final artifact in _spec.artifacts) {
        final file = File('${staging.path}/${artifact.fileName}');
        await _download(artifact, file, (bytes) {
          received += bytes;
          _report(received);
        });
      }
    }
    _progress.value = InstallProgress(
      InstallPhase.verifying,
      receivedBytes: received,
      totalBytes: _spec.totalBytes,
    );
    await File('${staging.path}/${KwsLayout.marker}').writeAsString(
      _spec.version,
      flush: true,
    );
    final target = Directory('${base.path}/${KwsLayout.dirName}');
    await _deleteQuietly(target);
    await staging.rename(target.path);
    final model = await _verify(target);
    if (model == null) {
      throw const _InstallError(InstallFault.storage, 'post-install check');
    }
    _verified = model;
    _progress.value = const InstallProgress(InstallPhase.ready);
    return model;
  }

  Future<bool> _copyFromAssets(Directory staging) async {
    try {
      for (final artifact in _spec.artifacts) {
        final data = await rootBundle.load('assets/kws/${artifact.fileName}');
        final file = File('${staging.path}/${artifact.fileName}');
        await file.writeAsBytes(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          flush: true,
        );
      }
      return true;
    } on Object {
      return false;
    }
  }

  void _report(int received) {
    _progress.value = InstallProgress(
      InstallPhase.downloading,
      receivedBytes: received,
      totalBytes: _spec.totalBytes,
    );
  }

  Future<void> _download(
    ModelArtifact artifact,
    File file,
    void Function(int bytes) onChunk,
  ) async {
    final uri = Uri.parse('${_spec.baseUri}/${artifact.fileName}');
    final response = await _http.get(uri);
    if (response.statusCode != HttpStatus.ok) {
      throw _InstallError(
        InstallFault.network,
        '${artifact.fileName} HTTP ${response.statusCode}',
      );
    }
    final sink = file.openWrite();
    final digest = _DigestSink();
    final hasher = sha256.startChunkedConversion(digest);
    var written = 0;
    try {
      await for (final chunk in response.body) {
        written += chunk.length;
        if (written > artifact.byteLength) {
          throw _InstallError(InstallFault.oversize, artifact.fileName);
        }
        sink.add(chunk);
        hasher.add(chunk);
        onChunk(chunk.length);
      }
    } finally {
      await sink.close();
    }
    hasher.close();
    if (written != artifact.byteLength) {
      throw _InstallError(InstallFault.truncated, artifact.fileName);
    }
    if (digest.value.toString() != artifact.sha256) {
      throw _InstallError(InstallFault.integrity, artifact.fileName);
    }
  }

  Future<KwsModelDir?> _verify(Directory dir) async {
    final marker = File('${dir.path}/${KwsLayout.marker}');
    if (!await marker.exists()) {
      return null;
    }
    if ((await marker.readAsString()).trim() != _spec.version) {
      return null;
    }
    for (final artifact in _spec.artifacts) {
      if (!await _matches(File('${dir.path}/${artifact.fileName}'), artifact)) {
        return null;
      }
    }
    String path(ModelArtifact a) => '${dir.path}/${a.fileName}';
    return KwsModelDir(
      directory: dir.path,
      encoder: path(_spec.encoder),
      decoder: path(_spec.decoder),
      joiner: path(_spec.joiner),
      tokens: path(_spec.tokens),
    );
  }

  static Future<bool> _matches(File file, ModelArtifact artifact) async {
    if (!await file.exists()) {
      return false;
    }
    if (await file.length() != artifact.byteLength) {
      return false;
    }
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString() == artifact.sha256;
  }

  static Future<void> _deleteQuietly(Directory dir) async {
    if (!await dir.exists()) {
      return;
    }
    await dir.delete(recursive: true);
  }

  void dispose() => _progress.dispose();
}

final class _DigestSink implements Sink<Digest> {
  Digest? _value;

  Digest get value => _value!;

  @override
  void add(Digest data) => _value = data;

  @override
  void close() {}
}
