import '../constants/app_constants.dart';

/// User-facing night dimming window. Hours are local wall-clock, [startHour]
/// inclusive, [endHour] exclusive; a start after end crosses midnight.
class DimSettings {
  const DimSettings({
    required this.enabled,
    required this.startHour,
    required this.endHour,
    required this.level,
  });

  static const DimSettings defaults = DimSettings(
    enabled: DimDefaults.enabled,
    startHour: DimDefaults.startHour,
    endHour: DimDefaults.endHour,
    level: DimDefaults.level,
  );

  final bool enabled;
  final int startHour;
  final int endHour;

  /// Window brightness 0..1 while dimmed.
  final double level;

  DimSettings copyWith({
    bool? enabled,
    int? startHour,
    int? endHour,
    double? level,
  }) {
    return DimSettings(
      enabled: enabled ?? this.enabled,
      startHour: startHour ?? this.startHour,
      endHour: endHour ?? this.endHour,
      level: level ?? this.level,
    );
  }

  DimSettings normalized() {
    return DimSettings(
      enabled: enabled,
      startHour: startHour.clamp(DimLimits.minHour, DimLimits.maxHour),
      endHour: endHour.clamp(DimLimits.minHour, DimLimits.maxHour),
      level: level.clamp(DimLimits.minLevel, DimLimits.maxLevel),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is DimSettings &&
        other.enabled == enabled &&
        other.startHour == startHour &&
        other.endHour == endHour &&
        other.level == level;
  }

  @override
  int get hashCode => Object.hash(enabled, startHour, endHour, level);
}

/// Window brightness to request: a fixed level, or the system's own
/// (automatic or user-set) brightness.
final class BrightnessTarget {
  const BrightnessTarget.dim(double this.level);

  const BrightnessTarget._system() : level = null;

  static const BrightnessTarget system = BrightnessTarget._system();

  /// Null means "no override".
  final double? level;

  bool get isDim => level != null;

  @override
  bool operator ==(Object other) {
    return other is BrightnessTarget && other.level == level;
  }

  @override
  int get hashCode => level.hashCode;

  @override
  String toString() => isDim ? 'dim($level)' : 'system';
}

bool _validHour(int hour) {
  return hour >= DimLimits.minHour && hour <= DimLimits.maxHour;
}

/// True when [now]'s hour falls inside the window. Invalid hours or an
/// empty window (start == end) never match.
bool inDimWindow(DateTime now, DimSettings settings) {
  final start = settings.startHour;
  final end = settings.endHour;
  if (!settings.enabled || !_validHour(start) || !_validHour(end)) {
    return false;
  }
  if (start == end) {
    return false;
  }
  final hour = now.hour;
  if (start < end) {
    return hour >= start && hour < end;
  }
  return hour >= start || hour < end;
}

BrightnessTarget dimTarget(DateTime now, DimSettings settings) {
  if (!inDimWindow(now, settings)) {
    return BrightnessTarget.system;
  }
  return BrightnessTarget.dim(settings.level);
}
