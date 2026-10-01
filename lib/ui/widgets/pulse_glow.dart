import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Breathing orb shown while the assistant is thinking.
class PulseGlow extends StatefulWidget {
  const PulseGlow({super.key, required this.color, this.size = _defaultSize});

  final Color color;
  final double size;

  static const double _defaultSize = 160;

  @override
  State<PulseGlow> createState() => _PulseGlowState();
}

class _PulseGlowState extends State<PulseGlow>
    with SingleTickerProviderStateMixin {
  static const double _minScale = 0.82;
  static const double _maxScale = 1.12;
  static const double _coreRatio = 0.38;
  static const double _haloAlpha = 0.55;
  static const double _coreBlur = 32;

  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: Motion.pulseCycle,
  )..repeat(reverse: true);

  late final Animation<double> _scale = Tween<double>(
    begin: _minScale,
    end: _maxScale,
  ).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut));

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final color = widget.color;
    return SizedBox.square(
      dimension: size,
      child: ScaleTransition(
        scale: _scale,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                color.withValues(alpha: _haloAlpha),
                color.withValues(alpha: 0),
              ],
            ),
          ),
          child: Center(
            child: Container(
              width: size * _coreRatio,
              height: size * _coreRatio,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color,
                boxShadow: [BoxShadow(color: color, blurRadius: _coreBlur)],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
