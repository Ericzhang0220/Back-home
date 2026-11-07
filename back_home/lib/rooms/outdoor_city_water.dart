part of 'outdoor_landscape.dart';

/// The city's river: a glossy, moving surface drawn by a shader. It mirrors the
/// actual scene (see [_PlanarReflection]), with the mirror image broken up by
/// layers of small drifting waves. The waves come from a filtered texture, so
/// they stay fine and irregular up close and settle to a calm sheen far away.
class _CityWater {
  _CityWater({
    required this.level,
    required this.minU,
    required this.maxU,
    required this.nearV,
    required this.farV,
    required this.wallZ,
  });

  final double level;
  final double minU;
  final double maxU;
  final double nearV;
  final double farV;
  final double wallZ;

  late final _PlanarReflection _reflection = _PlanarReflection(level: level);
  three.DataTexture? _waveTexture;
  three.ShaderMaterial? _material;
  three.Mesh? _mesh;
  final three.Vector3 _deep = three.Vector3();
  final three.Vector3 _zenith = three.Vector3();
  final three.Vector3 _horizon = three.Vector3();
  final three.Vector3 _fog = three.Vector3();
  final three.Vector3 _keyLight = three.Vector3(0, 40, -120);
  final three.Vector3 _keyColor = three.Vector3();
  double _time = 0;

  static const int _waveSize = 256;
  static three.Uint8Array? _waveBytes;

  /// A tiling field of wave slopes in red and green: many crossing wavelengths
  /// with no repeat within the tile, so no regular pattern shows.
  static three.Uint8Array _buildWaves() {
    final random = math.Random(0x7A7E);
    final table = Float64List(_waveSize);
    for (var i = 0; i < _waveSize; i += 1) {
      table[i] = math.cos(i / _waveSize * math.pi * 2);
    }
    final waves = <(int, int, int, double, double)>[];
    for (var i = 0; i < 40; i += 1) {
      final k = 2.0 + 28 * math.pow(random.nextDouble(), 1.7);
      final a = random.nextDouble() * math.pi * 2;
      final kx = (math.cos(a) * k).round();
      final ky = (math.sin(a) * k).round();
      if (kx == 0 && ky == 0) {
        continue;
      }
      final length = math.sqrt(kx * kx + ky * ky);
      // Short waves are smaller but not much less steep.
      final slope = math.pow(length, -0.35).toDouble();
      waves.add((
        kx,
        ky,
        random.nextInt(_waveSize),
        kx / length * slope,
        ky / length * slope,
      ));
    }
    final slopes = Float64List(_waveSize * _waveSize * 2);
    var peak = 0.0;
    for (var y = 0; y < _waveSize; y += 1) {
      for (var x = 0; x < _waveSize; x += 1) {
        var sx = 0.0;
        var sy = 0.0;
        for (final (kx, ky, phase, dx, dy) in waves) {
          final c = table[(kx * x + ky * y + phase) & (_waveSize - 1)];
          sx += dx * c;
          sy += dy * c;
        }
        final i = (y * _waveSize + x) * 2;
        slopes[i] = sx;
        slopes[i + 1] = sy;
        peak = math.max(peak, math.max(sx.abs(), sy.abs()));
      }
    }
    final bytes = three.Uint8Array(_waveSize * _waveSize * 4);
    final out = bytes.toDartList();
    for (var i = 0; i < _waveSize * _waveSize; i += 1) {
      out[i * 4] = ((slopes[i * 2] / peak * 0.5 + 0.5) * 255).round();
      out[i * 4 + 1] = ((slopes[i * 2 + 1] / peak * 0.5 + 0.5) * 255).round();
      out[i * 4 + 2] = 128;
      out[i * 4 + 3] = 255;
    }
    return bytes;
  }

