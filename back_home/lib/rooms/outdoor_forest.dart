part of 'outdoor_landscape.dart';

/// A river valley in deep forest: a sunny meadow and pond below the house, a
/// winding river with gravel bars, tall pines, and layered conifer ridges.
/// Sunbeams and long shadows follow the sun through the day, clouds drift,
/// the river flows and birds cross the sky.
class _ForestScene extends OutdoorScene {
  _ForestScene(super.wallZ) : super._();

  static const double _meadow = -3.2;
  static const double _riverLevel = -3.95;

  final _GlowMesh _beams = _GlowMesh();
  final List<(double, double, double, double)> _beamSpots = [];
  final List<_Bird> _birds = [];
  three.MeshBasicMaterial? _birdMaterial;
  double _time = 0;
  double _flockClock = 0;
  double _flockDirection = 1;
  double _birdVisibility = 1;
  final math.Random _random = math.Random(0xB1D5);

  @override
  double get _groundVSpan => 72;

  @override
  double get _groundUMin => -58;

  @override
  double get _groundUSpan => 116;

  /// Long low-sun shadows; the time of day reads in the shadow direction.
  @override
  double get _shadowReach => 3.4;

  double _riverU(double v) => -3 + 7 * math.sin(v * 0.12 + 0.6) + v * 0.12;

  double _riverHalfWidth(double v) => 1.4 + v * 0.035;

  double _riverDistance(double u, double v) => (u - _riverU(v)).abs();

  double _pond(double u, double v) {
    final du = (u - 9.5) / 2.6;
    final dv = (v - 12.5) / 1.8;
    return 1 - _smoothstep(0.7, 1.0, math.sqrt(du * du + dv * dv));
  }

  @override
  double height(double u, double v) {
    final broad = _fbm(u * 0.045 + 21, v * 0.045 - 8);
    final detail = _fbm(u * 0.18 + 4, v * 0.18 + 2) - 0.5;
    // Bluff at the house, dropping to a broad meadow.
    var h = -0.4 + (_meadow + 0.4) * _smoothstep(2.5, 11, v);
    h += detail * 0.45 * _smoothstep(8, 14, v);
    // Forested ridges rising behind, highest at the sides; a farther ridge
    // line beyond gives the layered look of the reference.
    final sides = _smoothstep(10, 36, u.abs());
    h += _smoothstep(26, 46, v) * (4 + broad * 7 + sides * 5);
    h += _smoothstep(52, 64, v) * (5 + broad * 6);
    h += sides * 3 * _smoothstep(6, 24, v);
    // River channel and pond.
    final half = _riverHalfWidth(v);
    final channel = 1 - _smoothstep(half, half + 1.6, _riverDistance(u, v));
    final valley = 1 - _smoothstep(26, 44, v);
    h +=
        (_riverLevel - 0.7 - h) * channel * math.max(valley, 0.0) +
        (_riverLevel - 0.6 - h) * _pond(u, v);
    return h;
  }

  @override
  _Rgb _groundColor(double u, double v, double h, double ny) {
    final patch = _fbm(u * 0.1 + 33, v * 0.1 + 71);
    final fine = _hash2((u * 1.7).round(), (v * 1.7).round() + 211);
    // Sunlit meadow grass shading into darker forest floor.
    var color = _Rgb.lerp(
      const _Rgb.hex(0x9EBB3A),
      const _Rgb.hex(0xC2C64A),
      fine * 0.6 + _smoothstep(0.45, 0.7, patch) * 0.4,
    );
    color = _Rgb.lerp(
      color,
      _Rgb.lerp(const _Rgb.hex(0x2F4F2A), const _Rgb.hex(0x3D5E2E), fine),
      _smoothstep(-1.5, 2.5, h),
    );
    // Gravel bars on the river's banks.
    final half = _riverHalfWidth(v);
    final bank = 1 - _smoothstep(half + 0.4, half + 2.4, _riverDistance(u, v));
    color = _Rgb.lerp(
      color,
      _Rgb.lerp(const _Rgb.hex(0xB3AA98), const _Rgb.hex(0x948B7B), fine),
      bank * (1 - _smoothstep(26, 38, v)),
    );
    // The pond mirrors the sky.
    return _Rgb.lerp(color, const _Rgb.hex(0x7FA6C0), _pond(u, v));
  }

