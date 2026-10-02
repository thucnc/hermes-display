import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants/app_constants.dart';
import '../core/pack/sen_pack.dart';
import 'sen_memory_service.dart';

enum PackSync {
  /// New content downloaded, applied and cached.
  updated,

  /// The host has nothing newer than the cache.
  unchanged,

  /// Bad URL, or the body is not a usable pack.
  invalid,

  /// Network, HTTP or database error; the cache is untouched.
  failed,
}

class PackSyncResult {
  const PackSyncResult(this.status, [this.pack]);

  final PackSync status;

  /// The pack now in effect; null when none was ever loaded.
  final SenPack? pack;
}

abstract final class _PrefKey {
  static const String body = 'sen_pack_json';
  static const String etag = 'sen_pack_etag';
}

abstract final class _Header {
  static const String etag = 'etag';
  static const String ifNoneMatch = 'if-none-match';
}

/// Downloads `sen-pack.json` from any URL, applies its members to the
/// memory database and keeps the last good copy for offline boots.
class SenPackService {
  SenPackService({
    required SharedPreferences prefs,
    SenMemoryService? memory,
    http.Client? client,
  }) : _prefs = prefs,
       _memory = memory,
       _client = client ?? http.Client();

  final SharedPreferences _prefs;

  /// Null: members are used by the app but not written to memory.
  final SenMemoryService? _memory;
  final http.Client _client;
  static const int _httpOk = 200;
  static const int _httpNotModified = 304;

  /// Last cached pack, applied to memory again; null when none or the
  /// cache is unreadable.
  Future<SenPack?> loadCached() async {
    final pack = _cached();
    if (pack == null) {
      return null;
    }
    try {
      await _memory?.applyMembers(pack.members);
    } on Exception {
      // Memory is a bonus; the pack still drives members and skills.
    }
    return pack;
  }

  Future<PackSyncResult> fetchAndApply(String url) async {
    final uri = parseUrl(url);
    final cached = _cached();
    if (uri == null) {
      return PackSyncResult(PackSync.invalid, cached);
    }
    final http.Response response;
    try {
      response = await _client
          .get(uri, headers: _conditional(cached))
          .timeout(SenPackDefaults.timeout);
    } on Exception {
      // ClientException, TimeoutException and TLS errors alike.
      return PackSyncResult(PackSync.failed, cached);
    }
    if (response.statusCode == _httpNotModified && cached != null) {
      return PackSyncResult(PackSync.unchanged, cached);
    }
    if (response.statusCode != _httpOk) {
      return PackSyncResult(PackSync.failed, cached);
    }
    return _accept(response, cached);
  }

  /// Absolute http(s) URL with a host; null otherwise.
  static Uri? parseUrl(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || uri.host.isEmpty) {
      return null;
    }
    return SenPackDefaults.schemes.contains(uri.scheme) ? uri : null;
  }

  Future<PackSyncResult> _accept(
    http.Response response,
    SenPack? cached,
  ) async {
    final String body;
    try {
      body = utf8.decode(response.bodyBytes);
    } on FormatException {
      return PackSyncResult(PackSync.invalid, cached);
    }
    final pack = SenPack.tryParse(body);
    if (pack == null) {
      return PackSyncResult(PackSync.invalid, cached);
    }
    final etag = response.headers[_Header.etag] ?? '';
    if (cached != null && _same(pack, cached, body)) {
      await _prefs.setString(_PrefKey.etag, etag);
      return PackSyncResult(PackSync.unchanged, cached);
    }
    try {
      await _memory?.applyMembers(pack.members);
    } on Exception {
      return PackSyncResult(PackSync.failed, cached);
    }
    await _prefs.setString(_PrefKey.body, body);
    await _prefs.setString(_PrefKey.etag, etag);
    return PackSyncResult(PackSync.updated, pack);
  }

  bool _same(SenPack pack, SenPack cached, String body) {
    return pack.sameContent(cached) || body == _prefs.getString(_PrefKey.body);
  }

  Map<String, String> _conditional(SenPack? cached) {
    final etag = _prefs.getString(_PrefKey.etag) ?? '';
    if (cached == null || etag.isEmpty) {
      return const {};
    }
    return {_Header.ifNoneMatch: etag};
  }

  SenPack? _cached() {
    final body = _prefs.getString(_PrefKey.body);
    return body == null ? null : SenPack.tryParse(body);
  }
}