  three.Mesh createMesh() {
    _waveTexture =
        three.DataTexture(
            _waveBytes ??= _buildWaves(),
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
    final x0 = minU + 1.0;
    final x1 = maxU + 1.0;
    final zNear = wallZ - nearV;
    final zFar = wallZ - farV;
    // Wound to face up; the shader does all the work on two triangles.
    final geometry = three.BufferGeometry()
      ..setAttributeFromString(
        'position',
        three.Float32BufferAttribute.fromList([
          x0, level, zNear, x1, level, zNear, x1, level, zFar, //
          x0, level, zNear, x1, level, zFar, x0, level, zFar,
        ], 3),
      );
    final material = three.ShaderMaterial.fromMap({
      'uniforms': <String, dynamic>{
        'uTime': <String, dynamic>{'value': 0.0},
        'uWaves': <String, dynamic>{'value': _waveTexture},
        'uReflection': <String, dynamic>{'value': _reflection.blank},
        'uMirror': <String, dynamic>{'value': _reflection.matrix},
        'uDeep': <String, dynamic>{'value': _deep},
        'uZenith': <String, dynamic>{'value': _zenith},
        'uHorizon': <String, dynamic>{'value': _horizon},
        'uFog': <String, dynamic>{'value': _fog},
        'uKeyLight': <String, dynamic>{'value': _keyLight},
        'uKeyColor': <String, dynamic>{'value': _keyColor},
        'uGlow': <String, dynamic>{'value': 0.0},
        'uFogAmount': <String, dynamic>{'value': 0.0},
      },
      'vertexShader': '''
varying vec3 vWorld;
void main() {
  vec4 world = modelMatrix * vec4(position, 1.0);
  vWorld = world.xyz;
  gl_Position = projectionMatrix * viewMatrix * world;
}
''',
      'fragmentShader': '''
uniform float uTime;
uniform sampler2D uWaves;
uniform sampler2D uReflection;
uniform mat4 uMirror;
uniform vec3 uDeep;
uniform vec3 uZenith;
uniform vec3 uHorizon;
uniform vec3 uFog;
uniform vec3 uKeyLight;
uniform vec3 uKeyColor;
uniform float uGlow;
uniform float uFogAmount;
varying vec3 vWorld;

// Three sizes of wave, turned against each other and drifting downstream at
// different speeds, so the tile never lines up with itself.
vec2 layer(vec2 p, float size, float c, float s, vec2 drift) {
  vec2 q = vec2(c * p.x - s * p.y, s * p.x + c * p.y) / size + drift * uTime;
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

void main() {
  vec3 toEye = cameraPosition - vWorld;
  float dist = length(toEye);
  vec3 V = toEye / dist;

  vec2 big = swell(vWorld.xz);
  vec2 fine = ripple(vWorld.xz);
  vec2 slope = big + fine;
  vec3 N = normalize(vec3(-slope.x, 1.0, -slope.y));
  float facing = max(dot(N, V), 0.0);
  float fresnel = 0.09 + 0.91 * pow(1.0 - facing, 2.6);

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

  vec3 color = mix(uDeep, reflected, fresnel);

  // Sun or moon: a sheen plus glitter on the crests, aimed at where it hangs.
  vec3 H = normalize(normalize(uKeyLight - vWorld) + V);
  vec2 sparkle = big + fine;
  float nh = max(dot(normalize(vec3(-sparkle.x, 1.0, -sparkle.y)), H), 0.0);
  color += uKeyColor * (pow(nh, 1400.0) * 0.8 + pow(nh, 140.0) * 0.06);

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
    set(
      _deep,
      _Rgb.lerp(
        const _Rgb.hex(0x050B14),
        const _Rgb.hex(0x124268),
        light.daylight,
      ),
    );
    set(_zenith, _Rgb.hex(light.zenith));
    set(_horizon, _Rgb.hex(light.fog));
    set(_fog, _Rgb.hex(light.fog));
    final strength = light.clearness * (0.3 + 0.7 * light.daylight);
    set(_keyColor, _Rgb.hex(light.sun).scale(strength));
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
