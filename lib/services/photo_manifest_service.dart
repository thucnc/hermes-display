import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants/app_constants.dart';
import '../core/photos/photo_manifest.dart';

enum PhotoSync {
  /// New manifest downloaded and cached.
  updated,

  /// The host has nothing newer than the cache.
  unchanged,

  /// Bad URL, or the body is not a usable manifest.
  invalid,

  /// Network or HTTP error; the cache is untouched.
  failed,
}

class PhotoSyncResult {
  const PhotoSyncResult(this.status, [this.manifest]);

  final PhotoSync status;

  /// The manifest now in effect for the URL; null when none.
  final PhotoManifest? manifest;
}

abstract final class _PrefKey {
  static const String body = 'photo_manifest_json';
  static const String etag = 'photo_manifest_etag';
  static const String url = 'photo_manifest_url';
}

abstract final class _Header {
  static const String etag = 'etag';
  static const String ifNoneMatch = 'if-none-match';
}

/// Downloads `photos.json` (hub `GET /api/photos/manifest` or any static
/// host) and keeps the last good copy for offline boots.
class PhotoManifestService {
  PhotoManifestService({required SharedPreferences prefs, http.Client? client})
    : _prefs = prefs,
      _client = client ?? http.Client();

  final SharedPreferences _prefs;
  final http.Client _client;
  static const int _httpOk = 200;
  static const int _httpNotModified = 304;

  /// Absolute http(s) URL with a host; null otherwise.
  static Uri? parseUrl(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || uri.host.isEmpty) {
      return null;
    }
    return PhotoManifest.schemes.contains(uri.scheme) ? uri : null;
  }

  /// Last manifest downloaded from [url]; another URL's cache is ignored.
  PhotoManifest? loadCached(String url) {
    final uri = parseUrl(url);
    if (uri == null || _prefs.getString(_PrefKey.url) != uri.toString()) {
      return null;
    }
    final body = _prefs.getString(_PrefKey.body);
    return body == null ? null : PhotoManifest.tryParse(body, uri);
  }

  Future<PhotoSyncResult> fetch(String url) async {
    final uri = parseUrl(url);
    if (uri == null) {
      return const PhotoSyncResult(PhotoSync.invalid);
    }
    final cached = loadCached(url);
    final http.Response response;
    try {
      response = await _client
          .get(uri, headers: _conditional(cached))
          .timeout(PhotoDefaults.manifestTimeout);
    } on Exception {
      return PhotoSyncResult(PhotoSync.failed, cached);
    }
    if (response.statusCode == _httpNotModified && cached != null) {
      return PhotoSyncResult(PhotoSync.unchanged, cached);
    }
    if (response.statusCode != _httpOk) {
      return PhotoSyncResult(PhotoSync.failed, cached);
    }
    return _accept(uri, response, cached);
  }

  Future<PhotoSyncResult> _accept(
    Uri uri,
    http.Response response,
    PhotoManifest? cached,
  ) async {
    final String body;
    try {
      body = utf8.decode(response.bodyBytes);
    } on FormatException {
      return PhotoSyncResult(PhotoSync.invalid, cached);
    }
    final manifest = PhotoManifest.tryParse(body, uri);
    if (manifest == null) {
      return PhotoSyncResult(PhotoSync.invalid, cached);
    }
    final etag = response.headers[_Header.etag] ?? '';
    final same = cached != null && body == _prefs.getString(_PrefKey.body);
    await _prefs.setString(_PrefKey.etag, etag);
    if (same) {
      return PhotoSyncResult(PhotoSync.unchanged, cached);
    }
    await _prefs.setString(_PrefKey.body, body);
    await _prefs.setString(_PrefKey.url, uri.toString());
    return PhotoSyncResult(PhotoSync.updated, manifest);
  }

  Map<String, String> _conditional(PhotoManifest? cached) {
    final etag = _prefs.getString(_PrefKey.etag) ?? '';
    if (cached == null || etag.isEmpty) {
      return const {};
    }
    return {_Header.ifNoneMatch: etag};
  }
}