  @override
  void _populate() {
    _buildRiver();
    final foliage = _LitMesh(wrap: 0.45);
    final solids = _LitMesh(wrap: 0.15);
    _buildForest(foliage, solids);
    _buildRocks(solids);
    _addMesh(solids);
    _addMesh(foliage);
    _buildBeams();
    _buildBirds();
  }

  void _buildRiver() {
    final river = _FlowMesh(
      speed: 1.4,
      alongFrequency: 0.5,
      acrossFrequency: 1.6,
      foamThreshold: 0.64,
    );
    river.ribbon(90, 9, (s, t) {
      final v = 2 + s * 40;
      final half = _riverHalfWidth(v) + 0.6;
      final u = _riverU(v) + (t - 0.5) * 2 * half;
      final edge = math.min(t, 1 - t);
      return (
        x: _worldX(u),
        y: _riverLevel,
        z: _worldZ(v),
        // Flows toward the house.
        along: v,
        across: u,
        base: _Rgb.lerp(
          const _Rgb.hex(0x6F98AC),
          const _Rgb.hex(0x4D7C92),
          _smoothstep(0, 0.4, edge),
        ),
        foam: const _Rgb.hex(0xD8E8EE),
        foamBias: (1 - _smoothstep(0, 0.12, edge)) * 0.35,
      );
    });
    _addFlow(river);
  }

  void _buildForest(_LitMesh foliage, _LitMesh solids) {
    final random = math.Random(0xF0E5);
    final high = _unitIcosahedron(1);
    final low = _unitIcosahedron(0);
    const greens = [
      _Rgb.hex(0x4E8F33),
      _Rgb.hex(0x6DA83A),
      _Rgb.hex(0x8FC23E),
      _Rgb.hex(0x3D7A30),
    ];
    const spacing = 2.0;
    for (var v = 2.0; v < 68; v += spacing) {
      final far = v > 36;
      for (var u = -56.0; u < 56; u += spacing * (far ? 1.15 : 1)) {
        final tu = u + (random.nextDouble() - 0.5) * spacing * 0.9;
        final tv = v + (random.nextDouble() - 0.5) * spacing * 0.9;
        final accept = random.nextDouble();
        final roll = random.nextDouble();
        final scale = 0.85 + random.nextDouble() * 0.5;
        final h = height(tu, tv);
        final half = _riverHalfWidth(tv);
        if (_riverDistance(tu, tv) < half + 1.8 || _pond(tu, tv) > 0.05) {
          continue;
        }
        // The meadow in front stays open, scattered with a few tall pines.
        final meadow = tv < 26 && tu.abs() < 10 + tv * 0.9;
        final forest = _smoothstep(20, 30, tv) + _smoothstep(14, 26, tu.abs());
        if (meadow) {
          if (tv > 9 && accept < 0.05) {
            _addConifer(
              foliage,
              solids,
              random,
              _worldX(tu),
              h,
              _worldZ(tv),
              scale * 0.9,
              slender: 1.9,
              tiers: 4,
            );
          }
          continue;
        }
        if (tv < 5 && tu.abs() < 12) {
          continue;
        }
        if (accept > 0.35 + forest * 0.6) {
          continue;
        }
        // Broadleaf along the river and valley floor, conifers everywhere up.
        if (h < -1.5 && roll < 0.55) {
          _addBroadleaf(
            foliage,
            solids,
            random,
            _worldX(tu),
            h,
            _worldZ(tv),
            scale,
            greens[random.nextInt(greens.length)],
            tv < 18 ? high : low,
            birchChance: 0.1,
          );
        } else {
          _addConifer(
            foliage,
            solids,
            random,
            _worldX(tu),
            h,
            _worldZ(tv),
            scale * (far ? 1.35 : 1.1),
            dark: const _Rgb.hex(0x1F4A2E),
            light: const _Rgb.hex(0x35633A),
            tiers: far ? 2 : 3,
            sides: far ? 5 : 7,
            slender: 1.3,
            castShadow: !far,
          );
        }
      }
    }
  }

