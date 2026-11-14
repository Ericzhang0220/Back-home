import 'dart:math' as math;
import 'dart:typed_data';

import 'package:three_js/three_js.dart' as three;

/// The moon as it actually looks: the near side's dark seas and bright ray
/// craters in their real places, lit from one side as a waxing gibbous, with
/// the shadowed part letting the night sky through and a soft halo around it.
class SkyMoon extends three.Group {
  SkyMoon({required double radius, required double opacity}) {
    const reach = _haloReach * 1.0;
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
    final texture = _createSurfaceTexture();
    final material = three.ShaderMaterial.fromMap({
      'uniforms': <String, dynamic>{
        'uMap': <String, dynamic>{'value': texture},
        'uTint': <String, dynamic>{'value': _tint},
        'uOpacity': <String, dynamic>{'value': opacity},
      },
      'transparent': true,
      'premultipliedAlpha': true,
      'depthWrite': false,
      'vertexShader': '''
varying vec2 vDisc;
void main() {
  vDisc = uv;
  gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
  // Behind everything, however far: never cut off by the far plane when the
  // view turns toward it, and still hidden by towers and trees in front.
  gl_Position.z = gl_Position.w * 0.99999;
}
''',
      'fragmentShader':
          '''
uniform sampler2D uMap;
uniform vec3 uTint;
uniform float uOpacity;
varying vec2 vDisc;

void main() {
  float r = length(vDisc);
  float edge = max(fwidth(r), 0.002);
  float disc = 1.0 - smoothstep(1.0 - edge, 1.0 + edge * 0.3, r);

  vec3 moon = vec3(0.0);
  float cover = 0.0;
  if (disc > 0.0) {
    vec2 uv = vDisc * 0.5 + 0.5;
    vec2 surface = texture2D(uMap, uv).rg;
    const float texel = 1.0 / 256.0;
    float dx = texture2D(uMap, uv + vec2(texel, 0.0)).g - surface.g;
    float dy = texture2D(uMap, uv + vec2(0.0, texel)).g - surface.g;
    float z = sqrt(max(1.0 - r * r, 0.0));
    vec3 N = normalize(vec3(vDisc - vec2(dx, dy) * 3.0, max(z, 0.02)));
    vec3 L = normalize(vec3(0.6, 0.18, 0.78));
    float cosI = dot(N, L);
    // Lunar soil scatters light back rather than diffusely, which is why the
    // full moon looks flat instead of like a shaded ball.
    float lit = 2.0 * max(cosI, 0.0) / (max(cosI, 0.0) + max(N.z, 0.08));
    lit = min(lit, 1.12) * smoothstep(-0.01, 0.1, cosI);
    moon = uTint * surface.r * lit;
    // Faint earthshine; otherwise the unlit part is simply night sky.
    moon += vec3(0.024, 0.03, 0.042) * surface.r;
    cover = disc * smoothstep(0.0, 0.3, lit);
  }

  // Scattered moonlight: a tight glow fading into a broad, very faint one.
  float out_ = max(r - 1.0, 0.0);
  float halo = 0.2 / (1.0 + out_ * out_ * 22.0) + 0.05 / (1.0 + out_ * out_ * 1.6);
  halo *= 1.0 - smoothstep(1.6, $_haloReach.0 - 0.1, r);
  vec3 glow = uTint * vec3(0.84, 0.9, 1.0) * halo;

  gl_FragColor = vec4(
    (moon * disc + glow * (1.0 - cover)) * uOpacity,
    cover * uOpacity
  );
}
''',
    });
    material.addEventListener('dispose', (_) => texture.dispose());
    add(three.Mesh(geometry, material)..frustumCulled = false);
  }

  static const int _haloReach = 5;

  final three.Vector3 _tint = three.Vector3(0.98, 0.97, 0.93);

  /// Warms toward amber as the moon sinks into the thick air at the horizon.
  void setAltitude(double altitude) {
    final low = 1 - ((altitude - 0.02) / 0.28).clamp(0.0, 1.0);
    final warm = low * low;
    _tint.setValues(0.98, 0.97 - warm * 0.24, 0.93 - warm * 0.46);
  }

  // --- Surface -----------------------------------------------------------------

  static const int _mapSize = 256;
  static final Uint8List _pixels = _paintSurface();

