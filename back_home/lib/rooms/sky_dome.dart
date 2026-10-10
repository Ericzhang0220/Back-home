import 'package:three_js/three_js.dart' as three;

/// A closed background around both the room and its outdoor viewpoint.
/// Unlike a flat backdrop, it has no upper or side edges to expose on a turn.
three.Mesh buildRoomSkyDome({
  required int horizon,
  required int zenith,
  required three.Vector3 center,
}) {
  // Keep the entire dome inside the camera's 80-unit far plane, including
  // when the camera returns to the room centre.
  final geometry = three.SphereGeometry(60, 64, 48);
  final positions = geometry.getAttributeFromString('position');
  final low = three.Color.fromHex32(horizon);
  final high = three.Color.fromHex32(zenith);
  final colors = <double>[];
  for (var i = 0; i < positions.count; i += 1) {
    final worldY = positions.getY(i)!.toDouble() + center.y;
    // Retain the existing landscape's height-based atmospheric gradient.
    final t = ((worldY + 22) / 72).clamp(0.0, 1.0);
    colors.addAll([
      low.red + (high.red - low.red) * t,
      low.green + (high.green - low.green) * t,
      low.blue + (high.blue - low.blue) * t,
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
