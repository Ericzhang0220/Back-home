part of 'outdoor_landscape.dart';

// --- Baked-lighting mesh -------------------------------------------------------

class _LitMesh {
  _LitMesh({required this.wrap, bool indexed = false, this.water = false})
    : indices = indexed ? <int>[] : null;

  final double wrap;
  final bool water;
  final List<int>? indices;
  final _positions = <double>[];
  final _normals = <double>[];
  final _albedo = <double>[];
  final _ao = <double>[];
  // Night emission per vertex (r, g, b, on); blended in by windowGlow.
  final _emissive = <double>[];
  three.Float32BufferAttribute? _colorAttribute;

  int get count => _positions.length ~/ 3;

  void vertex(
    double x,
    double y,
    double z,
    double nx,
    double ny,
    double nz,
    _Rgb color, {
    required double ao,
    _Rgb? emissive,
  }) {
    _positions.addAll([x, y, z]);
    _normals.addAll([nx, ny, nz]);
    _albedo.addAll([color.r, color.g, color.b]);
    _ao.add(ao);
    if (emissive == null) {
      _emissive.addAll(const [0, 0, 0, 0]);
    } else {
      _emissive.addAll([emissive.r, emissive.g, emissive.b, 1]);
    }
  }

  three.Mesh createMesh() {
    final geometry = three.BufferGeometry()
      ..setAttributeFromString(
        'position',
        three.Float32BufferAttribute.fromList(_positions, 3),
      );
    final colors = three.Float32BufferAttribute.fromList(
      List<double>.filled(_positions.length, 1),
      3,
    );
    geometry.setAttributeFromString('color', colors);
    if (indices != null) {
      geometry.setIndex(indices!);
    }
    _colorAttribute = colors;
    return three.Mesh(
      geometry,
      three.MeshBasicMaterial.fromMap({
        'color': 0xFFFFFF,
        'vertexColors': true,
      }),
    )..frustumCulled = false;
  }

  void relight(
    OutdoorLight light,
    double eyeX,
    double eyeY,
    double eyeZ, {
    Float32List? shadow,
  }) {
    final attribute = _colorAttribute;
    if (attribute == null) {
      return;
    }
    final out = attribute.array.toDartList();
    final sun = _Rgb.hex(light.sun);
    final sky = _Rgb.hex(light.sky);
    final ground = _Rgb.hex(light.ground);
    final fog = _Rgb.hex(light.fog);
    final sunR = sun.r * light.sunStrength;
    final sunG = sun.g * light.sunStrength;
    final sunB = sun.b * light.sunStrength;
    final sat = light.saturation;
    final glow = light.windowGlow;
    final n = count;
    for (var i = 0; i < n; i += 1) {
      final i3 = i * 3;
      final px = _positions[i3];
      final py = _positions[i3 + 1];
      final pz = _positions[i3 + 2];
      final dx = px - eyeX;
      final dy = py - eyeY;
      final dz = pz - eyeZ;
      final distance = math.sqrt(dx * dx + dy * dy + dz * dz);
      double r;
      double g;
      double b;
      double haze;
      if (water) {
        // Turquoise shallows, deepening to a crisp blue sea line that stands
        // out against the pale horizon, as in the reference.
        final shallow = 1 - _smoothstep(10, 30, distance);
        final deep = _Rgb.lerp(
          _Rgb.lerp(
            const _Rgb.hex(0x1D5F92),
            const _Rgb.hex(0x2A73A8),
            _hash2(i, 7),
          ),
          const _Rgb.hex(0x3AA2B4),
          shallow,
        );
        final lit = light.ambientStrength + light.sunStrength * 0.75;
        r = (deep.r + (sky.r - deep.r) * 0.12) * lit;
        g = (deep.g + (sky.g - deep.g) * 0.12) * lit;
        b = (deep.b + (sky.b - deep.b) * 0.12) * lit;
        haze = _smoothstep(35, 72, distance) * 0.38 * light.fogAmount;
      } else {
        final nx = _normals[i3];
        final ny = _normals[i3 + 1];
        final nz = _normals[i3 + 2];
        final ndl = nx * light.sunX + ny * light.sunY + nz * light.sunZ;
        var diffuse = ((ndl + wrap) / (1 + wrap)).clamp(0.0, 1.0);
        if (shadow != null) {
          diffuse *= shadow[i];
        }
        final ao = _ao[i];
        final hemi = ny * 0.5 + 0.5;
        final ambient = light.ambientStrength * ao;
        final ar = (ground.r + (sky.r - ground.r) * hemi) * ambient;
        final ag = (ground.g + (sky.g - ground.g) * hemi) * ambient;
        final ab = (ground.b + (sky.b - ground.b) * hemi) * ambient;
        final direct = diffuse * (0.55 + 0.45 * ao);
        r = _albedo[i3] * (ar + sunR * direct);
        g = _albedo[i3 + 1] * (ag + sunG * direct);
        b = _albedo[i3 + 2] * (ab + sunB * direct);
        final far = math.max(0.0, distance - 9) / 46;
        haze = (1 - math.exp(-far * far * 1.6)) * light.fogAmount;
      }
      if (sat < 1) {
        final grey = r * 0.3 + g * 0.55 + b * 0.15;
        r = grey + (r - grey) * sat;
        g = grey + (g - grey) * sat;
        b = grey + (b - grey) * sat;
      }
      r += (fog.r - r) * haze;
      g += (fog.g - g) * haze;
      b += (fog.b - b) * haze;
      final i4 = i * 4;
      if (glow > 0 && _emissive[i4 + 3] > 0) {
        // Lights cut through the night haze rather than fading into it.
        final k = glow * (1 - haze * 0.4);
        r += (_emissive[i4] - r) * k;
        g += (_emissive[i4 + 1] - g) * k;
        b += (_emissive[i4 + 2] - b) * k;
      }
      out[i3] = srgbToLinear(r);
      out[i3 + 1] = srgbToLinear(g);
      out[i3 + 2] = srgbToLinear(b);
    }
    attribute.needsUpdate = true;
  }
}

