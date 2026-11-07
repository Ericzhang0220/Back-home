import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:back_home/rooms/moon_state.dart';
import 'package:back_home/services/moon_service.dart';
import 'package:back_home/widgets/moon_disc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets('ordinary crescent leaves its unlit side transparent', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      const MoonDiscPainter(
        MoonState(progress: .95),
      ).paint(canvas, const ui.Size(100, 100));
      final picture = recorder.endRecording();
      final image = await picture.toImage(100, 100);
      final pixels = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      expect(pixels.getUint8((50 * 100 + 80) * 4 + 3), lessThan(5));
      expect(pixels.getUint8((50 * 100 + 1) * 4 + 3), greaterThan(200));
      image.dispose();
      picture.dispose();
    });
  });

  test(
    'all eight phases and continuous quarter illumination render correctly',
    () {
      for (var phase = 0; phase < 8; phase++) {
        final progress = phase / 8;
        final moon = MoonState(progress: progress);
        expect(moon.phase, MoonPhase.values[phase]);
        final path = MoonDiscPainter.illuminatedPath(1, progress);
        var lit = 0, disc = 0;
        for (var x = -99; x < 100; x++) {
          for (var y = -99; y < 100; y++) {
            final point = Offset(x / 100, y / 100);
            if (point.distance <= 1) {
              disc++;
              if (path.contains(point)) lit++;
            }
          }
        }
        expect(lit / disc, closeTo(moon.illuminated, .01));
      }
      final quarterLit = math.acos(.5) / (2 * math.pi);
      expect(MoonState(progress: quarterLit).illuminated, closeTo(.25, .0001));
      expect(
        MoonDiscPainter.illuminatedPath(1, .25).contains(const Offset(.5, 0)),
        isTrue,
      );
      expect(
        MoonDiscPainter.illuminatedPath(1, .75).contains(const Offset(-.5, 0)),
        isTrue,
      );
    },
  );

  test(
    'offline moon progresses across calendar months and timezone boundaries',
    () {
      final anchor = DateTime.utc(2000, 1, 6, 18, 14);
      expect(MoonState.estimate(anchor).progress, closeTo(0, .00001));
      expect(
        MoonState.estimate(anchor.add(const Duration(hours: 354))).illuminated,
        greaterThan(.999),
      );
      final before = MoonState.estimate(DateTime.utc(2026, 10, 31, 23, 59));
      final after = MoonState.estimate(DateTime.utc(2026, 11, 1));
      expect((after.progress - before.progress).abs(), lessThan(.001));
    },
  );

  test(
    'NASA eclipse passes penumbral, partial and total only above local horizon',
    () {
      final peak = DateTime.utc(2026, 3, 3, 11, 33, 37);
      MoonState local(DateTime time) =>
          MoonState.estimate(time, latitude: 34.05, longitude: -118.24);
      expect(local(peak).eclipse, LunarEclipse.total);
      expect(
        local(peak.subtract(const Duration(minutes: 60))).eclipse,
        LunarEclipse.partial,
      );
      expect(
        local(peak.subtract(const Duration(minutes: 130))).eclipse,
        LunarEclipse.penumbral,
      );
      expect(
        local(peak.subtract(const Duration(hours: 4))).eclipse,
        LunarEclipse.none,
      );
      expect(MoonState.estimate(peak).eclipse, LunarEclipse.none);
      expect(
        MoonState.estimate(peak, latitude: -34.05, longitude: 61.76).eclipse,
        LunarEclipse.none,
      );
    },
  );

  test(
    'no location uses offline cycle without sending network requests',
    () async {
      var calls = 0;
      final service = MoonService(
        location: () async => null,
        client: MockClient((_) async {
          calls++;
          return http.Response('', 500);
        }),
      );
      final time = DateTime.utc(2026, 11, 6);
      expect(
        (await service.current(time: time)).progress,
        MoonState.estimate(time).progress,
      );
      expect(calls, 0);
    },
  );

  test(
    'USNO local illumination is cached per day and network failure falls back',
    () async {
      var calls = 0;
      final position = Position(
        latitude: -33.9,
        longitude: 151.2,
        timestamp: DateTime.utc(2026),
        accuracy: 100,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      );
      final service = MoonService(
        location: () async => position,
        client: MockClient((uri) async {
          calls++;
          expect(uri.url.queryParameters['coords'], '-33.90,151.20');
          return http.Response(
            jsonEncode({
              'properties': {
                'data': {
                  'year': 2026,
                  'month': 11,
                  'day': 6,
                  'curphase': 'Waning Crescent',
                  'fracillum': '6%',
                },
              },
            }),
            200,
          );
        }),
      );
      final first = await service.current(time: DateTime.utc(2026, 11, 6, 12));
      expect(first.illuminated, closeTo(.06, .00001));
      expect(first.southernHemisphere, isTrue);
      await service.current(time: DateTime.utc(2026, 11, 6, 18));
      expect(calls, 1);
      final next = await service.current(time: DateTime.utc(2026, 11, 7, 12));
      expect(calls, 2);
      expect(
        next.progress,
        MoonState.estimate(DateTime.utc(2026, 11, 7, 12)).progress,
      );
      expect(
        () => MoonService.progressFromUsno({
          'curphase': 'Full Moon',
          'fracillum': 'NaN%',
        }),
        throwsFormatException,
      );
    },
  );
}
