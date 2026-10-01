import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Frosted panel used by every floating control for a consistent look.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.radius = Radii.card,
    this.padding = const EdgeInsets.all(Spacing.md),
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(radius);
    return ClipRRect(
      borderRadius: shape,
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: Glass.blurSigma,
          sigmaY: Glass.blurSigma,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppPalette.glass,
            borderRadius: shape,
            border: Border.all(
              color: AppPalette.glassBorder,
              width: Glass.borderWidth,
            ),
          ),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}
