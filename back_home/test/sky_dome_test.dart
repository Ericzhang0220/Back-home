import 'dart:math' as math;

import 'package:back_home/rooms/sky_dome.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:three_js/three_js.dart' as three;

void main() {
  test(
    'sky covers every heading and raised viewport corner before far clip',
    () {
      final ledgeEye = three.Vector3(1.7, 2.5, -7.6);
      final dome = buildRoomSkyDome(
        horizon: 0xAABBCC,
        zenith: 0x334455,
        center: three.Vector3(1, 2.32, -9.35),
      );
      addTearDown(dome.dispose);
      dome.updateMatrixWorld(true);

      // Cover both the window ledge and the main room centre. These high
      // rays previously passed above the rectangular backdrop.
      for (final eye in [ledgeEye, three.Vector3(0, 1.9, 0)]) {
        for (var degrees = 0; degrees < 360; degrees += 15) {
          for (final pitch in [-1.5, 0.01, 0.72, 2.5, 20.0]) {
            // Sample inside faces rather than exactly along shared meridians,
            // where Float32 ray/triangle edge comparisons are ambiguous.
            final yaw = (degrees + 0.37) * math.pi / 180;
            final direction = three.Vector3(
              math.sin(yaw),
              pitch,
              -math.cos(yaw),
            )..normalize();
            final ray = three.Raycaster(eye, direction, 0.1, 80);
            expect(
              ray.intersectObject(dome),
              isNotEmpty,
              reason: 'Uncovered sky at $degrees degrees, pitch $pitch',
            );
          }
        }
      }
    },
  );
}
