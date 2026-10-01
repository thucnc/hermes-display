import 'dart:math';

import '../core/constants/app_constants.dart';

/// Exponential backoff with symmetric jitter, capped at [max].
class ReconnectBackoff {
  ReconnectBackoff({
    this.base = NetworkTiming.backoffBase,
    this.max = NetworkTiming.backoffMax,
    this.factor = NetworkTiming.backoffFactor,
    this.jitter = NetworkTiming.backoffJitter,
    Random? random,
  }) : _random = random ?? Random();

  final Duration base;
  final Duration max;
  final double factor;
  final double jitter;
  final Random _random;

  Duration delayFor(int attempt) {
    final exponent = attempt.clamp(0, NetworkTiming.backoffMaxExponent);
    final raw = base.inMilliseconds * pow(factor, exponent);
    final capped = min(raw.toDouble(), max.inMilliseconds.toDouble());
    final spread = capped * jitter * (_random.nextDouble() * 2 - 1);
    final millis = (capped + spread).round().clamp(0, max.inMilliseconds);
    return Duration(milliseconds: millis);
  }
}
