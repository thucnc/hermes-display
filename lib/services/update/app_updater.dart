import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/dimming/dim_schedule.dart';
import '../../core/update/app_release.dart';
import 'app_platform.dart';

typedef UpdateClock = DateTime Function();

enum UpdatePhase { idle, checking, downloading, ready, failed }

/// Outcome of one [AppUpdater.check].
enum UpdateCheck {
  /// Nothing newer, or the endpoint has no release.
  upToDate,

  /// A newer APK is downloaded and verified.
  ready,

  /// Network, HTTP, storage or hash failure.
  failed,

  /// The installed version is unknown (not Android).
  unsupported,
}

final class UpdateState {
  const UpdateState(this.phase, {this.release, this.path});

  static const UpdateState idle = UpdateState(UpdatePhase.idle);

  final UpdatePhase phase;

  /// Set while downloading and once ready.
  final AppRelease? release;

  /// Verified APK; set only when [phase] is [UpdatePhase.ready].
  final String? path;
}

final class _UpdateError implements Exception {
  const _UpdateError(this.detail);

  final String detail;

  @override
  String toString() => 'App update: $detail';
}

/// Checks `GET /api/app/latest` on launch and once per night, downloads
/// a newer APK into `<cache>/updates/`, verifies its SHA-256 and hands it
/// to the system installer on request.
class AppUpdater {
  AppUpdater({
    required AppPlatform platform,
    http.Client? client,
    Future<Directory> Function()? cacheRoot,
    UpdateClock? clock,
  }) : _platform = platform,
       _client = client ?? http.Client(),
       _cacheRoot = cacheRoot ?? getApplicationCacheDirectory,
       _clock = clock ?? DateTime.now;

  final AppPlatform _platform;
  final http.Client _client;
  final Future<Directory> Function() _cacheRoot;
  final UpdateClock _clock;
  final ValueNotifier<UpdateState> _state = ValueNotifier<UpdateState>(
    UpdateState.idle,
  );
  static const int _httpOk = 200;
  static const int _httpNotFound = 404;

  Uri? _endpoint;
  DimSettings _dim = DimSettings.defaults;

  /// Last check started by the nightly tick; launch and manual checks
  /// do not count.
  DateTime? _lastNightly;
  Timer? _ticker;
  Future<UpdateCheck>? _running;
  AppVersion? _installed;
  bool _disposed = false;

  ValueListenable<UpdateState> get state => _state;

