import 'dart:math' as math;

import 'package:three_js/three_js.dart' as three;

/// The night sky's stars as points of light, not white dots: each has a
/// sharp core and a soft glow, a colour from blue-white to warm amber, its own
/// brightness, and a slow twinkle. Away from the city a faint band of many
/// small stars crosses the sky, like the Milky Way.
class SkyStars extends three.Group {
  SkyStars({
    required List<({double x, double y, double size, double brightness})> stars,
    required double opacity,
  }) {
    final random = math.Random(0x57A2);
    final positions = <double>[];
    final corners = <double>[];
    final details = <double>[];
    final tints = <double>[];
    final indices = <int>[];
    for (final star in stars) {
      // Hotter stars are bluer; most sit near white.
      final heat = random.nextDouble();
      final tint = heat < 0.18
          ? (1.0, 0.82, 0.62)
          : (heat > 0.78 ? (0.78, 0.86, 1.0) : (1.0, 0.97, 0.92));
      final phase = random.nextDouble();
      final base = positions.length ~/ 3;
      for (final (cx, cy) in const [
        (-1.0, -1.0),
        (1.0, -1.0),
        (1.0, 1.0),
        (-1.0, 1.0),
      ]) {
        positions.addAll([star.x, star.y, 0]);
        corners.addAll([cx, cy]);
        details.addAll([star.size, star.brightness, phase]);
        tints.addAll([tint.$1, tint.$2, tint.$3]);
      }
      indices.addAll([base, base + 1, base + 2, base, base + 2, base + 3]);
    }
    final geometry = three.BufferGeometry()
      ..setAttributeFromString(
        'position',
        three.Float32BufferAttribute.fromList(positions, 3),
      )
      ..setAttributeFromString(
        'aCorner',
        three.Float32BufferAttribute.fromList(corners, 2),
      )
      ..setAttributeFromString(
        'aStar',
        three.Float32BufferAttribute.fromList(details, 3),
      )
      ..setAttributeFromString(
        'aTint',
        three.Float32BufferAttribute.fromList(tints, 3),
      )
      ..setIndex(indices);
    _material = three.ShaderMaterial.fromMap({
      'uniforms': <String, dynamic>{
        'uTime': <String, dynamic>{'value': 0.0},
        'uOpacity': <String, dynamic>{'value': opacity},
      },
      'transparent': true,
      'depthWrite': false,
      'blending': three.AdditiveBlending,
      'vertexShader': '''
attribute vec2 aCorner;
attribute vec3 aStar;
attribute vec3 aTint;
varying vec2 vCorner;
varying vec3 vStar;
varying vec3 vTint;
void main() {
  vCorner = aCorner;
  vStar = aStar;
  vTint = aTint;
  // Each star faces the viewer, whichever way the camera turns.
  vec4 view = modelViewMatrix * vec4(position, 1.0);
  view.xy += aCorner * aStar.x;
  gl_Position = projectionMatrix * view;
  gl_Position.z = gl_Position.w * 0.99998;
}
''',
      'fragmentShader': '''
uniform float uTime;
uniform float uOpacity;
varying vec2 vCorner;
varying vec3 vStar;
varying vec3 vTint;
void main() {
  float d2 = dot(vCorner, vCorner);
  float core = exp(-d2 * 16.0);
  float glow = exp(-d2 * 3.5) * 0.38;
  float phase = vStar.z;
  float twinkle = 0.72 + 0.28 * sin(uTime * (1.1 + phase * 2.3) + phase * 40.0)
                * sin(uTime * (0.37 + phase) + phase * 13.0);
  vec3 c = vTint * (core * 1.35 + glow) * vStar.y * twinkle * uOpacity;
  gl_FragColor = vec4(c, 1.0);
}
''',
    });
    add(three.Mesh(geometry, _material)..frustumCulled = false);
  }

  late final three.ShaderMaterial _material;
  double _time = 0;

  void advance(double dt) {
    _time += dt;
    _material.uniforms['uTime']['value'] = _time;
  }
}
