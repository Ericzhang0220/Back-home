part of 'outdoor_landscape.dart';

/// The city's river: a glossy, moving surface drawn by a shader. Rolling swells
/// and fine ripples bend the reflected view per pixel, so the sky, a sun or
/// moon glitter path, and the skyline and bridge all wobble in the water.
///
/// Reflections are looked up, not re-rendered: the skyline is baked into two
/// small textures on a vertical plane behind the river, and the bridge into a
/// third along its own span, and each pixel follows its reflected ray to them.
class _CityWater {
  _CityWater({
    required this.level,
    required this.minU,
    required this.maxU,
    required this.nearV,
    required this.farV,
    required this.wallZ,
  }) {
    _skyDay.toDartList().fillRange(0, _skyDay.toDartList().length, 0);
    _skyNight.toDartList().fillRange(0, _skyNight.toDartList().length, 0);
    _bridge.toDartList().fillRange(0, _bridge.toDartList().length, 0);
  }

  final double level;
  final double minU;
  final double maxU;
  final double nearV;
  final double farV;
  final double wallZ;

  static const int _skyWidth = 512;
  static const int _skyHeight = 112;
  static const int _bridgeWidth = 512;
  static const int _bridgeHeight = 72;
  static const double _skyPlaneV = 48;
  static const double _skyMinX = -130;
  static const double _skyMaxX = 130;
  static const double _skyMinY = -8;
  static const double _skyMaxY = 42;
  static const double _bridgeMinY = -6;
  static const double _bridgeMaxY = 14;

  final three.Uint8Array _skyDay = three.Uint8Array(_skyWidth * _skyHeight * 4);
  final three.Uint8Array _skyNight = three.Uint8Array(
    _skyWidth * _skyHeight * 4,
  );
  final three.Uint8Array _bridge = three.Uint8Array(
    _bridgeWidth * _bridgeHeight * 4,
  );
  final List<_ReflectedTower> _towers = [];
  final math.Random _speckle = math.Random(0x51EE);

  three.DataTexture? _skyDayTexture;
  three.DataTexture? _skyNightTexture;
  three.DataTexture? _bridgeTexture;
  three.ShaderMaterial? _material;
  final three.Vector3 _deep = three.Vector3();
  final three.Vector3 _zenith = three.Vector3();
  final three.Vector3 _horizon = three.Vector3();
  final three.Vector3 _fog = three.Vector3();
  final three.Vector3 _sunDirection = three.Vector3();
  final three.Vector3 _sunColor = three.Vector3();
  double _time = 0;

  void addTower(
    double x,
    double z,
    double width,
    double baseY,
    double top,
    _Rgb tint,
    double emit,
  ) {
    _towers.add(_ReflectedTower(x, z, width, baseY, top, tint, emit));
  }

  // --- Baking ------------------------------------------------------------------

  static const double _eyeX = OutdoorScene._eyeX;

  /// Where a point lands on the skyline plane, as seen from the window's
  /// mirror image under the water: exactly what a reflected ray will hit.
  (double, double) _projectToPlane(double x, double y, double z) {
    final eyeZ = wallZ + 0.6;
    final mirrorY = 2 * level - OutdoorScene._eyeY;
    final planeZ = wallZ - _skyPlaneV;
    final k = (planeZ - eyeZ) / (z - eyeZ);
    return (_eyeX + (x - _eyeX) * k, mirrorY + (y - mirrorY) * k);
  }

