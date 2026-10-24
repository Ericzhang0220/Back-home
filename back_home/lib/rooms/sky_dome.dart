import 'package:three_js/three_js.dart' as three;

import 'outdoor_landscape.dart' show srgbToLinear;

/// A closed background around both the room and its outdoor viewpoint.
/// Unlike a flat backdrop, it has no upper or side edges to expose on a turn.
three.Mesh buildRoomSkyDome({
  required int horizon,
  required int zenith,
  required three.Vector3 center,
  int? glow,
  double glowStrength = 0,
}) {
  // Keep the entire dome inside the camera's 80-unit far plane, including
  // when the camera returns to the room centre.
  final geometry = three.SphereGeometry(60, 64, 48);
  final positions = geometry.getAttributeFromString('position');
  final low = three.Color.fromHex32(horizon);
  final high = three.Color.fromHex32(zenith);
  final band = three.Color.fromHex32(glow ?? horizon);
  final colors = <double>[];
  for (var i = 0; i < positions.count; i += 1) {
    final worldY = positions.getY(i)!.toDouble() + center.y;
    // Pure horizon colour at the sea horizon, so the landscape haze (which
    // uses that colour) meets the sky without a seam, deepening overhead.
    final t = ((worldY + 2) / 40).clamp(0.0, 1.0);
    // Dawn/dusk glow fades smoothly up from the horizon instead of sitting
    // in a hard-edged band.
    final g = glowStrength * (1 - (t / 0.32).clamp(0.0, 1.0));
    double channel(double lo, double hi, double glowChannel) {
      final base = lo + (hi - lo) * t;
      return srgbToLinear(base + (glowChannel - base) * g);
    }

    colors.addAll([
      channel(low.red, high.red, band.red),
      channel(low.green, high.green, band.green),
      channel(low.blue, high.blue, band.blue),
    ]);
  }
  geometry.setAttributeFromString(
    'color',
    three.Float32BufferAttribute.fromList(colors, 3),
  );
  return three.Mesh(
      geometry,
      three.MeshBasicMaterial.fromMap({
        'color': 0xFFFFFF,
        'vertexColors': true,
        'side': three.BackSide,
        'depthWrite': false,
      }),
    )
    ..position.setFrom(center)
    ..renderOrder = -100;
}