  /// Absolute http(s) URL with a host; null otherwise.
  static Uri? parseUrl(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || uri.host.isEmpty) {
      return null;
    }
    return UpdateDefaults.schemes.contains(uri.scheme) ? uri : null;
  }

  /// Launch check, then a nightly one inside [dim]'s hours.
  void start(Uri endpoint, DimSettings dim) {
    configure(endpoint, dim);
    _ticker ??= Timer.periodic(UpdateDefaults.tick, (_) => _onTick());
    unawaited(check());
  }

  void configure(Uri endpoint, DimSettings dim) {
    _endpoint = endpoint;
    _dim = dim;
  }

  void _onTick() {
    final now = _clock();
    if (!nightlyDue(now, _lastNightly, _dim)) {
      return;
    }
    _lastNightly = now;
    unawaited(check());
  }

  /// Checks [endpoint] (default: the configured one). Concurrent calls
  /// share one run.
  Future<UpdateCheck> check({Uri? endpoint, bool force = false}) {
    final target = endpoint ?? _endpoint;
    if (target == null) {
      return Future.value(UpdateCheck.failed);
    }
    return _running ??=
        _check(target, force: force).whenComplete(() => _running = null);
  }

  Future<UpdateCheck> _check(Uri endpoint, {bool force = false}) async {
    final installed = _installed ??= await _platform.version();
    if (installed == null) {
      return UpdateCheck.unsupported;
    }
    final previous = _state.value;
    _setState(UpdateState(UpdatePhase.checking, release: previous.release));
    try {
      return await _resolve(endpoint, installed, force: force);
    } on Object catch (error) {
      debugPrint('$error');
      // A verified APK stays installable when a later check fails.
      final keep = previous.phase == UpdatePhase.ready;
      _setState(keep ? previous : const UpdateState(UpdatePhase.failed));
      return keep ? UpdateCheck.ready : UpdateCheck.failed;
    }
  }

  Future<UpdateCheck> _resolve(
    Uri endpoint,
    AppVersion installed, {
    bool force = false,
  }) async {
    final release = await _fetchLatest(endpoint);
    if (release == null) {
      _setState(UpdateState.idle);
      return UpdateCheck.upToDate;
    }
    final dir = await _updateDir();
    if (!force && !release.isNewerThan(installed)) {
      await _clean(dir, keep: null);
      _setState(UpdateState.idle);
      return UpdateCheck.upToDate;
    }
    final target = File('${dir.path}/${_fileName(release)}');
    if (!await _matches(target, release.sha256)) {
      _setState(UpdateState(UpdatePhase.downloading, release: release));
      await _download(endpoint.resolve(release.url), target, release.sha256);
    }
    await _clean(dir, keep: target);
    _setState(
      UpdateState(UpdatePhase.ready, release: release, path: target.path),
    );
    return UpdateCheck.ready;
  }

  /// Null when the endpoint has no release (404).
  Future<AppRelease?> _fetchLatest(Uri endpoint) async {
    final response = await _client
        .get(endpoint)
        .timeout(UpdateDefaults.checkTimeout);
    if (response.statusCode == _httpNotFound) {
      return null;
    }
    if (response.statusCode != _httpOk) {
      throw _UpdateError('latest HTTP ${response.statusCode}');
    }
    final release = AppRelease.tryParse(response.body);
    if (release == null) {
      throw const _UpdateError('malformed latest.json');
    }
    return release;
  }

  Future<void> _download(Uri uri, File target, String sha) async {
    if (!UpdateDefaults.schemes.contains(uri.scheme)) {
      throw _UpdateError('bad APK url $uri');
    }
    final part = File('${target.path}${UpdateDefaults.partSuffix}');
    final response = await _client
        .send(http.Request('GET', uri))
        .timeout(UpdateDefaults.checkTimeout);
    if (response.statusCode != _httpOk) {
      throw _UpdateError('APK HTTP ${response.statusCode}');
    }
    final sink = part.openWrite();
    final digest = _DigestSink();
    final hasher = sha256.startChunkedConversion(digest);
    var written = 0;
    try {
      await for (final chunk in response.stream.timeout(
        UpdateDefaults.idleTimeout,
      )) {
        written += chunk.length;
        if (written > UpdateDefaults.maxApkBytes) {
          throw const _UpdateError('APK too large');
        }
        sink.add(chunk);
        hasher.add(chunk);
      }
    } finally {
      await sink.close();
    }
    hasher.close();
    if (digest.value.toString() != sha) {
      await _deleteQuietly(part);
      throw const _UpdateError('SHA-256 mismatch');
    }
    await part.rename(target.path);
  }

  Future<Directory> _updateDir() async {
    final root = await _cacheRoot();
    final dir = Directory('${root.path}/${UpdateDefaults.dirName}');
    await dir.create(recursive: true);
    return dir;
  }

  /// Drops stale APKs and partial downloads; [keep] survives.
  static Future<void> _clean(Directory dir, {required File? keep}) async {
    await for (final entry in dir.list()) {
      if (entry is File && entry.path != keep?.path) {
        await _deleteQuietly(entry);
      }
    }
  }

  static String _fileName(AppRelease release) {
    return '${UpdateDefaults.filePrefix}${release.versionCode}'
        '${UpdateDefaults.fileSuffix}';
  }

  static Future<bool> _matches(File file, String sha) async {
    if (!await file.exists()) {
      return false;
    }
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString() == sha;
  }

  static Future<void> _deleteQuietly(File file) async {
    try {
      await file.delete();
    } on FileSystemException {
      // Already gone.
    }
  }

  /// Opens the system installer for the verified APK.
  Future<InstallResult> install() async {
    final current = _state.value;
    final path = current.path;
    if (current.phase != UpdatePhase.ready || path == null) {
      return InstallResult.unsupported;
    }
    return _platform.install(path);
  }

  void _setState(UpdateState next) {
    if (_disposed) {
      return;
    }
    _state.value = next;
  }

  void dispose() {
    _disposed = true;
    _ticker?.cancel();
    _ticker = null;
    _state.dispose();
  }
}

final class _DigestSink implements Sink<Digest> {
  Digest? _value;

  Digest get value => _value!;

  @override
  void add(Digest data) => _value = data;

  @override
  void close() {}
}
