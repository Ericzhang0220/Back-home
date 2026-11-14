import 'package:three_js/three_js.dart' as three;

/// The sun as a bright disc rather than a flat circle: darker toward its rim,
/// as the real sun is, wrapped in layered glow that spreads into the sky. Near
/// the horizon the disc and glow turn golden and deepen toward orange.
class SkySun extends three.Group {
  SkySun({
    required double radius,
    required int color,
    required double opacity,
  }) {
    const reach = _glowReach * 1.0;
    final size = radius * reach;
    final geometry = three.BufferGeometry()
      ..setAttributeFromString(
        'position',
        three.Float32BufferAttribute.fromList([
          -size, -size, 0, size, -size, 0, size, size, 0, //
          -size, -size, 0, size, size, 0, -size, size, 0,
        ], 3),
      )
      ..setAttributeFromString(
        'uv',
        three.Float32BufferAttribute.fromList([
          -reach, -reach, reach, -reach, reach, reach, //
          -reach, -reach, reach, reach, -reach, reach,
        ], 2),
      );
    final c = three.Color.fromHex32(color);
    _color.setValues(c.red, c.green, c.blue);
    _material = three.ShaderMaterial.fromMap({
      'uniforms': <String, dynamic>{
        'uColor': <String, dynamic>{'value': _color},
        'uOpacity': <String, dynamic>{'value': opacity},
        'uLow': <String, dynamic>{'value': 0.0},
      },
      'transparent': true,
      'premultipliedAlpha': true,
      'depthWrite': false,
      'vertexShader': '''
varying vec2 vDisc;
void main() {
  vDisc = uv;
  gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
  // Behind everything, however far, and still hidden by what stands in front.
  gl_Position.z = gl_Position.w * 0.99999;
}
''',
      'fragmentShader':
          '''
uniform vec3 uColor;
uniform float uOpacity;
uniform float uLow;
varying vec2 vDisc;

void main() {
  float r = length(vDisc);
  float edge = max(fwidth(r), 0.002);
  float disc = 1.0 - smoothstep(1.0 - edge, 1.0 + edge, r);

  // Limb darkening: the rim is seen through more of the sun's own haze.
  float mu = sqrt(max(1.0 - min(r, 1.0) * min(r, 1.0), 0.0));
  vec3 white = vec3(1.0, 0.985, 0.94);
  vec3 face = mix(white, uColor, 0.25 + 0.6 * uLow);
  // Brighter than white at its heart, so it reads as blinding.
  vec3 core = face * (0.8 + 0.5 * pow(mu, 0.45));

  // A tight bright corona, a broad warm glow, and a faint wide bloom.
  float out_ = max(r - 1.0, 0.0);
  float glow = 0.62 / (1.0 + out_ * out_ * 10.0)
             + 0.2 / (1.0 + out_ * out_ * 0.8)
             + 0.07 * exp(-out_ * 0.45);
  glow *= 1.0 - smoothstep($_glowReach.0 - 2.5, $_glowReach.0, r);
  vec3 halo = mix(uColor, vec3(1.0, 0.96, 0.86), 0.35 * (1.0 - uLow)) * glow;

  // Haze dims the glow more than the disc itself.
  float dim = mix(0.55, 1.0, uOpacity);
  gl_FragColor = vec4(
    core * disc * dim + halo * (1.0 - disc) * uOpacity,
    disc * dim
  );
}
''',
    });
    add(three.Mesh(geometry, _material)..frustumCulled = false);
  }

  static const int _glowReach = 7;
  final three.Vector3 _color = three.Vector3();
  late final three.ShaderMaterial _material;

  /// Deepens the colour as the sun sinks into thicker air.
  void setAltitude(double altitude) {
    final low = 1 - ((altitude - 0.02) / 0.35).clamp(0.0, 1.0);
    _material.uniforms['uLow']['value'] = low * low;
  }
}