// --- Flowing water -------------------------------------------------------------

/// Water whose foam streaks travel along a flow coordinate every frame: the
/// waterfall curtain, rivers and streams. Lighting is baked into a calm and a
/// foam colour per vertex on relight; [animate] only blends between the two.
class _FlowMesh {
  _FlowMesh({
    required this.speed,
    this.alongFrequency = 0.9,
    this.acrossFrequency = 2.4,
    this.foamThreshold = 0.58,
  });

  final double speed;
  final double alongFrequency;
  final double acrossFrequency;
  final double foamThreshold;
  final indices = <int>[];
  final _positions = <double>[];
  final _flow = <double>[]; // (along, across) per vertex
  final _base = <double>[];
  final _foam = <double>[];
  final _bias = <double>[];
  Float32List? _baseLit;
  Float32List? _foamLit;
  three.Float32BufferAttribute? _colorAttribute;
  double _time = 0;
  double _sinceUpdate = 1;

  int get count => _positions.length ~/ 3;

  void vertex(
    double x,
    double y,
    double z, {
    required double along,
    required double across,
    required _Rgb base,
    required _Rgb foam,
    double foamBias = 0,
  }) {
    _positions.addAll([x, y, z]);
    _flow.addAll([along, across]);
    _base.addAll([base.r, base.g, base.b]);
    _foam.addAll([foam.r, foam.g, foam.b]);
    _bias.add(foamBias);
  }

  /// Adds a ribbon from [rows] x [cols] vertices produced by [at], which maps
  /// (along 0..1, across 0..1) to a position and per-vertex colours.
  void ribbon(
    int rows,
    int cols,
    ({
      double x,
      double y,
      double z,
      double along,
      double across,
      _Rgb base,
      _Rgb foam,
      double foamBias,
    })
    Function(double s, double t)
    at,
  ) {
    final start = count;
    for (var row = 0; row < rows; row += 1) {
      for (var col = 0; col < cols; col += 1) {
        final t = col / (cols - 1);
        final p = at(row / (rows - 1), t);
        vertex(
          p.x,
          p.y,
          p.z,
          along: p.along,
          across: p.across,
          base: p.base,
          foam: p.foam,
          foamBias: p.foamBias,
        );
      }
    }
    for (var row = 0; row < rows - 1; row += 1) {
      for (var col = 0; col < cols - 1; col += 1) {
        final a = start + row * cols + col;
        final b = a + 1;
        final c = a + cols;
        final d = c + 1;
        // Both windings: ribbons are seen from above and from the front.
        indices.addAll([a, b, c, b, d, c, a, c, b, b, c, d]);
      }
    }
  }

  three.Mesh createMesh() {
    final geometry = three.BufferGeometry()
      ..setAttributeFromString(
        'position',
        three.Float32BufferAttribute.fromList(_positions, 3),
      );
    final colors = three.Float32BufferAttribute.fromList(
      List<double>.filled(_positions.length, 1),
      3,
    );
    geometry.setAttributeFromString('color', colors);
    geometry.setIndex(indices);
    _colorAttribute = colors;
    return three.Mesh(
      geometry,
      three.MeshBasicMaterial.fromMap({
        'color': 0xFFFFFF,
        'vertexColors': true,
      }),
    )..frustumCulled = false;
  }

