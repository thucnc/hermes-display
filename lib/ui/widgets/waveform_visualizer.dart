import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Animated bar waveform. Amplitude follows [level] (0..1) with a floor so
/// the visual keeps breathing even when the bridge sends no levels.
class WaveformVisualizer extends StatefulWidget {
  const WaveformVisualizer({
    super.key,
    required this.level,
    required this.color,
    this.height = _defaultHeight,
    this.barCount = _defaultBars,
  });

  final ValueListenable<double> level;
  final Color color;
  final double height;
  final int barCount;

  static const double _defaultHeight = 96;
  static const int _defaultBars = 28;

  @override
  State<WaveformVisualizer> createState() => _WaveformVisualizerState();
}

class _WaveformVisualizerState extends State<WaveformVisualizer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: Motion.waveCycle,
  )..repeat();

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: CustomPaint(
        painter: _WavePainter(
          clock: _clock,
          level: widget.level,
          color: widget.color,
          barCount: widget.barCount,
        ),
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter({
    required this.clock,
    required this.level,
    required this.color,
    required this.barCount,
  }) : super(repaint: Listenable.merge([clock, level]));

  final Animation<double> clock;
  final ValueListenable<double> level;
  final Color color;
  final int barCount;

  static const double _gapRatio = 0.45;
  static const double _phaseStep = 0.55;
  static const double _ambientFloor = 0.25;
  static const double _minBarRatio = 0.08;
  static const double _tipAlpha = 0.35;

  @override
  void paint(Canvas canvas, Size size) {
    if (barCount <= 1) {
      return;
    }
    final slot = size.width / barCount;
    final barWidth = slot * (1 - _gapRatio);
    final energy = _ambientFloor + (1 - _ambientFloor) * level.value;
    final t = clock.value * 2 * pi;
    final centerY = size.height / 2;
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          color.withValues(alpha: _tipAlpha),
          color,
          color.withValues(alpha: _tipAlpha),
        ],
      ).createShader(Offset.zero & size);
    for (var i = 0; i < barCount; i++) {
      final envelope = sin(pi * i / (barCount - 1));
      final wave = (sin(t + i * _phaseStep) + sin(t * 2 - i)).abs() / 2;
      final ratio = max(_minBarRatio, envelope * energy * wave);
      final barHeight = size.height * ratio;
      final rect = Rect.fromCenter(
        center: Offset(slot * i + slot / 2, centerY),
        width: barWidth,
        height: barHeight,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(barWidth / 2)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) {
    return old.color != color || old.barCount != barCount;
  }
}
