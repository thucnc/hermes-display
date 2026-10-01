import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Placeholder photo sources until a real album provider lands (KB-006).
abstract final class SlideDeck {
  static const List<String> defaultPhotos = [
    'https://picsum.photos/seed/hermes-1/1920/1280',
    'https://picsum.photos/seed/hermes-2/1920/1280',
    'https://picsum.photos/seed/hermes-3/1920/1280',
    'https://picsum.photos/seed/hermes-4/1920/1280',
    'https://picsum.photos/seed/hermes-5/1920/1280',
    'https://picsum.photos/seed/hermes-6/1920/1280',
  ];

  /// Offline fallback: shown while loading or when a photo fails.
  static const List<List<Color>> fallbacks = [
    [Color(0xFF1B2A4A), Color(0xFF3B1F4A), Color(0xFF0B0D17)],
    [Color(0xFF0F3B3A), Color(0xFF1D2B53), Color(0xFF07080C)],
    [Color(0xFF4A2A1B), Color(0xFF2B1D3F), Color(0xFF0B0A12)],
  ];

  static const double kenBurnsScale = 1.08;
}

class PhotoSlideshow extends StatefulWidget {
  const PhotoSlideshow({
    super.key,
    required this.interval,
    this.photos = SlideDeck.defaultPhotos,
  });

  final Duration interval;
  final List<String> photos;

  @override
  State<PhotoSlideshow> createState() => _PhotoSlideshowState();
}

class _PhotoSlideshowState extends State<PhotoSlideshow> {
  Timer? _timer;
  int _index = 0;

  int get _count {
    if (widget.photos.isEmpty) {
      return SlideDeck.fallbacks.length;
    }
    return widget.photos.length;
  }

  @override
  void initState() {
    super.initState();
    _restart();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _precache(_index);
  }

  @override
  void didUpdateWidget(PhotoSlideshow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.interval == widget.interval) {
      return;
    }
    _restart();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _restart() {
    _timer?.cancel();
    _timer = Timer.periodic(widget.interval, (_) => _advance());
  }

  void _advance() {
    setState(() => _index = (_index + 1) % _count);
    _precache(_index + 1);
  }

  void _precache(int index) {
    if (widget.photos.isEmpty) {
      return;
    }
    final url = widget.photos[index % widget.photos.length];
    precacheImage(NetworkImage(url), context, onError: (_, _) {});
  }

  @override
  Widget build(BuildContext context) {
    final colors = SlideDeck.fallbacks[_index % SlideDeck.fallbacks.length];
    final url = widget.photos.isEmpty ? null : widget.photos[_index];
    return AnimatedSwitcher(
      duration: Motion.crossFade,
      switchInCurve: Curves.easeInOut,
      switchOutCurve: Curves.easeInOut,
      layoutBuilder: (current, previous) =>
          Stack(fit: StackFit.expand, children: [...previous, ?current]),
      child: _Slide(
        key: ValueKey<int>(_index),
        url: url,
        colors: colors,
        lifetime: widget.interval + Motion.crossFade,
      ),
    );
  }
}

class _Slide extends StatelessWidget {
  const _Slide({
    super.key,
    required this.url,
    required this.colors,
    required this.lifetime,
  });

  final String? url;
  final List<Color> colors;
  final Duration lifetime;

  @override
  Widget build(BuildContext context) {
    final fallback = _GradientSlide(colors: colors);
    final source = url;
    final Widget content = source == null
        ? fallback
        : Image.network(
            source,
            fit: BoxFit.cover,
            frameBuilder: (_, child, frame, wasSync) {
              if (frame == null && !wasSync) {
                return fallback;
              }
              return child;
            },
            errorBuilder: (_, _, _) => fallback,
          );
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 1, end: SlideDeck.kenBurnsScale),
      duration: lifetime,
      builder: (_, scale, child) => Transform.scale(scale: scale, child: child),
      child: content,
    );
  }
}

class _GradientSlide extends StatelessWidget {
  const _GradientSlide({required this.colors});

  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
      ),
    );
  }
}
