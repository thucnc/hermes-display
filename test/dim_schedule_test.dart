import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_display/core/constants/app_constants.dart';
import 'package:hermes_display/core/dimming/dim_schedule.dart';

void main() {
  DateTime at(int hour, [int minute = 0]) =>
      DateTime(2026, 10, 1, hour, minute);

  const night = DimSettings(
    enabled: true,
    startHour: 23,
    endHour: 6,
    level: 0.05,
  );

  test('defaults: on, 23:00-06:00, 5%', () {
    expect(DimSettings.defaults.enabled, isTrue);
    expect(DimSettings.defaults.startHour, DimDefaults.startHour);
    expect(DimSettings.defaults.endHour, DimDefaults.endHour);
    expect(DimSettings.defaults.level, DimDefaults.level);
    expect(DimDefaults.startHour, 23);
    expect(DimDefaults.endHour, 6);
    expect(DimDefaults.level, 0.05);
  });

  test('window crossing midnight', () {
    expect(dimTarget(at(22, 59), night), BrightnessTarget.system);
    expect(dimTarget(at(23), night), const BrightnessTarget.dim(0.05));
    expect(dimTarget(at(0, 30), night), const BrightnessTarget.dim(0.05));
    expect(dimTarget(at(5, 59), night), const BrightnessTarget.dim(0.05));
    expect(dimTarget(at(6), night), BrightnessTarget.system);
    expect(dimTarget(at(12), night), BrightnessTarget.system);
  });

  test('same-day window', () {
    final day = night.copyWith(startHour: 13, endHour: 15);
    expect(dimTarget(at(12, 59), day), BrightnessTarget.system);
    expect(dimTarget(at(13), day).isDim, isTrue);
    expect(dimTarget(at(14, 59), day).isDim, isTrue);
    expect(dimTarget(at(15), day), BrightnessTarget.system);
  });

  test('start == end is an empty window', () {
    final empty = night.copyWith(startHour: 4, endHour: 4);
    for (var hour = 0; hour < Duration.hoursPerDay; hour++) {
      expect(dimTarget(at(hour), empty), BrightnessTarget.system);
    }
  });

  test('disabled never dims', () {
    final off = night.copyWith(enabled: false);
    expect(dimTarget(at(0), off), BrightnessTarget.system);
  });

  test('invalid hours never dim', () {
    expect(dimTarget(at(0), night.copyWith(startHour: -1)).isDim, isFalse);
    expect(dimTarget(at(0), night.copyWith(endHour: 24)).isDim, isFalse);
  });

  test('normalized clamps hours and level', () {
    final raw = night.copyWith(startHour: 30, endHour: -2, level: 0);
    final value = raw.normalized();
    expect(value.startHour, DimLimits.maxHour);
    expect(value.endHour, DimLimits.minHour);
    expect(value.level, DimLimits.minLevel);
    expect(night.copyWith(level: 2).normalized().level, DimLimits.maxLevel);
  });

  test('uses the injected local time only', () {
    final utcMidnight = DateTime.utc(2026, 10, 1, 0);
    expect(dimTarget(utcMidnight, night).isDim, isTrue);
  });
}
