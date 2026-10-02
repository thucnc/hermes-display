import 'package:flutter/material.dart';

import '../../core/photos/photo_frame.dart';
import '../strings.dart';
import '../theme/app_theme.dart';
import 'glass_surface.dart';

/// Caption of the family photo on screen; "Ngày này năm xưa" photos get
/// a highlighted badge.
class PhotoCaption extends StatelessWidget {
  const PhotoCaption({super.key, required this.frame});

  final PhotoFrame frame;

  static const double _maxWidth = 560;
  static const double _iconSize = 18;
  static const double _textSize = 15;
  static const double _badgeSize = 13;
  static const int _maxLines = 2;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: frame,
      builder: (context, _) {
        final photo = frame.current;
        final memory = frame.slide.memory;
        final text = memory ?? photo?.caption ?? '';
        return AnimatedSwitcher(
          duration: Motion.overlay,
          child: text.isEmpty
              ? const SizedBox.shrink()
              : _chip(text, memory != null, frame.slide.serial),
        );
      },
    );
  }

  Widget _chip(String text, bool memory, int serial) {
    return ConstrainedBox(
      key: ValueKey<int>(serial),
      constraints: const BoxConstraints(maxWidth: _maxWidth),
      child: GlassSurface(
        radius: Radii.pill,
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.md,
          vertical: Spacing.sm,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (memory) ...[
              const Icon(
                Icons.auto_awesome_rounded,
                size: _iconSize,
                color: AppPalette.accentWarm,
              ),
              const SizedBox(width: Spacing.sm),
              const Text(
                AppStrings.onThisDay,
                style: TextStyle(
                  fontSize: _badgeSize,
                  fontWeight: FontWeight.w700,
                  color: AppPalette.accentWarm,
                ),
              ),
              const SizedBox(width: Spacing.sm),
            ],
            Flexible(
              child: Text(
                text,
                maxLines: _maxLines,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: _textSize),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
