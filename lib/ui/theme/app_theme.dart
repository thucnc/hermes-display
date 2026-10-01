import 'package:flutter/material.dart';

abstract final class AppPalette {
  static const Color ink = Color(0xFF07080C);
  static const Color text = Color(0xFFF5F2EA);
  static const Color textMuted = Color(0xB3F5F2EA);
  static const Color glass = Color(0x1FFFFFFF);
  static const Color glassBorder = Color(0x33FFFFFF);
  static const Color accent = Color(0xFF8AB4FF);
  static const Color accentWarm = Color(0xFFFFB37A);
  static const Color online = Color(0xFF5EE6A8);
  static const Color pending = Color(0xFFFFC857);
  static const Color offline = Color(0xFFFF6B6B);
  static const Color scrim = Color(0xFF000000);
}

abstract final class Motion {
  static const Duration crossFade = Duration(milliseconds: 1800);
  static const Duration overlay = Duration(milliseconds: 450);
  static const Duration entrance = Duration(milliseconds: 600);
  static const Duration quick = Duration(milliseconds: 250);
  static const Duration waveCycle = Duration(milliseconds: 1400);
  static const Duration pulseCycle = Duration(milliseconds: 1600);
  static const Duration clockTick = Duration(seconds: 1);
  static const Curve emphasized = Curves.easeOutCubic;
}

abstract final class Spacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 40;
}

abstract final class Radii {
  static const double card = 28;
  static const double pill = 999;
}

abstract final class Glass {
  static const double blurSigma = 24;
  static const double borderWidth = 1;
}

abstract final class AppTheme {
  static ThemeData dark() {
    final base = ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppPalette.accent,
        brightness: Brightness.dark,
      ),
    );
    return base.copyWith(
      scaffoldBackgroundColor: AppPalette.ink,
      textTheme: base.textTheme.apply(
        bodyColor: AppPalette.text,
        displayColor: AppPalette.text,
      ),
    );
  }
}
