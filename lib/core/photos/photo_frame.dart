import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../services/photo_cache.dart';
import '../../services/photo_manifest_service.dart';
import '../constants/app_constants.dart';
import '../members/member_profile.dart';
import 'on_this_day.dart';
import 'photo_context.dart';
import 'photo_manifest.dart';
import 'photo_playlist.dart';

/// What the slideshow shows right now.
class FrameSlide {
  const FrameSlide({
    required this.serial,
    this.photo,
    this.file,
    this.url,
    this.memory,
  });

  static const FrameSlide empty = FrameSlide(serial: 0);

  /// Changes on every advance; drives the cross-fade.
  final int serial;
  final FamilyPhoto? photo;

  /// Cached copy on disk; preferred over the network.
  final File? file;

  /// Set only when there is no disk cache: load straight from the web.
  final Uri? url;

  /// "Ngày này 3 năm trước (2023): …" for on-this-day photos.
  final String? memory;

  FrameSlide withFile(File file) {
    return FrameSlide(
      serial: serial,
      photo: photo,
      file: file,
      url: url,
      memory: memory,
    );
  }
}

/// Slideshow state: family photos from the manifest (placeholder deck
/// otherwise), ordered for today and the active member, cached on disk.
class PhotoFrame extends ChangeNotifier {
  PhotoFrame({
    PhotoManifestService? manifests,
    PhotoCache? cache,
    List<String> deck = const [],
    DateTime Function()? clock,
    Random? random,
  }) : _manifests = manifests,
       _cache = cache,
       _deck = [
         for (var i = 0; i < deck.length; i++)
           FamilyPhoto(id: '$_deckPrefix$i', url: Uri.parse(deck[i])),
       ],
       _clock = clock ?? DateTime.now,
       _random = random ?? Random() {
    _photos = _deck;
  }

  /// Null: no download, the manifest URL is ignored.
  final PhotoManifestService? _manifests;

  /// Null: photos stream from the network every time.
  final PhotoCache? _cache;
  final List<FamilyPhoto> _deck;
  final DateTime Function() _clock;
  final Random _random;
  static const String _deckPrefix = 'deck-';

  late List<FamilyPhoto> _photos;
  bool _family = false;
  String _url = '';
  String _memberId = MemberProfile.defaultId;
  List<FamilyPhoto> _order = const [];
  int _index = -1;
  DateTime? _orderedFor;
  DateTime? _checkedAt;
  FrameSlide _slide = FrameSlide.empty;
  final Map<String, File> _files = {};

  /// Downloads that failed since the last good manifest check; skipped
  /// while any other photo can be shown.
  final Set<String> _failed = {};
  bool _disposed = false;

  FrameSlide get slide => _slide;

  /// True once a family manifest replaced the placeholder deck.
  bool get showsFamily => _family;

  /// The family photo on screen; null for placeholders.
  FamilyPhoto? get current => _family ? _slide.photo : null;

  /// Playlist for the current day and member.
  List<FamilyPhoto> get order => List.unmodifiable(_order);

  /// Cached manifest first so the frame works offline, then a refresh.
  /// An empty [url] goes back to the placeholder deck.
  Future<void> boot(String url) async {
    _url = url.trim();
    _checkedAt = null;
    _apply(_url.isEmpty ? null : _manifests?.loadCached(_url));
    if (_url.isEmpty) {
      return;
    }
    await refresh();
  }

  /// Re-downloads the manifest; a new one reorders from the next slide.
  Future<PhotoSyncResult> refresh() async {
    final manifests = _manifests;
    final url = _url;
    if (manifests == null || url.isEmpty) {
      return const PhotoSyncResult(PhotoSync.failed);
    }
    _checkedAt = _clock();
    final result = await manifests.fetch(url);
    if (_disposed || url != _url) {
      return result;
    }
    final manifest = result.manifest;
    if (result.status == PhotoSync.updated && manifest != null) {
      _apply(manifest);
    }
    if (result.status == PhotoSync.updated ||
        result.status == PhotoSync.unchanged) {
      _failed.clear();
    }
    return result;
  }

