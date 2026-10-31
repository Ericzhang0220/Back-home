part of 'outdoor_landscape.dart';

/// A jungle gorge: the house looks across a turquoise pool at a broad
/// waterfall pouring off a mossy cliff, with side ribbons, mist and dense
/// canopy framing the walls. Nothing stands in the line of sight.
class _WaterfallScene extends OutdoorScene {
  _WaterfallScene(super.wallZ) : super._();

  static const double _water = -5.6;
  static const double _floor = -6.9;
  static const double _lipV = 34.0;
  static const double _plateau = 10.0;
  static const double _fallLeft = -6.5;
  static const double _fallRight = 5.5;

  final List<three.Mesh> _mist = [];
  final List<double> _mistPhase = [];
  double _time = 0;

  double _gorgeHalfWidth(double v, double n) => 8.5 + v * 0.16 + (n - 0.5) * 3;

  /// 0 on the gorge floor, 1 on the cliff tops.
  double _cliff(double u, double v) {
    final n = _fbm(u * 0.08 + 3, v * 0.08 - 7);
    final half = _gorgeHalfWidth(v, n);
    final walls =
        _smoothstep(half, half + 4.0, u.abs()) * _smoothstep(4, 10, v);
    // A near-vertical back wall behind the falls, ragged elsewhere.
    final nearFalls =
        1 - _smoothstep(6, 9, (u - (_fallLeft + _fallRight) / 2).abs());
    final backStart = _lipV - 0.2 + (1 - nearFalls) * (n - 0.5) * 3;
    final back = _smoothstep(backStart, backStart + 1.2 + (1 - nearFalls), v);
    return math.max(walls, back);
  }

  double _plateauHeight(double u, double v) {
    final n = _fbm(u * 0.07 + 9, v * 0.07 + 2);
    final flatAroundFalls = _smoothstep(7, 11, (u + 0.5).abs());
    return _plateau +
        n * 3.5 * flatAroundFalls +
        _smoothstep(34, 56, v) * (3 + n * 6);
  }

  @override
  double height(double u, double v) {
    final detail = _fbm(u * 0.2 + 11, v * 0.2 + 5) - 0.5;
    // Grassy rim at the house, then a steep rocky bank into the gorge.
    var floor = -0.4 - (_floor + 0.4).abs() * _smoothstep(2.5, 8.5, v);
    floor += detail * 0.9 * _smoothstep(5, 9, v);
    // Boulder bars break the pool surface, as in the reference.
    final bars = _smoothstep(0.62, 0.76, _fbm(u * 0.16 + 40, v * 0.16 - 12));
    floor += bars * 1.7 * _smoothstep(8, 11, v);
    final cliff = _cliff(u, v);
    return floor + (_plateauHeight(u, v) - floor) * cliff;
  }

  @override
  _Rgb _groundColor(double u, double v, double h, double ny) {
    final patch = _fbm(u * 0.12 + 61, v * 0.12 + 13);
    final fine = _hash2((u * 1.8).round(), (v * 1.8).round() + 401);
    // Wet dark rock streaked with moss on the walls.
    var color = _Rgb.lerp(
      const _Rgb.hex(0x4D4A44),
      const _Rgb.hex(0x6B655B),
      fine,
    );
    final moss = _smoothstep(0.42, 0.62, patch) * (0.55 + ny * 0.45);
    color = _Rgb.lerp(
      color,
      _Rgb.lerp(const _Rgb.hex(0x3F6E28), const _Rgb.hex(0x6E9A35), fine),
      moss,
    );
    // Jungle floor on top of the cliffs and on the rim by the house.
    final top = math.max(_smoothstep(8, 9.5, h), _smoothstep(-1.4, -0.6, h));
    color = _Rgb.lerp(
      color,
      _Rgb.lerp(const _Rgb.hex(0x3E6B26), const _Rgb.hex(0x5E8C2E), fine),
      top * _smoothstep(0.55, 0.8, ny),
    );
    // Pale sunlit stones and gravel at the waterline.
    final shore = 1 - _smoothstep(_water + 0.2, _water + 1.4, h);
    color = _Rgb.lerp(
      color,
      _Rgb.lerp(const _Rgb.hex(0xA3927A), const _Rgb.hex(0x8A7B67), fine),
      shore * 0.8,
    );
    final under = _smoothstep(_water, _water - 0.9, h);
    return _Rgb.lerp(color, const _Rgb.hex(0x2F8C88), under);
  }

