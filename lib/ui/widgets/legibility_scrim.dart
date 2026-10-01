import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

enum ScrimLevel { ambient, focused }

/// Gradient veil over photos so white type stays readable on any image.
class LegibilityScrim extends StatelessWidget {
  const LegibilityScrim({super.key, required this.level});

  final ScrimLevel level;

  static const double _topAlpha = 0.45;
  static const double _bottomAlpha = 0.8;
  static const double _focusAlpha = 0.5;
  static const List<double> _stops = [0, 0.3, 0.55, 1];

  @override
  Widget build(BuildContext context) {
    final focusAlpha = level == ScrimLevel.focused ? _focusAlpha : 0.0;
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: _stops,
                colors: [
                  AppPalette.scrim.withValues(alpha: _topAlpha),
                  AppPalette.scrim.withValues(alpha: 0),
                  AppPalette.scrim.withValues(alpha: 0),
                  AppPalette.scrim.withValues(alpha: _bottomAlpha),
                ],
              ),
            ),
          ),
          AnimatedContainer(
            duration: Motion.overlay,
            color: AppPalette.scrim.withValues(alpha: focusAlpha),
          ),
        ],
      ),
    );
  }
}