  void _bakeSkyline() {
    final day = _skyDay.toDartList().buffer.asUint32List(
      _skyDay.toDartList().offsetInBytes,
      _skyWidth * _skyHeight,
    );
    final night = _skyNight.toDartList().buffer.asUint32List(
      _skyNight.toDartList().offsetInBytes,
      _skyWidth * _skyHeight,
    );
    // Painted far to near, so nearer towers cover the ones behind.
    _towers.sort((a, b) => a.z.compareTo(b.z));
    final xScale = _skyWidth / (_skyMaxX - _skyMinX);
    final yScale = _skyHeight / (_skyMaxY - _skyMinY);
    for (final tower in _towers) {
      final (left, bottom) = _projectToPlane(
        tower.x - tower.width / 2,
        tower.baseY,
        tower.z,
      );
      final (right, top) = _projectToPlane(
        tower.x + tower.width / 2,
        tower.top,
        tower.z,
      );
      final x0 = ((left - _skyMinX) * xScale).floor().clamp(0, _skyWidth - 1);
      final x1 = ((right - _skyMinX) * xScale).ceil().clamp(0, _skyWidth);
      final y0 = ((bottom - _skyMinY) * yScale).floor().clamp(
        0,
        _skyHeight - 1,
      );
      final y1 = ((top - _skyMinY) * yScale).ceil().clamp(0, _skyHeight);
      final shade = 0.55 + _speckle.nextDouble() * 0.25;
      final wall = _FacadeAtlas._shade(tower.tint, shade);
      for (var y = y0; y < y1; y += 1) {
        // Lit floors come in bands, as on the facades above.
        final floorLit = _speckle.nextDouble() < 0.5;
        for (var x = x0; x < x1; x += 1) {
          final index = y * _skyWidth + x;
          day[index] = wall;
          final on = _speckle.nextDouble() < (floorLit ? 0.5 : 0.12);
          night[index] = on
              ? _FacadeAtlas._shade(
                  const _Rgb.hex(0xFFCB80),
                  (0.35 + _speckle.nextDouble() * 0.65) * tower.emit,
                )
              : 0xFF050608;
        }
      }
    }
  }

  (double, double, double, double) _bridgePlane = (0, 0, 1, 0); // x, z, dx, dz
  double _bridgeLength = 1;

  /// Sets the vertical plane the bridge's reflection is looked up on.
  void setBridgeSpan(
    (double, double, double) from,
    (double, double, double) to,
  ) {
    final dx = to.$1 - from.$1;
    final dz = to.$3 - from.$3;
    _bridgeLength = math.sqrt(dx * dx + dz * dz);
    _bridgePlane = (from.$1, from.$3, dx / _bridgeLength, dz / _bridgeLength);
  }

  /// Paints a light into the bridge's reflection map. [along] is 0..1 on the
  /// span. [coverage] marks solid structure that hides the sky behind it.
  void plotBridge(double along, double y, _Rgb light, {double radius = 0.5}) {
    final bytes = _bridge.toDartList();
    final px = along * (_bridgeWidth - 1);
    final py =
        (y - _bridgeMinY) / (_bridgeMaxY - _bridgeMinY) * (_bridgeHeight - 1);
    final reach = radius.ceil();
    for (var oy = -reach; oy <= reach; oy += 1) {
      for (var ox = -reach; ox <= reach; ox += 1) {
        final x = px.round() + ox;
        final row = py.round() + oy;
        if (x < 0 || x >= _bridgeWidth || row < 0 || row >= _bridgeHeight) {
          continue;
        }
        final i = (row * _bridgeWidth + x) * 4;
        bytes[i] = math.max(bytes[i], (light.r * 255).round());
        bytes[i + 1] = math.max(bytes[i + 1], (light.g * 255).round());
        bytes[i + 2] = math.max(bytes[i + 2], (light.b * 255).round());
        bytes[i + 3] = 255;
      }
    }
  }

  // --- Mesh --------------------------------------------------------------------

  three.DataTexture _texture(three.Uint8Array data, int w, int h) {
    return three.DataTexture(
        data,
        w,
        h,
        three.RGBAFormat,
        three.UnsignedByteType,
      )
      ..wrapS = three.ClampToEdgeWrapping
      ..wrapT = three.ClampToEdgeWrapping
      ..magFilter = three.LinearFilter
      ..minFilter = three.LinearMipmapLinearFilter
      ..generateMipmaps = true
      ..needsUpdate = true;
  }