  @override
  void _populate() {
    _buildPool();
    _buildFalls();
    final foliage = _LitMesh(wrap: 0.45);
    final solids = _LitMesh(wrap: 0.15);
    _buildRocks(solids);
    _buildJungle(foliage, solids);
    _addMesh(solids);
    _addMesh(foliage);
    _buildMist();
  }

  // --- Water ---------------------------------------------------------------

  void _buildPool() {
    // One sheet across the gorge floor; the terrain hides it wherever the
    // ground rises above the waterline. It drifts gently toward the house.
    final pool = _FlowMesh(
      speed: 0.35,
      alongFrequency: 0.55,
      acrossFrequency: 0.9,
      foamThreshold: 0.72,
    );
    pool.ribbon(48, 40, (s, t) {
      final v = 3 + s * (_lipV - 2);
      final u = -16 + t * 32;
      // Churned white water at the foot of the falls.
      final churn =
          _smoothstep(_lipV - 8, _lipV - 1.5, v) *
          (1 - _smoothstep(1, 5, math.max(0, (u + 0.5).abs() - 6)));
      return (
        x: _worldX(u),
        y: _water,
        z: _worldZ(v),
        along: -v,
        across: u,
        base: _Rgb.lerp(
          const _Rgb.hex(0x2E9C98),
          const _Rgb.hex(0x1F6F78),
          _smoothstep(10, 24, v),
        ),
        foam: const _Rgb.hex(0xE6F4F2),
        foamBias: churn * 0.55,
      );
    });
    _addFlow(pool);
  }

  void _buildFalls() {
    // Long thin streaks: bright water with shadowed bands, as falls read.
    final falls = _FlowMesh(
      speed: 2.4,
      alongFrequency: 0.22,
      acrossFrequency: 2.8,
      foamThreshold: 0.36,
    );
    const top = _plateau + 0.12;
    const drop = top - _water;
    const curtainStart = 0.22; // share of the ribbon that runs over the lip
    // Main curtain: slides across the plateau, bows over the lip and falls,
    // widening slightly toward the pool. The flow coordinate is continuous so
    // streaks pour over the edge.
    falls.ribbon(46, 60, (s, t) {
      final double v;
      final double y;
      final double along;
      if (s < curtainStart) {
        final k = s / curtainStart;
        v = _lipV + 7 * (1 - k);
        y = top;
        along = -(1 - k) * 7;
      } else {
        final k = (s - curtainStart) / (1 - curtainStart);
        v = _lipV - 1.3 * _smoothstep(0, 0.45, k) - 0.25 * k;
        y = top - drop * math.pow(k, 1.15);
        along = k * drop;
      }
      final spread = s < curtainStart ? 0.0 : (s - curtainStart) * 1.2;
      final u = _fallLeft - spread + t * (_fallRight - _fallLeft + spread * 2);
      // Gaps in the curtain show the wet rock behind.
      final edge = math.min(t, 1 - t);
      return (
        x: _worldX(u),
        y: y,
        z: _worldZ(v),
        along: along,
        across: u,
        base: _Rgb.lerp(
          const _Rgb.hex(0x8FAAB2),
          const _Rgb.hex(0x5E7E86),
          1 - _smoothstep(0, 0.1, edge),
        ),
        foam: const _Rgb.hex(0xFAFCFC),
        foamBias: s < curtainStart ? 0.0 : 0.25 + 0.5 * _smoothstep(0.8, 1, s),
      );
    });
    // Narrow side ribbons down the cliff, like the second reference.
    for (final ribbon in const [
      (u: -10.5, width: 1.3, from: 0.15),
      (u: 8.2, width: 0.9, from: 0.3),
    ]) {
      falls.ribbon(30, 6, (s, t) {
        final k = ribbon.from + s * (1 - ribbon.from);
        final y = top - drop * k;
        final u = ribbon.u + (t - 0.5) * ribbon.width * (1 + k * 0.6);
        return (
          x: _worldX(u),
          y: y,
          z: _worldZ(_lipV - 0.2 - k * 0.6),
          along: k * drop,
          across: u,
          base: const _Rgb.hex(0x8EB6BA),
          foam: const _Rgb.hex(0xF0F8F8),
          foamBias: 0.3,
        );
      });
    }
    _addFlow(falls);
  }