  void relight(OutdoorLight light, double eyeX, double eyeY, double eyeZ) {
    final n = count;
    final baseLit = _baseLit ??= Float32List(n * 3);
    final foamLit = _foamLit ??= Float32List(n * 3);
    final fog = _Rgb.hex(light.fog);
    final sky = _Rgb.hex(light.sky);
    final sun = _Rgb.hex(light.sun);
    // Water is lit flatly: sky ambient plus a share of the sun.
    final lr = sky.r * light.ambientStrength + sun.r * light.sunStrength * 0.7;
    final lg = sky.g * light.ambientStrength + sun.g * light.sunStrength * 0.7;
    final lb = sky.b * light.ambientStrength + sun.b * light.sunStrength * 0.7;
    final sat = light.saturation;
    for (var i = 0; i < n; i += 1) {
      final i3 = i * 3;
      final dx = _positions[i3] - eyeX;
      final dy = _positions[i3 + 1] - eyeY;
      final dz = _positions[i3 + 2] - eyeZ;
      final distance = math.sqrt(dx * dx + dy * dy + dz * dz);
      final far = math.max(0.0, distance - 9) / 46;
      final haze = (1 - math.exp(-far * far * 1.6)) * light.fogAmount;
      for (final (source, target) in [(_base, baseLit), (_foam, foamLit)]) {
        var r = source[i3] * lr;
        var g = source[i3 + 1] * lg;
        var b = source[i3 + 2] * lb;
        if (sat < 1) {
          final grey = r * 0.3 + g * 0.55 + b * 0.15;
          r = grey + (r - grey) * sat;
          g = grey + (g - grey) * sat;
          b = grey + (b - grey) * sat;
        }
        target[i3] = srgbToLinear(r + (fog.r - r) * haze);
        target[i3 + 1] = srgbToLinear(g + (fog.g - g) * haze);
        target[i3 + 2] = srgbToLinear(b + (fog.b - b) * haze);
      }
    }
    _sinceUpdate = 1;
    animate(0);
  }

  void animate(double dt) {
    final attribute = _colorAttribute;
    final baseLit = _baseLit;
    final foamLit = _foamLit;
    if (attribute == null || baseLit == null || foamLit == null) {
      return;
    }
    _time += dt;
    _sinceUpdate += dt;
    // ~30 updates a second is plenty for streaming foam.
    if (_sinceUpdate < 1 / 30) {
      return;
    }
    _sinceUpdate = 0;
    final out = attribute.array.toDartList();
    final shift = _time * speed;
    final n = count;
    for (var i = 0; i < n; i += 1) {
      final along = _flow[i * 2] * alongFrequency - shift;
      final across = _flow[i * 2 + 1];
      final noise =
          _valueNoise(across * acrossFrequency, along) * 0.65 +
          _valueNoise(across * acrossFrequency * 2.1 + 17, along * 1.9) * 0.35;
      final f = (_bias[i] + _smoothstep(foamThreshold, 0.86, noise)).clamp(
        0.0,
        1.0,
      );
      final i3 = i * 3;
      out[i3] = baseLit[i3] + (foamLit[i3] - baseLit[i3]) * f;
      out[i3 + 1] = baseLit[i3 + 1] + (foamLit[i3 + 1] - baseLit[i3 + 1]) * f;
      out[i3 + 2] = baseLit[i3 + 2] + (foamLit[i3 + 2] - baseLit[i3 + 2]) * f;
    }
    attribute.needsUpdate = true;
  }
}

// --- Additive glow -------------------------------------------------------------

/// Light that adds onto whatever is behind it: neon reflections on water and
/// sunbeams. Colours are emitted in linear space; black emits nothing, so a
/// beam can fade out along its own vertices.
class _GlowMesh {
  final _positions = <double>[];
  final _colors = <double>[];
  three.MeshBasicMaterial? _material;
  three.Float32BufferAttribute? _positionAttribute;

  int get count => _positions.length ~/ 3;

  void quad(
    (double, double, double) a,
    (double, double, double) b,
    (double, double, double) c,
    (double, double, double) d, {
    required _Rgb near,
    required _Rgb far,
  }) {
    // a-b is the "near" edge, c-d the "far" edge.
    for (final (p, color) in [
      (a, near),
      (b, near),
      (c, far),
      (a, near),
      (c, far),
      (d, far),
    ]) {
      _positions.addAll([p.$1, p.$2, p.$3]);
      _colors.addAll([
        srgbToLinear(color.r),
        srgbToLinear(color.g),
        srgbToLinear(color.b),
      ]);
    }
  }

  three.Mesh createMesh() {
    final positions = three.Float32BufferAttribute.fromList(_positions, 3);
    _positionAttribute = positions;
    final geometry = three.BufferGeometry()
      ..setAttributeFromString('position', positions)
      ..setAttributeFromString(
        'color',
        three.Float32BufferAttribute.fromList(_colors, 3),
      );
    final material = three.MeshBasicMaterial.fromMap({
      'color': 0xFFFFFF,
      'vertexColors': true,
      'transparent': true,
      'opacity': 0.0,
      'depthWrite': false,
      'blending': three.AdditiveBlending,
      'side': three.DoubleSide,
    });
    _material = material;
    return three.Mesh(geometry, material)
      ..frustumCulled = false
      ..renderOrder = 5;
  }