  /// Photos featuring [memberId] move up from the next slide on.
  void setMember(String memberId) {
    if (memberId == _memberId) {
      return;
    }
    _memberId = memberId;
    _reorder(_clock());
  }

  /// Next slide; also reorders at midnight and re-checks the manifest.
  void advance() {
    final now = _clock();
    if (!_sameDay(now, _orderedFor)) {
      _failed.clear();
      _reorder(now);
    }
    _maybeRefresh(now);
    if (_order.isEmpty) {
      _show(null);
      return;
    }
    _show(_pick());
  }

  /// Gemini context for the photo on screen; empty for placeholders.
  String describe({String Function(String memberId)? nameOf}) {
    final photo = current;
    if (photo == null) {
      return '';
    }
    return photoContext(photo, _clock(), nameOf: nameOf);
  }

  void _apply(PhotoManifest? manifest) {
    _family = manifest != null;
    _photos = manifest?.photos ?? _deck;
    _reorder(_clock());
    final shown = _slide.photo?.id;
    if (shown == null || !_photos.any((photo) => photo.id == shown)) {
      advance();
    }
  }

  void _reorder(DateTime now) {
    _orderedFor = now;
    _order = buildPlaylist(
      _photos,
      memberId: _memberId,
      today: now,
      random: _random,
    );
    _index = -1;
  }

  void _maybeRefresh(DateTime now) {
    final checkedAt = _checkedAt;
    if (_manifests == null || _url.isEmpty || checkedAt == null) {
      return;
    }
    if (now.difference(checkedAt) < PhotoDefaults.refreshEvery) {
      return;
    }
    unawaited(refresh());
  }

  /// Next index whose download has not failed, never the photo already
  /// on screen when there is a choice.
  int _pick() {
    final count = _order.length;
    final shown = _slide.photo?.id;
    for (var step = 1; step <= count; step++) {
      final index = (_index + step) % count;
      final photo = _order[index];
      if (_failed.contains(photo.id)) {
        continue;
      }
      if (count > 1 && photo.id == shown) {
        continue;
      }
      return index;
    }
    return (_index + 1) % count;
  }

  void _show(int? index) {
    final serial = _slide.serial + 1;
    if (index == null) {
      _slide = FrameSlide(serial: serial);
      _notify();
      return;
    }
    _index = index;
    final photo = _order[index];
    final years = _family ? OnThisDay.of(photo, _clock()) : null;
    _slide = FrameSlide(
      serial: serial,
      photo: photo,
      file: _files[photo.id],
      url: _cache == null ? photo.url : null,
      memory: years == null ? null : OnThisDay.label(photo, years),
    );
    _notify();
    _warm(photo);
    if (_order.length > 1) {
      _warm(_order[(index + 1) % _order.length]);
    }
  }

  void _warm(FamilyPhoto photo) {
    final cache = _cache;
    if (cache == null ||
        _files.containsKey(photo.id) ||
        _failed.contains(photo.id)) {
      return;
    }
    unawaited(cache.fetch(photo.url).then((file) => _onCached(photo, file)));
  }

  void _onCached(FamilyPhoto photo, File? file) {
    if (_disposed) {
      return;
    }
    final onScreen = _slide.photo?.id == photo.id;
    if (file == null) {
      _failed.add(photo.id);
      if (onScreen && _order.any((p) => !_failed.contains(p.id))) {
        advance();
      }
      return;
    }
    _files[photo.id] = file;
    if (!onScreen) {
      return;
    }
    _slide = _slide.withFile(file);
    _notify();
  }

  static bool _sameDay(DateTime a, DateTime? b) {
    return b != null &&
        a.year == b.year &&
        a.month == b.month &&
        a.day == b.day;
  }

  void _notify() {
    if (_disposed) {
      return;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