  void _buildRocks(_LitMesh solids) {
    final random = math.Random(0x50CC);
    final unit = _unitIcosahedron(0);
    for (var i = 0; i < 30; i += 1) {
      final v = 4 + random.nextDouble() * 24;
      final side = random.nextBool() ? 1 : -1;
      final u = _riverU(v) + side * (_riverHalfWidth(v) + random.nextDouble());
      final size = 0.3 + random.nextDouble() * 0.6;
      _addRock(
        solids,
        unit,
        random,
        _worldX(u),
        height(u, v) + size * 0.2,
        _worldZ(v),
        size,
        _Rgb.lerp(
          const _Rgb.hex(0x8F8A80),
          const _Rgb.hex(0x6B675F),
          random.nextDouble(),
        ),
        moss: const _Rgb.hex(0x5E7E34),
      );
    }
  }

  // --- Sunbeams ------------------------------------------------------------------

  void _buildBeams() {
    // Shafts of light falling through gaps at the forest edge.
    final random = math.Random(0x5EA4);
    for (var i = 0; i < 12; i += 1) {
      final side = i.isEven ? -1 : 1;
      final u = side * (9 + random.nextDouble() * 18);
      final v = 14 + random.nextDouble() * 16;
      _beamSpots.add((
        u,
        v,
        0.7 + random.nextDouble() * 1.3,
        9 + random.nextDouble() * 6,
      ));
      // Placeholder positions; oriented on every relight.
      const zero = (0.0, 0.0, 0.0);
      _beams.quad(
        zero,
        zero,
        zero,
        zero,
        near: const _Rgb.hex(0xFFE2A0),
        far: const _Rgb(0, 0, 0),
      );
    }
    group.add(_beams.createMesh());
  }

  void _orientBeams(OutdoorLight light) {
    final positions = <double>[];
    for (final (u, v, width, length) in _beamSpots) {
      final gx = _worldX(u);
      final gz = _worldZ(v);
      final gy = height(u, v);
      // Beam axis runs from the ground up toward the sun.
      final dx = light.sunX;
      final dy = math.max(light.sunY, 0.25);
      final dz = light.sunZ;
      final dl = math.sqrt(dx * dx + dy * dy + dz * dz);
      final ax = dx / dl;
      final ay = dy / dl;
      final az = dz / dl;
      // Broad side toward the window.
      final vx = OutdoorScene._eyeX - gx;
      final vz = _eyeZ - gz;
      var wx = ay * vz;
      var wy = az * vx - ax * vz;
      var wz = -ay * vx;
      final wl = math.sqrt(wx * wx + wy * wy + wz * wz);
      wx = wx / wl * width / 2;
      wy = wy / wl * width / 2;
      wz = wz / wl * width / 2;
      final tx = gx + ax * length;
      final ty = gy + ay * length;
      final tz = gz + az * length;
      // near edge (bright) on the ground, far edge fades toward the sun.
      final quad = [
        (gx - wx, gy - wy, gz - wz),
        (gx + wx, gy + wy, gz + wz),
        (tx + wx * 2.2, ty + wy * 2.2, tz + wz * 2.2),
        (gx - wx, gy - wy, gz - wz),
        (tx + wx * 2.2, ty + wy * 2.2, tz + wz * 2.2),
        (tx - wx * 2.2, ty - wy * 2.2, tz - wz * 2.2),
      ];
      for (final p in quad) {
        positions.addAll([p.$1, p.$2, p.$3]);
      }
    }
    _beams.setPositions(positions);
  }

