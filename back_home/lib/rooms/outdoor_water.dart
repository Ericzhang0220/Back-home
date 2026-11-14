part of 'outdoor_landscape.dart';

/// Open water for every scene: rivers, pools and the sea. The surface mirrors
/// the actual scenery (see [_PlanarReflection]), broken up by layers of small
/// waves from a filtered texture, so it stays fine and irregular up close and
/// settles to a calm sheen far away. Each vertex carries its own current,
/// foam and water colour, so a river can run and churn while a pond lies still.
class _MirrorWater {
  _MirrorWater({
    required this.level,
    this.waveScale = 1,
    this.waveStrength = 1,
    this.maxFresnel = 1,
    this.refreshSeconds = 0.5,
  });

  final double level;

  /// Wave size relative to a river's; the open sea runs larger.
  final double waveScale;
  final double waveStrength;

  /// Below 1 keeps grazing water from turning into a pure mirror of the sky,
  /// so a sea horizon still reads as darker than the sky above it.
  final double maxFresnel;

  /// How often a still view refreshes its mirror image.
  final double refreshSeconds;

  final _positions = <double>[];
  // Current (x, z) and foam, packed together.
  final _flows = <double>[];
  final _tints = <double>[];
  final indices = <int>[];

  late final _PlanarReflection _reflection = _PlanarReflection(
    level: level,
    refreshSeconds: refreshSeconds,
  );
  three.DataTexture? _waveTexture;
  three.ShaderMaterial? _material;
  three.Mesh? _mesh;
  final three.Vector3 _zenith = three.Vector3();
  final three.Vector3 _horizon = three.Vector3();
  final three.Vector3 _fog = three.Vector3();
  final three.Vector3 _foamColor = three.Vector3();
  final three.Vector3 _keyLight = three.Vector3(0, 40, -120);
  final three.Vector3 _keyColor = three.Vector3();
  double _time = 0;

  int get count => _positions.length ~/ 3;

  /// Adds a vertex on the surface. [flowX], [flowZ] are the current in world
  /// units per second, [foam] 0..1 how white the water runs there, and [tint]
  /// the water's own colour seen from straight above, in daylight.
  int vertex(
    double x,
    double z, {
    double flowX = 0,
    double flowZ = 0,
    double foam = 0,
    required _Rgb tint,
  }) {
    _positions.addAll([x, level, z]);
    _flows.addAll([flowX, flowZ, foam]);
    _tints.addAll([tint.r, tint.g, tint.b]);
    return count - 1;
  }

  /// Covers a grid of the ground with water, keeping only the cells where the
  /// ground dips below the surface; the terrain hides the ragged edge.
  void sheet({
    required double uMin,
    required double uMax,
    required double vMin,
    required double vMax,
    required double step,
    required double Function(double u) worldX,
    required double Function(double v) worldZ,
    required double Function(double u, double v) ground,
    required ({double flowX, double flowZ, double foam, _Rgb tint}) Function(
      double u,
      double v,
      double depth,
    )
    at,
  }) {
    final cols = ((uMax - uMin) / step).round() + 1;
    final rows = ((vMax - vMin) / step).round() + 1;
    final wet = List<bool>.filled(cols * rows, false);
    final index = List<int>.filled(cols * rows, -1);
    for (var row = 0; row < rows; row += 1) {
      for (var col = 0; col < cols; col += 1) {
        final u = uMin + col * step;
        final v = vMin + row * step;
        wet[row * cols + col] = ground(u, v) < level + 0.08;
      }
    }
    int vertexAt(int col, int row) {
      final i = row * cols + col;
      if (index[i] >= 0) {
        return index[i];
      }
      final u = uMin + col * step;
      final v = vMin + row * step;
      final p = at(u, v, level - ground(u, v));
      return index[i] = vertex(
        worldX(u),
        worldZ(v),
        flowX: p.flowX,
        flowZ: p.flowZ,
        foam: p.foam,
        tint: p.tint,
      );
    }

    for (var row = 0; row < rows - 1; row += 1) {
      for (var col = 0; col < cols - 1; col += 1) {
        final i = row * cols + col;
        if (!(wet[i] || wet[i + 1] || wet[i + cols] || wet[i + cols + 1])) {
          continue;
        }
        final a = vertexAt(col, row);
        final b = vertexAt(col + 1, row);
        final c = vertexAt(col, row + 1);
        final d = vertexAt(col + 1, row + 1);
        // Wound to face up (v grows toward world -z).
        indices.addAll([a, b, c, b, d, c]);
      }
    }
  }

  // --- Waves ---------------------------------------------------------------

  static const int _waveSize = 256;
  static final Uint8List _waveBytes = _buildWaves();