  set intensity(double value) {
    final material = _material;
    if (material == null) {
      return;
    }
    material.opacity = value.clamp(0.0, 1.0);
    material.visible = value > 0.005;
  }

  /// Replaces every position in place (same vertex count).
  void setPositions(List<double> positions) {
    final attribute = _positionAttribute;
    if (attribute == null) {
      return;
    }
    attribute.array.toDartList().setAll(0, positions);
    attribute.needsUpdate = true;
  }
}

class _TreeShadow {
  const _TreeShadow({
    required this.x,
    required this.z,
    required this.radius,
    required this.height,
  });

  final double x;
  final double z;
  final double radius;
  final double height;
}

class _Rgb {
  const _Rgb(this.r, this.g, this.b);

  const _Rgb.hex(int hex)
    : r = ((hex >> 16) & 0xff) / 255,
      g = ((hex >> 8) & 0xff) / 255,
      b = (hex & 0xff) / 255;

  final double r;
  final double g;
  final double b;

  static _Rgb lerp(_Rgb a, _Rgb b, double t) {
    final tt = t.clamp(0.0, 1.0);
    return _Rgb(
      a.r + (b.r - a.r) * tt,
      a.g + (b.g - a.g) * tt,
      a.b + (b.b - a.b) * tt,
    );
  }

  _Rgb scale(double s) => _Rgb(r * s, g * s, b * s);

  /// Small warm/cool shift so neighbouring trees of one grove aren't clones.
  _Rgb shift(double amount) => _Rgb(r * (1 + amount), g, b * (1 - amount));
}

// --- Noise and geometry helpers --------------------------------------------------

final Map<int, List<double>> _icosahedronCache = {};

/// Unit icosahedron as a flat triangle list (x, y, z per corner).
List<double> _unitIcosahedron(int detail) {
  return _icosahedronCache.putIfAbsent(detail, () {
    final geometry = three.IcosahedronGeometry(1, detail);
    final position = geometry.getAttributeFromString('position');
    final list = <double>[];
    for (var i = 0; i < position.count; i += 1) {
      list
        ..add(position.getX(i)!.toDouble())
        ..add(position.getY(i)!.toDouble())
        ..add(position.getZ(i)!.toDouble());
    }
    geometry.dispose();
    return list;
  });
}

(double, double, double) _faceNormal(List<double> p) {
  final ax = p[3] - p[0];
  final ay = p[4] - p[1];
  final az = p[5] - p[2];
  final bx = p[6] - p[0];
  final by = p[7] - p[1];
  final bz = p[8] - p[2];
  var nx = ay * bz - az * by;
  var ny = az * bx - ax * bz;
  var nz = ax * by - ay * bx;
  final len = math.sqrt(nx * nx + ny * ny + nz * nz);
  if (len == 0) {
    return (0, 1, 0);
  }
  nx /= len;
  ny /= len;
  nz /= len;
  return (nx, ny, nz);
}

double _smoothstep(double edge0, double edge1, double x) {
  final t = ((x - edge0) / (edge1 - edge0)).clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

double _hash2(int x, int y) {
  var h = (x * 374761393 + y * 668265263) & 0xffffffff;
  h = ((h ^ (h >> 13)) * 1274126177) & 0xffffffff;
  h ^= h >> 16;
  return (h & 0xffffff) / 0xffffff;
}

double _hash3(int x, int y, int z) => _hash2(x * 31 + z * 7919, y);

double _valueNoise(double x, double y) {
  final x0 = x.floor();
  final y0 = y.floor();
  final fx = x - x0;
  final fy = y - y0;
  final sx = fx * fx * (3 - 2 * fx);
  final sy = fy * fy * (3 - 2 * fy);
  final a = _hash2(x0, y0);
  final b = _hash2(x0 + 1, y0);
  final c = _hash2(x0, y0 + 1);
  final d = _hash2(x0 + 1, y0 + 1);
  final top = a + (b - a) * sx;
  final bottom = c + (d - c) * sx;
  return top + (bottom - top) * sy;
}

double _fbm(double x, double y) {
  var sum = 0.0;
  var amplitude = 0.5;
  var frequency = 1.0;
  var norm = 0.0;
  for (var octave = 0; octave < 4; octave += 1) {
    sum += _valueNoise(x * frequency, y * frequency) * amplitude;
    norm += amplitude;
    amplitude *= 0.5;
    frequency *= 2.03;
  }
  return sum / norm;
}
