import 'dart:async';

import 'package:flutter/material.dart';

import '../strings.dart';
import '../theme/app_theme.dart';

class AmbientClock extends StatefulWidget {
  const AmbientClock({super.key, required this.timeSize});

  final double timeSize;

  @override
  State<AmbientClock> createState() => _AmbientClockState();
}

class _AmbientClockState extends State<AmbientClock> {
  static const double _dateRatio = 0.22;
  static const double _timeLetterSpacing = -4;
  static const double _timeHeight = 0.95;
  static const int _padWidth = 2;
  static const String _padChar = '0';

  late DateTime _now = DateTime.now();
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(Motion.clockTick, (_) => _tick());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _tick() {
    final now = DateTime.now();
    if (now.minute == _now.minute && now.day == _now.day) {
      return;
    }
    setState(() => _now = now);
  }

  String _pad(int value) => value.toString().padLeft(_padWidth, _padChar);

  String get _time => '${_pad(_now.hour)}:${_pad(_now.minute)}';

  String get _date {
    final weekday = AppStrings.weekdays[_now.weekday - 1];
    return '$weekday, ${_now.day} ${AppStrings.month} ${_now.month}';
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.timeSize;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _time,
          style: TextStyle(
            fontSize: size,
            fontWeight: FontWeight.w200,
            height: _timeHeight,
            letterSpacing: _timeLetterSpacing,
            color: AppPalette.text,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: Spacing.sm),
        Text(
          _date,
          style: TextStyle(
            fontSize: size * _dateRatio,
            fontWeight: FontWeight.w500,
            color: AppPalette.textMuted,
          ),
        ),
      ],
    );
  }
}