  /// A tiling field: wave slopes in red and green from many crossing
  /// wavelengths, so no regular pattern shows, and in blue a softer noise that
  /// foam is cut from.
  static Uint8List _buildWaves() {
    final random = math.Random(0x7A7E);
    final table = Float64List(_waveSize);
    for (var i = 0; i < _waveSize; i += 1) {
      table[i] = math.cos(i / _waveSize * math.pi * 2);
    }
    List<(int, int, int, double, double)> waves(
      int n,
      double kMin,
      double kMax,
      double falloff,
    ) {
      final list = <(int, int, int, double, double)>[];
      while (list.length < n) {
        final k = kMin + (kMax - kMin) * math.pow(random.nextDouble(), 1.7);
        final a = random.nextDouble() * math.pi * 2;
        final kx = (math.cos(a) * k).round();
        final ky = (math.sin(a) * k).round();
        if (kx == 0 && ky == 0) {
          continue;
        }
        final length = math.sqrt(kx * kx + ky * ky);
        final weight = math.pow(length, -falloff).toDouble();
        list.add((
          kx,
          ky,
          random.nextInt(_waveSize),
          kx / length * weight,
          ky / length * weight,
        ));
      }
      return list;
    }

    final slopeWaves = waves(40, 2, 30, 0.35);
    final foamWaves = waves(24, 2, 14, 1.1);
    final values = Float64List(_waveSize * _waveSize * 3);
    var slopePeak = 0.0;
    var foamPeak = 0.0;
    for (var y = 0; y < _waveSize; y += 1) {
      for (var x = 0; x < _waveSize; x += 1) {
        var sx = 0.0;
        var sy = 0.0;
        for (final (kx, ky, phase, dx, dy) in slopeWaves) {
          final c = table[(kx * x + ky * y + phase) & (_waveSize - 1)];
          sx += dx * c;
          sy += dy * c;
        }
        var foam = 0.0;
        for (final (kx, ky, phase, dx, dy) in foamWaves) {
          // dx, dy carry the weight; their length is it.
          foam +=
              math.sqrt(dx * dx + dy * dy) *
              table[(kx * x + ky * y + phase) & (_waveSize - 1)];
        }
        final i = (y * _waveSize + x) * 3;
        values[i] = sx;
        values[i + 1] = sy;
        values[i + 2] = foam;
        slopePeak = math.max(slopePeak, math.max(sx.abs(), sy.abs()));
        foamPeak = math.max(foamPeak, foam.abs());
      }
    }
    final out = Uint8List(_waveSize * _waveSize * 4);
    for (var i = 0; i < _waveSize * _waveSize; i += 1) {
      out[i * 4] = ((values[i * 3] / slopePeak * 0.5 + 0.5) * 255).round();
      out[i * 4 + 1] = ((values[i * 3 + 1] / slopePeak * 0.5 + 0.5) * 255)
          .round();
      out[i * 4 + 2] = ((values[i * 3 + 2] / foamPeak * 0.5 + 0.5) * 255)
          .round();
      out[i * 4 + 3] = 255;
    }
    return out;
  }

  // --- Mesh ----------------------------------------------------------------

