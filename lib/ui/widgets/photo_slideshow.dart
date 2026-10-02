import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/photos/photo_frame.dart';
import '../theme/app_theme.dart';

abstract final class SlideDeck {
  /// Offline fallback: shown while loading or when a photo fails.
  static const List<List<Color>> fallbacks = [
    [Color(0xFF1B2A4A), Color(0xFF3B1F4A), Color(0xFF0B0D17)],
    [Color(0xFF0F3B3A), Color(0xFF1D2B53), Color(0xFF07080C)],
    [Color(0xFF4A2A1B), Color(0xFF2B1D3F), Color(0xFF0B0A12)],
  ];

  static const double kenBurnsScale = 1.08;
}

/// Full-screen cross-fading photos; [frame] decides what is shown.
class PhotoSlideshow extends StatefulWidget {
  const PhotoSlideshow({
    super.key,
    required this.interval,
    required this.frame,
  });

  final Duration interval;
  final PhotoFrame frame;

  @override
  State<PhotoSlideshow> createState() => _PhotoSlideshowState();
}

class _PhotoSlideshowState extends State<PhotoSlideshow> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _restart();
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
    _timer = Timer.periodic(widget.interval, (_) => widget.frame.advance());
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.frame,
      builder: (context, _) {
        final slide = widget.frame.slide;
        final fallbacks = SlideDeck.fallbacks;
        return AnimatedSwitcher(
          duration: Motion.crossFade,
          switchInCurve: Curves.easeInOut,
          switchOutCurve: Curves.easeInOut,
          layoutBuilder: (current, previous) =>
              Stack(fit: StackFit.expand, children: [...previous, ?current]),
          child: _Slide(
            key: ValueKey<int>(slide.serial),
            image: _imageFor(slide),
            colors: fallbacks[slide.serial % fallbacks.length],
            lifetime: widget.interval + Motion.crossFade,
          ),
        );
      },
    );
  }

  static ImageProvider? _imageFor(FrameSlide slide) {
    final file = slide.file;
    if (file != null) {
      return FileImage(file);
    }
    final url = slide.url;
    return url == null ? null : NetworkImage(url.toString());
  }
}

class _Slide extends StatelessWidget {
  const _Slide({
    super.key,
    required this.image,
    required this.colors,
    required this.lifetime,
  });

  final ImageProvider? image;
  final List<Color> colors;
  final Duration lifetime;

  @override
  Widget build(BuildContext context) {
    final fallback = _GradientSlide(colors: colors);
    final source = image;
    final Widget content = source == null
        ? fallback
        : Image(
            image: source,
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