  three.Mesh createMesh() {
    _bakeSkyline();
    _skyDayTexture = _texture(_skyDay, _skyWidth, _skyHeight);
    _skyNightTexture = _texture(_skyNight, _skyWidth, _skyHeight);
    _bridgeTexture = _texture(_bridge, _bridgeWidth, _bridgeHeight);
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
    final (bx, bz, bdx, bdz) = _bridgePlane;
    final material = three.ShaderMaterial.fromMap({
      'uniforms': <String, dynamic>{
        'uTime': <String, dynamic>{'value': 0.0},
        'uSkyDay': <String, dynamic>{'value': _skyDayTexture},
        'uSkyNight': <String, dynamic>{'value': _skyNightTexture},
        'uBridge': <String, dynamic>{'value': _bridgeTexture},
        'uDeep': <String, dynamic>{'value': _deep},
        'uZenith': <String, dynamic>{'value': _zenith},
        'uHorizon': <String, dynamic>{'value': _horizon},
        'uFog': <String, dynamic>{'value': _fog},
        'uSunDirection': <String, dynamic>{'value': _sunDirection},
        'uSunColor': <String, dynamic>{'value': _sunColor},
        'uGlow': <String, dynamic>{'value': 0.0},
        'uLit': <String, dynamic>{'value': 1.0},
        'uFogAmount': <String, dynamic>{'value': 0.0},
        'uSkyPlaneZ': <String, dynamic>{'value': wallZ - _skyPlaneV},
        'uSkyRect': <String, dynamic>{
          'value': three.Vector4(
            _skyMinX,
            _skyMinY,
            _skyMaxX - _skyMinX,
            _skyMaxY - _skyMinY,
          ),
        },
        'uBridgeOrigin': <String, dynamic>{
          'value': three.Vector3(bx, bz, _bridgeLength),
        },
        'uBridgeAxis': <String, dynamic>{'value': three.Vector2(bdx, bdz)},
        'uBridgeY': <String, dynamic>{
          'value': three.Vector2(_bridgeMinY, _bridgeMaxY - _bridgeMinY),
        },
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
uniform sampler2D uSkyDay;
uniform sampler2D uSkyNight;
uniform sampler2D uBridge;
uniform vec3 uDeep;
uniform vec3 uZenith;
uniform vec3 uHorizon;
uniform vec3 uFog;
uniform vec3 uSunDirection;
uniform vec3 uSunColor;
uniform float uGlow;
uniform float uLit;
uniform float uFogAmount;
uniform float uSkyPlaneZ;
uniform vec4 uSkyRect;
uniform vec3 uBridgeOrigin;
uniform vec2 uBridgeAxis;
uniform vec2 uBridgeY;
varying vec3 vWorld;

// Slope of one travelling wave.
vec2 wave(vec2 p, vec2 dir, float freq, float speed, float amp) {
  return dir * amp * cos(dot(p, dir) * freq + uTime * speed);
}

// Small waves at the scale of the river, about a car's length: they only
// nudge the reflection, so the water stays close to a calm mirror.
vec2 swell(vec2 p) {
  vec2 q = p + 0.7 * vec2(
    sin(p.y * 0.41 + uTime * 0.07),
    sin(p.x * 0.33 - uTime * 0.05)
  );
  vec2 s = wave(q, vec2(0.94, 0.34), 1.5, 0.3, 0.0065);
  s += wave(q, vec2(-0.45, 0.89), 2.3, 0.38, 0.005);
  s += wave(q, vec2(0.71, -0.71), 3.6, 0.5, 0.003);
  return s;
}

// Finer still: these only catch the light.
vec2 ripple(vec2 p) {
  vec2 s = wave(p, vec2(0.2, 0.98), 5.5, 0.7, 0.012);
  s += wave(p, vec2(-0.86, 0.5), 8.3, 0.95, 0.009);
  s += wave(p, vec2(0.6, 0.8), 12.1, 1.3, 0.006);
  return s;
}

// Calm water smears what it reflects downward into soft vertical streaks.
vec3 smear(sampler2D map, vec2 uv, float bias) {
  vec3 c = texture2D(map, uv, bias).rgb * 0.4;
  c += texture2D(map, uv + vec2(0.0, 0.016), bias).rgb * 0.25;
  c += texture2D(map, uv - vec2(0.0, 0.016), bias).rgb * 0.25;
  c += texture2D(map, uv - vec2(0.0, 0.034), bias).rgb * 0.1;
  return c;
}

void main() {
  vec3 toEye = cameraPosition - vWorld;
  float dist = length(toEye);
  vec3 V = toEye / dist;
  // Fine ripples fade out with distance, before they could shimmer as noise.
  float fine = smoothstep(30.0, 8.0, dist);
  vec2 s = swell(vWorld.xz) * mix(0.35, 1.0, smoothstep(50.0, 12.0, dist));
  vec3 N = normalize(vec3(-s.x, 1.0, -s.y));
  float facing = max(dot(N, V), 0.0);
  float fresnel = 0.05 + 0.95 * pow(1.0 - facing, 3.2);
  vec3 R = reflect(-V, N);
  R.y = abs(R.y) + 0.001;

  vec3 reflected = mix(uHorizon, uZenith, clamp(R.y * 1.6, 0.0, 1.0));
  // Skyline: follow the ray to its plane behind the river.
  if (R.z < -0.001) {
    float t = (uSkyPlaneZ - vWorld.z) / R.z;
    vec3 hit = vWorld + R * t;
    vec2 uv = (vec2(hit.x, hit.y) - uSkyRect.xy) / uSkyRect.zw;
    if (uv.y >= 0.0 && uv.y <= 1.0) {
      float cover = texture2D(uSkyDay, uv, 2.0).a;
      vec3 day = smear(uSkyDay, uv, 2.0);
      vec3 lights = smear(uSkyNight, uv, 3.0);
      reflected = mix(reflected, day * uLit, cover * 0.9);
      reflected += lights * uGlow * 1.25;
    }
  }
  // Bridge: the same, on the vertical plane through its span.
  vec2 axisNormal = vec2(-uBridgeAxis.y, uBridgeAxis.x);
  float denom = dot(R.xz, axisNormal);
  if (abs(denom) > 0.001) {
    float t = dot(uBridgeOrigin.xy - vWorld.xz, axisNormal) / denom;
    if (t > 0.0) {
      vec3 hit = vWorld + R * t;
      float along = dot(hit.xz - uBridgeOrigin.xy, uBridgeAxis) / uBridgeOrigin.z;
      float up = (hit.y - uBridgeY.x) / uBridgeY.y;
      if (along >= 0.0 && along <= 1.0 && up >= 0.0 && up <= 1.0) {
        vec2 bridgeUv = vec2(along, up);
        float solid = texture2D(uBridge, bridgeUv, 2.0).a;
        reflected = mix(reflected, uDeep, solid * 0.4 * (1.0 - uGlow));
        reflected += smear(uBridge, bridgeUv, 2.0) * uGlow * 0.9;
      }
    }
  }

  vec3 color = mix(uDeep, reflected, fresnel);
  // Sun or moon: broad sheen plus a tight glint riding the swell.
  vec3 H = normalize(uSunDirection + V);
  vec2 g = s + ripple(vWorld.xz) * fine;
  vec3 G = normalize(vec3(-g.x, 1.0, -g.y));
  float nh = max(dot(G, H), 0.0);
  color += uSunColor * (pow(nh, 700.0) * 0.9 + pow(nh, 90.0) * 0.1);

  float far = max(0.0, dist - 9.0) / 46.0;
  float haze = (1.0 - exp(-far * far * 1.6)) * uFogAmount;
  gl_FragColor = vec4(mix(color, uFog, haze), 1.0);
}
''',
    });
    _material = material;
    return three.Mesh(geometry, material)..frustumCulled = false;
  }

  void relight(OutdoorLight light) {
    final material = _material;
    if (material == null) {
      return;
    }
    void set(three.Vector3 target, _Rgb c) => target.setValues(c.r, c.g, c.b);
    final lit = (light.ambientStrength + light.sunStrength * 0.7).clamp(
      0.0,
      1.2,
    );
    final deep = _Rgb.lerp(
      const _Rgb.hex(0x050B14),
      const _Rgb.hex(0x124268),
      light.daylight,
    );
    set(_deep, deep);
    set(_zenith, _Rgb.hex(light.zenith));
    set(_horizon, _Rgb.hex(light.fog));
    set(_fog, _Rgb.hex(light.fog));
    // Behind the river from the house, so its glitter runs across the water.
    final sx = light.sunX;
    final sy = math.max(light.sunY, 0.14);
    final sz = -light.sunZ.abs();
    final length = math.sqrt(sx * sx + sy * sy + sz * sz);
    _sunDirection.setValues(sx / length, sy / length, sz / length);
    final sun = _Rgb.hex(light.sun);
    final strength = light.clearness * (0.3 + 0.7 * light.daylight);
    set(_sunColor, sun.scale(strength));
    material.uniforms['uGlow']['value'] = light.windowGlow;
    material.uniforms['uLit']['value'] = lit * (0.25 + 0.75 * light.daylight);
    material.uniforms['uFogAmount']['value'] = light.fogAmount;
  }

  void animate(double dt) {
    _time += dt;
    _material?.uniforms['uTime']['value'] = _time;
  }

  void dispose() {
    _skyDayTexture?.dispose();
    _skyNightTexture?.dispose();
    _bridgeTexture?.dispose();
  }
}

class _ReflectedTower {
  const _ReflectedTower(
    this.x,
    this.z,
    this.width,
    this.baseY,
    this.top,
    this.tint,
    this.emit,
  );

  final double x;
  final double z;
  final double width;
  final double baseY;
  final double top;
  final _Rgb tint;
  final double emit;
}