  void _buildMist() {
    final unit = _unitIcosahedron(1);
    final random = math.Random(0x3157);
    for (var i = 0; i < 7; i += 1) {
      final positions = <double>[];
      for (final value in unit) {
        positions.add(value);
      }
      final geometry = three.BufferGeometry()
        ..setAttributeFromString(
          'position',
          three.Float32BufferAttribute.fromList(positions, 3),
        );
      final mesh =
          three.Mesh(
              geometry,
              three.MeshBasicMaterial.fromMap({
                'color': 0xFFFFFF,
                'transparent': true,
                'opacity': 0.18,
                'depthWrite': false,
              }),
            )
            ..position.setValues(
              _worldX(-4.5 + i * 1.5 + (random.nextDouble() - 0.5)),
              _water + 0.6 + random.nextDouble() * 1.4,
              _worldZ(_lipV - 2.2 - random.nextDouble() * 2),
            )
            ..scale.setValues(2.4, 1.3, 1.4)
            ..renderOrder = 4;
      _mist.add(mesh);
      _mistPhase.add(random.nextDouble() * math.pi * 2);
      group.add(mesh);
    }
  }

  @override
  void _onRelight(OutdoorLight light) {
    // Mist takes the ambient tint, so it greys in rain and darkens at night.
    final sky = _Rgb.hex(light.sky);
    final level = (light.ambientStrength + light.sunStrength * 0.6).clamp(
      0.0,
      1.2,
    );
    final tint = _Rgb.lerp(const _Rgb.hex(0xFFFFFF), sky, 0.35).scale(level);
    final color = three.Color(
      srgbToLinear(tint.r),
      srgbToLinear(tint.g),
      srgbToLinear(tint.b),
    );
    for (final mesh in _mist) {
      (mesh.material as three.MeshBasicMaterial).color.setFrom(color);
    }
  }

  @override
  void _onAnimate(double dt) {
    _time += dt;
    for (var i = 0; i < _mist.length; i += 1) {
      final wave = math.sin(_time * 0.6 + _mistPhase[i]);
      _mist[i].scale.setValues(2.4 + wave * 0.35, 1.3 + wave * 0.25, 1.4);
      (_mist[i].material as three.MeshBasicMaterial).opacity =
          0.15 + 0.07 * (wave * 0.5 + 0.5);
    }
  }

  // --- Rocks and jungle ------------------------------------------------------

  void _buildRocks(_LitMesh solids) {
    final random = math.Random(0x80C5);
    final unit = _unitIcosahedron(0);
    for (var i = 0; i < 46; i += 1) {
      final u = (random.nextDouble() - 0.5) * 26;
      final v = 7 + random.nextDouble() * (_lipV - 9);
      final h = height(u, v);
      if (_cliff(u, v) > 0.4) {
        continue;
      }
      // Bigger boulders toward the banks, small stones mid-stream.
      final bank = _smoothstep(4, 10, u.abs());
      final size = 0.4 + random.nextDouble() * (0.6 + bank * 1.6);
      _addRock(
        solids,
        unit,
        random,
        _worldX(u),
        math.max(h, _water - 0.3) + size * 0.15,
        _worldZ(v),
        size,
        _Rgb.lerp(
          const _Rgb.hex(0x7A7064),
          const _Rgb.hex(0x5A544C),
          random.nextDouble(),
        ),
        moss: const _Rgb.hex(0x4E7A2C),
      );
    }
  }