  // --- Birds ---------------------------------------------------------------------

  void _buildBirds() {
    final material = three.MeshBasicMaterial.fromMap({
      'color': 0x1E1E24,
      'side': three.DoubleSide,
    });
    _birdMaterial = material;
    // One wing, extending along +z from the body; mirrored for the other.
    final wing = three.BufferGeometry()
      ..setAttributeFromString(
        'position',
        three.Float32BufferAttribute.fromList(const [
          -0.12, 0, 0, //
          0.16, 0, 0,
          -0.05, 0.02, 0.62,
        ], 3),
      );
    for (var i = 0; i < 7; i += 1) {
      final body = three.Group();
      final left = three.Mesh(wing, material);
      final right = three.Mesh(wing, material)..scale.z = -1;
      body
        ..add(left)
        ..add(right)
        ..visible = false;
      group.add(body);
      _birds.add(
        _Bird(
          body: body,
          left: left,
          right: right,
          // V formation offsets.
          offsetAlong: -(i ~/ 2) * 1.3,
          offsetSide: (i.isEven ? 1 : -1) * ((i + 1) ~/ 2) * 1.0,
          phase: _random.nextDouble() * math.pi * 2,
          flapRate: 7 + _random.nextDouble() * 2,
        ),
      );
    }
    _flockClock = -2;
  }

  @override
  void _onRelight(OutdoorLight light) {
    _orientBeams(light);
    // Beams are strongest when the sun is low and the sky is clear.
    _beams.intensity =
        light.clearness * light.daylight * (0.22 + light.twilight * 0.55);
    _birdVisibility = _smoothstep(0.1, 0.35, light.daylight);
    final material = _birdMaterial;
    if (material != null) {
      final level = 0.35 + light.ambientStrength * 0.3;
      material.color.setValues(
        srgbToLinear(0.12 * level),
        srgbToLinear(0.12 * level),
        srgbToLinear(0.14 * level),
      );
    }
  }

  @override
  void _onAnimate(double dt) {
    _time += dt;
    _flockClock += dt;
    // A pass takes ~26 s; then a pause before the next flock crosses.
    const pass = 26.0;
    if (_flockClock > pass + 8 + _random.nextDouble() * 6) {
      _flockClock = 0;
      _flockDirection = _random.nextBool() ? 1 : -1;
    }
    final active = _flockClock >= 0 && _flockClock <= pass;
    final progress = (_flockClock / pass).clamp(0.0, 1.0);
    final leadU = (-46 + progress * 92) * _flockDirection;
    final leadV = 24 + math.sin(progress * math.pi) * 6;
    final leadY = 9 + math.sin(_time * 0.4) * 1.2 + progress * 2;
    for (final bird in _birds) {
      bird.body.visible = active && _birdVisibility > 0.5;
      if (!bird.body.visible) {
        continue;
      }
      final u = leadU - bird.offsetAlong * _flockDirection;
      final v = leadV + bird.offsetSide;
      final bob = math.sin(_time * 1.3 + bird.phase) * 0.25;
      bird.body.position.setValues(
        _worldX(u),
        leadY + bob + bird.offsetSide.abs() * 0.15,
        _worldZ(v),
      );
      bird.body.rotation.y = _flockDirection > 0 ? 0 : math.pi;
      final flap = math.sin(_time * bird.flapRate + bird.phase) * 0.6;
      bird.left.rotation.x = flap;
      bird.right.rotation.x = -flap;
    }
  }
}

class _Bird {
  _Bird({
    required this.body,
    required this.left,
    required this.right,
    required this.offsetAlong,
    required this.offsetSide,
    required this.phase,
    required this.flapRate,
  });

  final three.Group body;
  final three.Mesh left;
  final three.Mesh right;
  final double offsetAlong;
  final double offsetSide;
  final double phase;
  final double flapRate;
}