  three.Mesh createMesh() {
    _waveTexture =
        three.DataTexture(
            three.Uint8Array.fromList(_waveBytes),
            _waveSize,
            _waveSize,
            three.RGBAFormat,
            three.UnsignedByteType,
          )
          ..wrapS = three.RepeatWrapping
          ..wrapT = three.RepeatWrapping
          ..magFilter = three.LinearFilter
          ..minFilter = three.LinearMipmapLinearFilter
          ..generateMipmaps = true
          ..anisotropy = 8
          ..needsUpdate = true;
    final geometry = three.BufferGeometry()
      ..setAttributeFromString(
        'position',
        three.Float32BufferAttribute.fromList(_positions, 3),
      )
      ..setAttributeFromString(
        'aFlow',
        three.Float32BufferAttribute.fromList(_flows, 3),
      )
      ..setAttributeFromString(
        'aTint',
        three.Float32BufferAttribute.fromList(_tints, 3),
      )
      ..setIndex(indices);
    final material = three.ShaderMaterial.fromMap({
      'uniforms': <String, dynamic>{
        'uTime': <String, dynamic>{'value': 0.0},
        'uWaves': <String, dynamic>{'value': _waveTexture},
        'uReflection': <String, dynamic>{'value': _reflection.blank},
        'uMirror': <String, dynamic>{'value': _reflection.matrix},
        'uZenith': <String, dynamic>{'value': _zenith},
        'uHorizon': <String, dynamic>{'value': _horizon},
        'uFog': <String, dynamic>{'value': _fog},
        'uFoamColor': <String, dynamic>{'value': _foamColor},
        'uKeyLight': <String, dynamic>{'value': _keyLight},
        'uKeyColor': <String, dynamic>{'value': _keyColor},
        'uLit': <String, dynamic>{'value': 1.0},
        'uGlow': <String, dynamic>{'value': 0.0},
        'uFogAmount': <String, dynamic>{'value': 0.0},
        'uWaveScale': <String, dynamic>{'value': waveScale},
        'uWaveStrength': <String, dynamic>{'value': waveStrength},
        'uMaxFresnel': <String, dynamic>{'value': maxFresnel},
      },
      'vertexShader': '''
attribute vec3 aFlow;
attribute vec3 aTint;
varying vec3 vWorld;
varying vec2 vFlow;
varying float vFoam;
varying vec3 vTint;
void main() {
  vec4 world = modelMatrix * vec4(position, 1.0);
  vWorld = world.xyz;
  vFlow = aFlow.xy;
  vFoam = aFlow.z;
  vTint = aTint;
  gl_Position = projectionMatrix * viewMatrix * world;
}
''',
      'fragmentShader': '''
uniform float uTime;
uniform sampler2D uWaves;
uniform sampler2D uReflection;
uniform mat4 uMirror;
uniform vec3 uZenith;
uniform vec3 uHorizon;
uniform vec3 uFog;
uniform vec3 uFoamColor;
uniform vec3 uKeyLight;
uniform vec3 uKeyColor;
uniform float uLit;
uniform float uGlow;
uniform float uFogAmount;
uniform float uWaveScale;
uniform float uWaveStrength;
uniform float uMaxFresnel;
varying vec3 vWorld;
varying vec2 vFlow;
varying float vFoam;
varying vec3 vTint;

// Three sizes of wave, turned against each other and drifting at different
// speeds, so the tile never lines up with itself.
vec2 layer(vec2 p, float size, float c, float s, vec2 drift) {
  vec2 q = vec2(c * p.x - s * p.y, s * p.x + c * p.y) / (size * uWaveScale)
         + drift * uTime / uWaveScale;
  vec2 slope = texture2D(uWaves, q).rg - 0.5;
  return vec2(c * slope.x + s * slope.y, -s * slope.x + c * slope.y);
}

vec2 swell(vec2 p) {
  return layer(p, 15.0, 0.96, 0.28, vec2(0.0065, 0.0015)) * 0.075
       + layer(p, 6.1, 0.59, -0.81, vec2(-0.008, 0.012)) * 0.06;
}

vec2 ripple(vec2 p) {
  return layer(p, 2.3, -0.42, 0.91, vec2(0.021, 0.024)) * 0.05
       + layer(p, 1.37, 0.77, 0.64, vec2(-0.04, 0.033)) * 0.022;
}

vec3 mirrored(vec2 uv, float lod) {
  return texture2DLodEXT(uReflection, uv, lod).rgb;
}

// Foam torn into streaks along the current.
float foamAt(vec2 p, vec2 along, vec2 warp) {
  vec2 across = vec2(-along.y, along.x);
  vec2 q = vec2(dot(p, across) * 0.6, dot(p, along) * 0.38) + warp * 3.0;
  float n = texture2D(uWaves, q).b * 0.65 + texture2D(uWaves, q * 2.7 + 0.31).b * 0.35;
  return n;
}

void main() {
  vec3 toEye = cameraPosition - vWorld;
  float dist = length(toEye);
  vec3 V = toEye / dist;

  // The current carries the waves and foam along: two copies half a cycle
  // apart, each faded out before it is pulled back to the start.
  const float cycle = 3.0;
  float phase0 = fract(uTime / cycle);
  float phase1 = fract(phase0 + 0.5);
  float weight0 = 1.0 - abs(2.0 * phase0 - 1.0);
  vec2 p0 = vWorld.xz - vFlow * phase0 * cycle;
  vec2 p1 = vWorld.xz - vFlow * phase1 * cycle + vec2(3.7, 1.9);
  vec2 big = swell(p0) * weight0 + swell(p1) * (1.0 - weight0);
  vec2 fine = ripple(p0) * weight0 + ripple(p1) * (1.0 - weight0);
  // Running water is choppier than still water.
  float chop = 1.0 + min(length(vFlow), 1.5) * 0.5;
  big *= uWaveStrength * chop;
  fine *= uWaveStrength * chop;

  vec2 slope = big + fine;
  vec3 N = normalize(vec3(-slope.x, 1.0, -slope.y));
  float facing = max(dot(N, V), 0.0);
  float fresnel = min(0.09 + 0.91 * pow(1.0 - facing, 2.6), uMaxFresnel);

  vec3 R = reflect(-V, N);
  R.y = abs(R.y) + 0.002;
  // Follow the bent ray as far as a typical reflected object. On a still
  // surface this lands exactly on the mirror image of this point.
  vec4 clip = uMirror * vec4(vWorld + R * (7.0 + dist * 0.7), 1.0);
  vec2 uv = clip.xy / max(clip.w, 0.001) * 0.5 + 0.5;

  // Shallow views stretch what they reflect into streaks, as real water does.
  float graze = 1.0 - V.y;
  float reach = mix(0.0015, 0.011, graze * graze) * (1.0 + uGlow * 1.2);
  vec2 up = vec2(0.0, reach);
  vec3 image = mirrored(uv, 1.0) * 0.32;
  image += (mirrored(uv + up, 1.4) + mirrored(uv - up, 1.4)) * 0.22;
  image += (mirrored(uv + up * 2.4, 2.2) + mirrored(uv - up * 2.4, 2.2)) * 0.12;
  // Bright windows stay bright when they're smeared.
  float glint = max(image.r, max(image.g, image.b));
  image *= 1.0 + uGlow * smoothstep(0.12, 0.6, glint) * 1.1;

  // Rays that leave the mirror image still see the sky.
  vec3 sky = mix(uHorizon, uZenith, clamp(R.y * 1.6, 0.0, 1.0));
  vec2 edge = smoothstep(vec2(0.0), vec2(0.02), uv)
            * smoothstep(vec2(0.0), vec2(0.02), 1.0 - uv);
  vec3 reflected = mix(sky, image, edge.x * edge.y);

  vec3 color = mix(vTint * uLit, reflected, fresnel);

  // Sun or moon: a sheen plus glitter on the crests, aimed at where it hangs.
  vec3 H = normalize(normalize(uKeyLight - vWorld) + V);
  float nh = max(dot(normalize(vec3(-slope.x, 1.0, -slope.y)), H), 0.0);
  color += uKeyColor * (pow(nh, 1400.0) * 0.8 + pow(nh, 140.0) * 0.06);

  if (vFoam > 0.01) {
    vec2 along = normalize(vFlow + vec2(0.0001, 0.00013));
    float n = foamAt(p0, along, slope) * weight0 +
        foamAt(p1, along, slope) * (1.0 - weight0);
    float foam = smoothstep(0.7 - vFoam * 0.4, 0.86 - vFoam * 0.3, n);
    color = mix(color, uFoamColor, foam * 0.6);
  }

  float far = max(0.0, dist - 9.0) / 46.0;
  float haze = (1.0 - exp(-far * far * 1.6)) * uFogAmount;
  gl_FragColor = vec4(mix(color, uFog, haze), 1.0);
}
''',
    });
    _material = material;
    return _mesh = three.Mesh(geometry, material)..frustumCulled = false;
  }