  static three.DataTexture _createSurfaceTexture() =>
      three.DataTexture(
          three.Uint8Array.fromList(_pixels),
          _mapSize,
          _mapSize,
          three.RGBAFormat,
          three.UnsignedByteType,
        )
        ..wrapS = three.ClampToEdgeWrapping
        ..wrapT = three.ClampToEdgeWrapping
        ..magFilter = three.LinearFilter
        ..minFilter = three.LinearMipmapLinearFilter
        ..generateMipmaps = true
        ..needsUpdate = true;

  // The near side's seas: x, y, x radius, y radius, in disc units, north up.
  static const List<(double, double, double, double)> _seas = [
    (-0.63, 0.24, 0.27, 0.5), // Oceanus Procellarum
    (-0.27, 0.5, 0.34, 0.3), // Imbrium
    (0.25, 0.45, 0.2, 0.19), // Serenitatis
    (0.42, 0.13, 0.26, 0.21), // Tranquillitatis
    (0.71, -0.07, 0.14, 0.23), // Fecunditatis
    (0.79, 0.34, 0.085, 0.12), // Crisium
    (0.5, -0.27, 0.1, 0.1), // Nectaris
    (-0.2, -0.36, 0.26, 0.19), // Nubium
    (-0.56, -0.4, 0.13, 0.13), // Humorum
    (-0.38, -0.13, 0.17, 0.14), // Cognitum
    (0.05, 0.24, 0.1, 0.08), // Vaporum
    (0.02, 0.79, 0.52, 0.055), // Frigoris
    (-0.47, 0.03, 0.16, 0.16), // Insularum
  ];

  // Young craters with bright rays: x, y, radius, ray length, ray strength.
  static const List<(double, double, double, double, double)> _rayed = [
    (-0.08, -0.7, 0.042, 1.05, 0.34), // Tycho
    (-0.33, 0.16, 0.042, 0.33, 0.3), // Copernicus
    (-0.6, 0.14, 0.022, 0.2, 0.26), // Kepler
    (-0.68, 0.4, 0.018, 0.14, 0.3), // Aristarchus
    (0.6, -0.04, 0.016, 0.16, 0.14), // Langrenus side
  ];

