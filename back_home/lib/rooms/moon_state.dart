import 'dart:math' as math;

part 'lunar_eclipses.dart';

enum MoonPhase {
  newMoon,
  waxingCrescent,
  firstQuarter,
  waxingGibbous,
  fullMoon,
  waningGibbous,
  lastQuarter,
  waningCrescent,
}

enum LunarEclipse { none, penumbral, partial, total }

/// Progress runs from new (0), through full (.5), back to new (1).
class MoonState {
  const MoonState({
    required this.progress,
    this.southernHemisphere = false,
    this.eclipse = LunarEclipse.none,
    this.eclipseCoverage = 0,
  });
  final double progress;
  final bool southernHemisphere;
  final LunarEclipse eclipse;
  final double eclipseCoverage;
  double get illuminated => (1 - math.cos(progress * 2 * math.pi)) / 2;
  MoonPhase get phase => MoonPhase.values[((progress * 8 + .5).floor()) % 8];
  String get label => switch (phase) {
    MoonPhase.newMoon => 'New moon',
    MoonPhase.waxingCrescent => 'Waxing crescent',
    MoonPhase.firstQuarter => 'First quarter',
    MoonPhase.waxingGibbous => 'Waxing gibbous',
    MoonPhase.fullMoon => 'Full moon',
    MoonPhase.waningGibbous => 'Waning gibbous',
    MoonPhase.lastQuarter => 'Last quarter',
    MoonPhase.waningCrescent => 'Waning crescent',
  };

  /// Mean synodic cycle anchored to the 2000-01-06 18:14 UTC new moon.
  /// Calendar months must not restart the cycle on their first day.
  static MoonState estimate(
    DateTime time, {
    double? latitude,
    double? longitude,
    double? progress,
  }) {
    final days =
        time
            .toUtc()
            .difference(DateTime.utc(2000, 1, 6, 18, 14))
            .inMilliseconds /
        Duration.millisecondsPerDay;
    final cycle = progress ?? ((days / 29.530588853) % 1 + 1) % 1;
    var eclipse = LunarEclipse.none;
    var coverage = 0.0;
    if (latitude != null &&
        longitude != null &&
        moonAltitude(time, latitude, longitude) > 0) {
      for (final event in lunarEclipses) {
        final minutes =
            time
                .toUtc()
                .difference(
                  DateTime.fromMillisecondsSinceEpoch(
                    event.maximumUtcMs,
                    isUtc: true,
                  ),
                )
                .inMilliseconds
                .abs() /
            60000;
        if (minutes >= event.penumbralMinutes / 2) continue;
        eclipse = LunarEclipse.penumbral;
        coverage = 1 - minutes / (event.penumbralMinutes / 2);
        if (event.partialMinutes > 0 && minutes < event.partialMinutes / 2) {
          eclipse = LunarEclipse.partial;
          coverage =
              (event.umbralMagnitude *
                      math.sqrt(
                        1 - math.pow(minutes / (event.partialMinutes / 2), 2),
                      ))
                  .clamp(0.0, 1.0);
        }
        if (event.totalMinutes > 0 && minutes < event.totalMinutes / 2) {
          eclipse = LunarEclipse.total;
          coverage = 1;
        }
        break;
      }
    }
    return MoonState(
      progress: cycle,
      southernHemisphere: (latitude ?? 0) < 0,
      eclipse: eclipse,
      eclipseCoverage: coverage,
    );
  }
}

class LunarEclipseEvent {
  const LunarEclipseEvent(
    this.maximumUtcMs,
    this.penumbralMinutes,
    this.partialMinutes,
    this.totalMinutes,
    this.umbralMagnitude,
  );
  final int maximumUtcMs;
  final double penumbralMinutes, partialMinutes, totalMinutes, umbralMagnitude;
}

/// Low-precision lunar equatorial coordinates for horizon visibility, in radians.
/// Orbital longitude/latitude terms follow the standard first-order lunar model.
double moonAltitude(DateTime time, double latitude, double longitude) {
  const rad = math.pi / 180;
  final days =
      time.toUtc().millisecondsSinceEpoch / Duration.millisecondsPerDay +
      2440587.5 -
      2451545;
  final meanLongitude = (218.316 + 13.176396 * days) * rad;
  final anomaly = (134.963 + 13.064993 * days) * rad;
  final distance = (93.272 + 13.229350 * days) * rad;
  final lon = meanLongitude + 6.289 * rad * math.sin(anomaly);
  final lat = 5.128 * rad * math.sin(distance);
  const obliquity = 23.4397 * rad;
  final rightAscension = math.atan2(
    math.sin(lon) * math.cos(obliquity) - math.tan(lat) * math.sin(obliquity),
    math.cos(lon),
  );
  final declination = math.asin(
    math.sin(lat) * math.cos(obliquity) +
        math.cos(lat) * math.sin(obliquity) * math.sin(lon),
  );
  final hourAngle =
      (280.16 + 360.9856235 * days + longitude) * rad - rightAscension;
  final phi = latitude * rad;
  return math.asin(
    math.sin(phi) * math.sin(declination) +
        math.cos(phi) * math.cos(declination) * math.cos(hourAngle),
  );
}