  void relight(OutdoorLight light) {
    final material = _material;
    if (material == null) {
      return;
    }
    void set(three.Vector3 target, _Rgb c) => target.setValues(c.r, c.g, c.b);
    set(_zenith, _Rgb.hex(light.zenith));
    set(_horizon, _Rgb.hex(light.fog));
    set(_fog, _Rgb.hex(light.fog));
    final sky = _Rgb.hex(light.sky);
    final sun = _Rgb.hex(light.sun);
    // Foam is lit like the land: sky light plus a share of the sun.
    set(
      _foamColor,
      _Rgb(
        (sky.r * light.ambientStrength + sun.r * light.sunStrength * 0.7) *
            0.92,
        (sky.g * light.ambientStrength + sun.g * light.sunStrength * 0.7) *
            0.92,
        (sky.b * light.ambientStrength + sun.b * light.sunStrength * 0.7) *
            0.92,
      ),
    );
    final strength = light.clearness * (0.3 + 0.7 * light.daylight);
    set(_keyColor, sun.scale(strength));
    material.uniforms['uLit']['value'] =
        (light.ambientStrength + light.sunStrength * 0.75).clamp(0.08, 1.2) *
        (0.12 + 0.88 * light.daylight);
    material.uniforms['uGlow']['value'] = light.windowGlow;
    material.uniforms['uFogAmount']['value'] = light.fogAmount;
  }

  void setKeyLightPosition(double x, double y, double z) {
    _keyLight.setValues(x, y, z);
  }

  void updateReflection(
    double dt,
    three.WebGLRenderer renderer,
    three.Scene scene,
    three.PerspectiveCamera camera,
    List<three.Object3D> outdoors,
    List<three.Object3D> movers,
  ) {
    final mesh = _mesh;
    final material = _material;
    if (mesh == null || material == null) {
      return;
    }
    final texture = _reflection.update(dt, renderer, scene, camera, outdoors, [
      mesh,
      ...movers,
    ]);
    if (texture != null) {
      material.uniforms['uReflection']['value'] = texture;
    }
  }

  void animate(double dt) {
    _time += dt;
    _material?.uniforms['uTime']['value'] = _time;
  }

  void dispose() {
    _waveTexture?.dispose();
    _reflection.dispose();
  }
}
