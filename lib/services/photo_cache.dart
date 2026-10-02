import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../core/constants/app_constants.dart';

/// Downloaded photos on disk, capped at [maxBytes] with least recently
/// shown files evicted first. Files are named by URL hash, so a photo
/// once shown keeps working offline.
class PhotoCache {
  PhotoCache({
    Future<Directory> Function()? root,
    http.Client? client,
    this.maxBytes = PhotoDefaults.cacheBytes,
  }) : _root = root ?? getApplicationSupportDirectory,
       _client = client ?? http.Client();

  final Future<Directory> Function() _root;
  final http.Client _client;
  final int maxBytes;
  final Map<String, Future<File?>> _inflight = {};
  Future<Directory>? _dir;
  static const int _httpOk = 200;
  static const String _extension = '.img';
  static const String _partial = '.part';

  /// Local file for [url]: from disk when present (marked as just used),
  /// else downloaded. Null when offline or the download fails.
  Future<File?> fetch(Uri url) {
    final key = _name(url);
    // Block body: returning the removed future would make it await itself.
    return _inflight[key] ??= _fetch(url, key).whenComplete(() {
      _inflight.remove(key);
    });
  }

  Future<File?> _fetch(Uri url, String name) async {
    final Directory dir;
    try {
      dir = await _directory();
    } on Exception {
      // No storage or no plugin: the slide falls back.
      return null;
    }
    final file = File('${dir.path}/$name');
    if (await file.exists()) {
      await _touch(file);
      return file;
    }
    final bytes = await _download(url);
    if (bytes == null) {
      return null;
    }
    try {
      final part = File('${file.path}$_partial');
      await part.writeAsBytes(bytes, flush: true);
      await part.rename(file.path);
      await _evict(dir, keep: file.path);
    } on FileSystemException {
      return null;
    }
    return file;
  }

  Future<List<int>?> _download(Uri url) async {
    final http.Response response;
    try {
      response = await _client.get(url).timeout(PhotoDefaults.downloadTimeout);
    } on Exception {
      return null;
    }
    final bytes = response.bodyBytes;
    if (response.statusCode != _httpOk || bytes.isEmpty) {
      return null;
    }
    return bytes.length > maxBytes ? null : bytes;
  }

  /// Oldest-used files go first until the cache fits; [keep] stays.
  Future<void> _evict(Directory dir, {required String keep}) async {
    final entries = <(File, FileStat)>[];
    var total = 0;
    await for (final entity in dir.list()) {
      if (entity is! File) {
        continue;
      }
      final stat = await entity.stat();
      entries.add((entity, stat));
      total += stat.size;
    }
    if (total <= maxBytes) {
      return;
    }
    entries.sort((a, b) => a.$2.modified.compareTo(b.$2.modified));
    for (final (file, stat) in entries) {
      if (total <= maxBytes) {
        return;
      }
      if (file.path == keep) {
        continue;
      }
      await file.delete();
      total -= stat.size;
    }
  }

  /// LRU clock: modification time is the last time it was shown.
  static Future<void> _touch(File file) async {
    try {
      await file.setLastModified(DateTime.now());
    } on FileSystemException {
      // Read-only or vanished; eviction order is a hint only.
    }
  }

  Future<Directory> _directory() {
    return _dir ??= _create().catchError((Object error) {
      _dir = null;
      throw error;
    });
  }

  Future<Directory> _create() async {
    final base = await _root();
    return Directory(
      '${base.path}/${PhotoDefaults.cacheDir}',
    ).create(recursive: true);
  }

  static String _name(Uri url) {
    return '${sha1.convert(utf8.encode(url.toString()))}$_extension';
  }
}