  static Uint8List _paintSurface() {
    const n = _mapSize;
    final random = math.Random(0x300);
    final albedo = List<double>.filled(n * n, 0);
    final height = List<double>.filled(n * n, 0.5);
    double px(int i) => (i + 0.5) / n * 2 - 1;

    for (var row = 0; row < n; row += 1) {
      final y = px(row);
      for (var col = 0; col < n; col += 1) {
        final x = px(col);
        // Coastlines wander; no sea is a clean ellipse.
        final wx = x + (_fbm(x * 3.4 + 7, y * 3.4, 5) - 0.5) * 0.34;
        final wy = y + (_fbm(x * 3.4, y * 3.4 + 11, 5) - 0.5) * 0.34;
        var sea = 0.0;
        for (final (cx, cy, rx, ry) in _seas) {
          final dx = (wx - cx) / rx;
          final dy = (wy - cy) / ry;
          sea = math.max(sea, 1 - (dx * dx + dy * dy));
        }
        final mask = _smooth(-0.22, 0.62, sea);
        final mottling = _fbm(x * 9, y * 9, 5);
        final highland = 0.8 + (mottling - 0.5) * 0.3;
        final mare = 0.5 + (_fbm(x * 6 + 3, y * 6 + 5, 4) - 0.5) * 0.24;
        albedo[row * n + col] = highland + (mare - highland) * mask;
        // The highlands are rough; the seas are smooth lava plains.
        height[row * n + col] =
            0.5 + (mottling - 0.5) * (0.26 - 0.2 * mask) - mask * 0.05;
      }
    }

    void crater(double cx, double cy, double radius, double bright) {
      final centre = math.sqrt(cx * cx + cy * cy);
      // Foreshortened toward the limb, on a sphere seen from afar.
      final squash = math.sqrt(math.max(1 - centre * centre, 0.05));
      final ux = centre > 0 ? cx / centre : 1.0;
      final uy = centre > 0 ? cy / centre : 0.0;
      final span = radius * 1.7;
      final c0 = (((cx - span) + 1) / 2 * n).floor().clamp(0, n - 1);
      final c1 = (((cx + span) + 1) / 2 * n).ceil().clamp(0, n - 1);
      final r0 = (((cy - span) + 1) / 2 * n).floor().clamp(0, n - 1);
      final r1 = (((cy + span) + 1) / 2 * n).ceil().clamp(0, n - 1);
      for (var row = r0; row <= r1; row += 1) {
        for (var col = c0; col <= c1; col += 1) {
          final dx = px(col) - cx;
          final dy = px(row) - cy;
          final radial = (dx * ux + dy * uy) / squash;
          final tangent = -dx * uy + dy * ux;
          final d = math.sqrt(radial * radial + tangent * tangent) / radius;
          if (d > 1.7) {
            continue;
          }
          final i = row * n + col;
          if (d < 1) {
            height[i] -= 0.1 * (1 - d * d) * math.min(radius * 22, 1.0);
            albedo[i] += bright * (1 - d);
          }
          // Raised rim, then ejecta fading out.
          final rim = math.exp(-(d - 1) * (d - 1) * 34);
          height[i] += 0.06 * rim * math.min(radius * 22, 1.0);
          albedo[i] += bright * 0.45 * rim;
        }
      }
    }

    for (var i = 0; i < 240; i += 1) {
      final a = random.nextDouble() * math.pi * 2;
      final d = math.sqrt(random.nextDouble()) * 0.97;
      final cx = math.cos(a) * d;
      final cy = math.sin(a) * d;
      final radius = 0.006 + math.pow(random.nextDouble(), 4) * 0.04;
      // Most lie in the older southern highlands.
      if (cy > 0.2 && random.nextDouble() < 0.5) {
        continue;
      }
      crater(cx, cy, radius, 0.02 + random.nextDouble() * 0.05);
    }

    for (final (cx, cy, radius, reach, strength) in _rayed) {
      final spokes = <(double, double, double)>[
        for (var i = 0; i < 17; i += 1)
          (
            random.nextDouble() * math.pi * 2,
            0.03 + random.nextDouble() * 0.09,
            0.45 + random.nextDouble() * 0.75,
          ),
      ];
      for (var row = 0; row < n; row += 1) {
        final y = px(row) - cy;
        for (var col = 0; col < n; col += 1) {
          final x = px(col) - cx;
          final d = math.sqrt(x * x + y * y);
          if (d > reach * 1.3 || d < 1e-4) {
            continue;
          }
          final angle = math.atan2(y, x);
          var ray = 0.0;
          for (final (spoke, width, length) in spokes) {
            var delta = (angle - spoke) % (math.pi * 2);
            if (delta > math.pi) {
              delta = math.pi * 2 - delta;
            }
            final fall = 1 - d / (reach * length);
            if (fall > 0 && delta < width) {
              ray = math.max(ray, (1 - delta / width) * fall);
            }
          }
          final blanket = math.exp(-d / (radius * 2.6));
          albedo[row * n + col] += strength * math.max(ray * 0.75, blanket);
        }
      }
      crater(cx, cy, radius, strength * 0.6);
    }

    final out = Uint8List(n * n * 4);
    for (var i = 0; i < n * n; i += 1) {
      out[i * 4] = (albedo[i].clamp(0.0, 1.0) * 255).round();
      out[i * 4 + 1] = (height[i].clamp(0.0, 1.0) * 255).round();
      out[i * 4 + 3] = 255;
    }
    return out;
  }

  static double _smooth(double a, double b, double x) {
    final t = ((x - a) / (b - a)).clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }

  static double _hash(int x, int y) {
    final h = (x * 374761393 + y * 668265263) & 0x7FFFFFFF;
    final m = ((h ^ (h >> 13)) * 1274126177) & 0x7FFFFFFF;
    return ((m ^ (m >> 16)) & 0xFFFF) / 0xFFFF;
  }

  static double _noise(double x, double y) {
    final xi = x.floor();
    final yi = y.floor();
    final fx = x - xi;
    final fy = y - yi;
    final sx = fx * fx * (3 - 2 * fx);
    final sy = fy * fy * (3 - 2 * fy);
    final a = _hash(xi, yi);
    final b = _hash(xi + 1, yi);
    final c = _hash(xi, yi + 1);
    final d = _hash(xi + 1, yi + 1);
    return a + (b - a) * sx + (c - a) * sy + (a - b - c + d) * sx * sy;
  }

  static double _fbm(double x, double y, int octaves) {
    var sum = 0.0;
    var amp = 0.5;
    var scale = 1.0;
    var total = 0.0;
    for (var i = 0; i < octaves; i += 1) {
      sum += _noise(x * scale, y * scale) * amp;
      total += amp;
      amp *= 0.5;
      scale *= 2.03;
    }
    return sum / total;
  }
}
