import 'package:flutter/material.dart';

import '../strings.dart';
import '../theme/app_theme.dart';
import 'glass_surface.dart';

/// Assistant reply bubble. Slides up on first appearance and grows smoothly
/// as streamed TTS text extends.
class SubtitleCard extends StatelessWidget {
  const SubtitleCard({super.key, required this.text, this.footer});

  final String text;
  final Widget? footer;

  static const double _maxWidth = 760;
  static const double _labelSize = 13;
  static const double _labelSpacing = 1.6;
  static const double _bodySize = 26;
  static const double _bodyHeight = 1.35;
  static const double _slideOffset = 24;

  @override
  Widget build(BuildContext context) {
    final extra = footer;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Motion.entrance,
      curve: Motion.emphasized,
      builder: (_, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, (1 - t) * _slideOffset),
          child: child,
        ),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _maxWidth),
        child: GlassSurface(
          padding: const EdgeInsets.all(Spacing.lg),
          child: AnimatedSize(
            duration: Motion.quick,
            alignment: Alignment.topCenter,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  AppStrings.assistantName.toUpperCase(),
                  style: const TextStyle(
                    fontSize: _labelSize,
                    letterSpacing: _labelSpacing,
                    fontWeight: FontWeight.w700,
                    color: AppPalette.accentWarm,
                  ),
                ),
                const SizedBox(height: Spacing.sm),
                Text(
                  text,
                  style: const TextStyle(
                    fontSize: _bodySize,
                    height: _bodyHeight,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                if (extra != null) ...[
                  const SizedBox(height: Spacing.md),
                  extra,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