  static const _jungle = [
    _Rgb.hex(0x2F6B2A),
    _Rgb.hex(0x3F8030),
    _Rgb.hex(0x5C9A2E),
    _Rgb.hex(0x7DB236),
    _Rgb.hex(0x9CC23A),
    _Rgb.hex(0x2E5F3A),
  ];

  bool _inSightline(double u, double v) {
    // The view from the window to the falls stays open.
    final half = (_fallRight - _fallLeft) / 2 + 3.5 + v * 0.08;
    return (u + 0.5).abs() < half && v < _lipV + 4;
  }

  void _buildJungle(_LitMesh foliage, _LitMesh solids) {
    final random = math.Random(0x1A6E);
    final high = _unitIcosahedron(1);
    final low = _unitIcosahedron(0);
    const spacing = 2.1;
    for (var v = 1.0; v < 54; v += spacing) {
      for (var u = -46.0; u < 46; u += spacing) {
        final tu = u + (random.nextDouble() - 0.5) * spacing * 0.9;
        final tv = v + (random.nextDouble() - 0.5) * spacing * 0.9;
        final accept = random.nextDouble();
        final pick = random.nextDouble();
        final scale = 0.8 + random.nextDouble() * 0.55;
        if (_inSightline(tu, tv) || tv < 1.5) {
          continue;
        }
        final cliff = _cliff(tu, tv);
        final h = height(tu, tv);
        // Rim by the house: only a few trees at the far sides.
        if (tv < 5 && tu.abs() < 9) {
          continue;
        }
        // Gorge floor: occasional bushes by the banks, nothing tall.
        if (cliff < 0.6 && tv > 5) {
          if (cliff < 0.12 &&
              h > _water + 0.6 &&
              accept < 0.25 &&
              tu.abs() > 8) {
            _addBlob(
              foliage,
              low,
              random,
              _worldX(tu),
              h + 0.4,
              _worldZ(tv),
              0.9 * scale,
              0.6 * scale,
              0.9 * scale,
              _jungle[random.nextInt(_jungle.length)],
              bottom: h,
              top: h + 1,
            );
          }
          continue;
        }
        if (accept > 0.86) {
          continue;
        }
        final color =
            _jungle[(_fbm(tu * 0.09 + 5, tv * 0.09) * 1.8 * _jungle.length)
                    .floor() %
                _jungle.length];
        _addBroadleaf(
          foliage,
          solids,
          random,
          _worldX(tu),
          h,
          _worldZ(tv),
          scale * (tv > 30 ? 1.25 : 1.0),
          pick < 0.12 ? const _Rgb.hex(0xB9D43A) : color,
          tv < 18 ? high : low,
          birchChance: 0.05,
          tallChance: 0.45,
        );
      }
    }
    // Ferns and moss clumps clinging to the gorge walls.
    for (var i = 0; i < 160; i += 1) {
      final u = (random.nextDouble() - 0.5) * 50;
      final v = 6 + random.nextDouble() * 24;
      final cliff = _cliff(u, v);
      // Side walls only: the back wall faces the house, so clumps there
      // would hang in front of the rock.
      if (cliff < 0.3 || cliff > 0.75 || v > _lipV - 4 || _inSightline(u, v)) {
        continue;
      }
      final h = height(u, v);
      final size = 0.6 + random.nextDouble() * 0.7;
      _addBlob(
        foliage,
        low,
        random,
        _worldX(u + u.sign * 0.8),
        h - size * 0.25,
        _worldZ(v),
        size * 1.2,
        size * 0.7,
        size,
        _jungle[random.nextInt(_jungle.length)],
        bottom: h - size,
        top: h + size,
      );
    }
  }
}
