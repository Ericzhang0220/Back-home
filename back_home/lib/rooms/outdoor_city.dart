part of 'outdoor_landscape.dart';

/// A riverside skyline: glass towers by day that light up floor by floor at
/// night with neon crowns and edges, a cable-stayed bridge with an A-shaped
/// pylon, an elevated highway, cars in both directions and neon reflections
/// shimmering on the river.
class _CityScene extends OutdoorScene {
  _CityScene(super.wallZ) : super._();

  static const double _water = -5.2;
  static const double _deckY = -1.6;
  static const double _bank = -3.6;

  static const _neon = [
    _Rgb.hex(0xFF3DB8), // magenta
    _Rgb.hex(0x33E1FF), // cyan
    _Rgb.hex(0x9B5CFF), // violet
    _Rgb.hex(0x3DFF8A), // green
    _Rgb.hex(0xFF4A3D), // red
    _Rgb.hex(0xFFC03D), // gold
  ];

  // Road centreline in (u, v): near-bank viaduct, the bridge, far-bank road.
  static const List<(double, double)> _route = [
    (-46, 6.5),
    (-32, 7.2),
    (-22, 8.6),
    (-16, 10.0),
    (14, 26.0),
    (24, 27.6),
    (46, 28.2),
  ];
  static const int _bridgeStart = 3;
  static const int _bridgeEnd = 4;

  final _GlowMesh _reflections = _GlowMesh();
  final List<_Car> _cars = [];
  late final List<double> _routeLengths = _cumulativeLengths();
  double _time = 0;
  double _night = 0;

  List<double> _cumulativeLengths() {
    final lengths = <double>[0];
    for (var i = 1; i < _route.length; i += 1) {
      final du = _route[i].$1 - _route[i - 1].$1;
      final dv = _route[i].$2 - _route[i - 1].$2;
      lengths.add(lengths.last + math.sqrt(du * du + dv * dv));
    }
    return lengths;
  }

  /// Point and heading along the road, [distance] from its start.
  (double, double, double) _routeAt(double distance) {
    final total = _routeLengths.last;
    final d = ((distance % total) + total) % total;
    var i = 1;
    while (i < _routeLengths.length - 1 && _routeLengths[i] < d) {
      i += 1;
    }
    final t =
        (d - _routeLengths[i - 1]) / (_routeLengths[i] - _routeLengths[i - 1]);
    final a = _route[i - 1];
    final b = _route[i];
    return (
      a.$1 + (b.$1 - a.$1) * t,
      a.$2 + (b.$2 - a.$2) * t,
      math.atan2(b.$2 - a.$2, b.$1 - a.$1),
    );
  }

  double _riverMask(double u, double v) =>
      _smoothstep(10.5, 12.5, v) * (1 - _smoothstep(23.5, 25.5, v));

  @override
  double height(double u, double v) {
    final detail = _fbm(u * 0.15 + 3, v * 0.15 + 9) - 0.5;
    // The house sits on a wooded bluff above the near bank.
    var h =
        -0.4 - 3.2 * _smoothstep(2, 9, v) + detail * 0.8 * _smoothstep(3, 9, v);
    h += (_water - 1.6 - h) * _riverMask(u, v);
    // Far bank: flat embankment, rising gently into the city.
    final far = _smoothstep(24.5, 26, v);
    h += (_bank + _smoothstep(30, 56, v) * 1.2 - h) * far;
    // Hills behind the city close the horizon at the sides.
    h += _smoothstep(26, 50, u.abs()) * _smoothstep(30, 55, v) * 6;
    return h;
  }

  @override
  _Rgb _groundColor(double u, double v, double h, double ny) {
    final fine = _hash2((u * 1.6).round(), (v * 1.6).round() + 59);
    // Paved city blocks on the far bank, green bluff on the near one.
    if (v > 25) {
      return _Rgb.lerp(
        const _Rgb.hex(0x6E6C69),
        const _Rgb.hex(0x857F78),
        fine,
      );
    }
    final grass = _Rgb.lerp(
      const _Rgb.hex(0x4F7A32),
      const _Rgb.hex(0x6C9238),
      fine,
    );
    final stone = _Rgb.lerp(
      const _Rgb.hex(0x8A847A),
      const _Rgb.hex(0x6C665E),
      fine,
    );
    // Stone embankment walls down to the river.
    return _Rgb.lerp(
      grass,
      stone,
      _smoothstep(0.85, 0.6, ny) + _riverMask(u, v),
    );
  }

  @override
  void _populate() {
    _buildRiver();
    final solids = _LitMesh(wrap: 0.2);
    final glass = _LitMesh(wrap: 0.35);
    final foliage = _LitMesh(wrap: 0.45);
    _buildSkyline(glass);
    _buildBridge(solids);
    _buildRoads(solids);
    _buildTrees(foliage, solids);
    _addMesh(glass);
    _addMesh(solids);
    _addMesh(foliage);
    if (_reflections.count > 0) {
      group.add(_reflections.createMesh());
    }
    _buildCars();
  }

  void _buildRiver() {
    final river = _FlowMesh(
      speed: 0.5,
      alongFrequency: 0.35,
      acrossFrequency: 1.2,
      foamThreshold: 0.8,
    );
    river.ribbon(18, 60, (s, t) {
      final u = -60 + t * 120;
      final v = 10.5 + s * 15.5;
      return (
        x: _worldX(u),
        y: _water,
        z: _worldZ(v),
        along: u,
        across: v,
        base: _Rgb.lerp(const _Rgb.hex(0x2B5C78), const _Rgb.hex(0x3A6E86), s),
        foam: const _Rgb.hex(0x8FB6C8),
        foamBias: 0,
      );
    });
    _addFlow(river);
  }

  // --- Skyline -----------------------------------------------------------------

  void _buildSkyline(_LitMesh glass) {
    final random = math.Random(0xC17E);
    const step = 3.4;
    for (var v = 28.0; v < 56; v += step) {
      for (var u = -50.0; u < 50; u += step) {
        if (random.nextDouble() < 0.12) {
          continue;
        }
        final bu = u + (random.nextDouble() - 0.5) * 1.2;
        final bv = v + (random.nextDouble() - 0.5) * 1.2;
        // Keep the far-bank road clear.
        if ((bv - 27.4).abs() < 1.6) {
          continue;
        }
        final cluster = math.exp(-math.pow((bu - 3) / 17, 2).toDouble());
        final noise = _fbm(bu * 0.11 + 7, bv * 0.11 - 3);
        final tall =
            4 +
            cluster * (10 + noise * 16) +
            random.nextDouble() * 5 +
            _smoothstep(30, 50, bv) * 3;
        _addTower(
          glass,
          random,
          bu,
          bv,
          width: 1.9 + random.nextDouble() * 1.4,
          depth: 1.9 + random.nextDouble() * 1.2,
          height: tall,
        );
      }
    }
  }

  void _addTower(
    _LitMesh mesh,
    math.Random random,
    double u,
    double v, {
    required double width,
    required double depth,
    required double height,
  }) {
    final x = _worldX(u);
    final z = _worldZ(v);
    final base = this.height(u, v) - 0.2;
    final wall = [
      const _Rgb.hex(0xC9C3B8),
      const _Rgb.hex(0xB59E7E),
      const _Rgb.hex(0x5A616C),
      const _Rgb.hex(0x8E949C),
    ][random.nextInt(4)];
    final glassTint = _Rgb.lerp(
      const _Rgb.hex(0x6F8DA8),
      const _Rgb.hex(0xA7BED0),
      random.nextDouble(),
    );
    final neon = random.nextDouble() < 0.35
        ? _neon[random.nextInt(_neon.length)]
        : null;
    // Taller towers step back once or twice, like the classic skyline.
    final tiers = height > 16 ? 1 + random.nextInt(3) : 1;
    var tierBase = base;
    var w = width;
    var d = depth;
    for (var tier = 0; tier < tiers; tier += 1) {
      final last = tier == tiers - 1;
      final tierHeight = last
          ? height - (tierBase - base)
          : height * (0.45 + random.nextDouble() * 0.15);
      _addFacades(
        mesh,
        random,
        x,
        tierBase,
        z,
        w,
        d,
        tierHeight,
        wall: wall,
        glass: glassTint,
        neon: neon,
        crown: last,
      );
      tierBase += tierHeight;
      w *= 0.72;
      d *= 0.72;
    }
    if (height > 20 && random.nextDouble() < 0.6) {
      // Spire.
      _addPrism(
        mesh,
        x,
        tierBase,
        z,
        bottomRadius: w * 0.22,
        topRadius: 0.03,
        height: 2.5 + random.nextDouble() * 3,
        sides: 4,
        color: const _Rgb.hex(0xC8CCD2),
        emissive: neon ?? const _Rgb.hex(0xFFF2D8),
      );
    }
    if (u.abs() < 26 && v < 44) {
      _addReflection(x, w, neon ?? const _Rgb.hex(0xFFC27A), height);
    }
  }

  /// Three facades (the back is never seen) as alternating spandrel and
  /// glass bands; each band of glass lights up, or not, at night.
  void _addFacades(
    _LitMesh mesh,
    math.Random random,
    double x,
    double baseY,
    double z,
    double width,
    double depth,
    double height, {
    required _Rgb wall,
    required _Rgb glass,
    required _Rgb? neon,
    required bool crown,
  }) {
    const floorHeight = 0.9;
    final floors = math.max(1, (height / floorHeight).floor());
    final hw = width / 2;
    final hd = depth / 2;
    final faces = [
      // (corner a, corner b) at ground level, wound to face outward.
      ((x - hw, z + hd), (x + hw, z + hd)), // front, toward the house
      ((x + hw, z + hd), (x + hw, z - hd)), // right
      ((x - hw, z - hd), (x - hw, z + hd)), // left
    ];
    final band = height / floors;
    for (var f = 0; f < floors; f += 1) {
      final y0 = baseY + f * band;
      final yGlass = y0 + band * 0.32;
      final y1 = y0 + band;
      final roll = random.nextDouble();
      // Most floors burn warm, some cool white, some are dark.
      final lit = roll < 0.62
          ? _Rgb.lerp(
              const _Rgb.hex(0xFFD08A),
              const _Rgb.hex(0xFFE7B8),
              random.nextDouble(),
            )
          : roll < 0.8
          ? const _Rgb.hex(0xD9E8FF)
          : null;
      final isCrown = crown && neon != null && f == floors - 1;
      for (final (a, b) in faces) {
        _addQuad(
          mesh,
          (a.$1, y0, a.$2),
          (b.$1, y0, b.$2),
          (b.$1, yGlass, b.$2),
          (a.$1, yGlass, a.$2),
          isCrown ? neon.scale(0.8) : wall,
          emissive: isCrown ? neon : null,
        );
        _addQuad(
          mesh,
          (a.$1, yGlass, a.$2),
          (b.$1, yGlass, b.$2),
          (b.$1, y1, b.$2),
          (a.$1, y1, a.$2),
          isCrown ? neon : glass,
          emissive: isCrown ? neon : lit,
        );
      }
    }
    // Roof.
    _addQuad(
      mesh,
      (x - hw, baseY + height, z + hd),
      (x + hw, baseY + height, z + hd),
      (x + hw, baseY + height, z - hd),
      (x - hw, baseY + height, z - hd),
      wall.scale(0.8),
    );
    // Neon corner strips run the full height on the corners facing the house.
    if (neon != null) {
      for (final cx in [x - hw - 0.02, x + hw + 0.02]) {
        _addBeam(
          mesh,
          (cx, baseY, z + hd + 0.02),
          (cx, baseY + height, z + hd + 0.02),
          0.09,
          neon.scale(0.7),
          emissive: neon,
        );
      }
    }
  }

  void _addReflection(double x, double width, _Rgb color, double height) {
    // A soft streak stretching from the far bank toward the viewer.
    final length = 3 + math.min(height, 24) * 0.32;
    final near = _wallZ - (24.5 - length);
    final far = _wallZ - 24.5;
    final hw = width * 0.3;
    _reflections.quad(
      (x - hw, _water + 0.03, far),
      (x + hw, _water + 0.03, far),
      (x + hw * 0.6, _water + 0.03, near),
      (x - hw * 0.6, _water + 0.03, near),
      near: color.scale(0.55),
      far: const _Rgb(0, 0, 0),
    );
  }

  // --- Bridge and roads ----------------------------------------------------------

  void _buildBridge(_LitMesh mesh) {
    final a = _route[_bridgeStart];
    final b = _route[_bridgeEnd];
    final du = b.$1 - a.$1;
    final dv = b.$2 - a.$2;
    final length = math.sqrt(du * du + dv * dv);
    // Unit vectors along and across the deck, in (u, v).
    final au = du / length;
    final av = dv / length;
    final pu = -av;
    final pv = au;
    (double, double, double) at(double along, double across, double y) => (
      _worldX(a.$1 + au * along + pu * across),
      y,
      _worldZ(a.$2 + av * along + pv * across),
    );
    const deckRed = _Rgb.hex(0xFF2D3A);
    const pylonBlue = _Rgb.hex(0x5C6BFF);
    // Pylon: two legs meeting high above the river, lit blue at night.
    final mid = length * 0.48;
    const pylonTop = 13.5;
    for (final side in const [-1.0, 1.0]) {
      _addBeam(
        mesh,
        at(mid, side * 2.4, _water - 0.5),
        at(mid, 0, pylonTop),
        0.5,
        const _Rgb.hex(0xDCDCD8),
        emissive: pylonBlue,
      );
    }
    _addBeam(
      mesh,
      at(mid, 0, pylonTop - 0.2),
      at(mid, 0, pylonTop + 1.6),
      0.35,
      const _Rgb.hex(0xDCDCD8),
      emissive: const _Rgb.hex(0xC9A3FF),
    );
    // Fan of stay cables to both spans.
    for (var i = 1; i <= 7; i += 1) {
      final reach = i / 7.5;
      for (final dir in const [-1.0, 1.0]) {
        final along = mid + dir * reach * mid * 0.95;
        final cableTop = pylonTop - 0.4 - i * 0.55;
        for (final side in const [-1.0, 1.0]) {
          _addBeam(
            mesh,
            at(mid, side * 0.35, cableTop),
            at(along, side * 1.2, _deckY + 0.2),
            0.05,
            const _Rgb.hex(0xE8E8E4),
            emissive: const _Rgb.hex(0xC8D4FF),
          );
        }
      }
    }
    // Deck with a red neon underside, on piers.
    for (var s = 0.0; s < length; s += 2.0) {
      final e = math.min(length, s + 2.0);
      _addQuad(
        mesh,
        at(s, -1.3, _deckY),
        at(e, -1.3, _deckY),
        at(e, 1.3, _deckY),
        at(s, 1.3, _deckY),
        const _Rgb.hex(0x45474C),
        doubleSided: true,
      );
      for (final side in const [-1.0, 1.0]) {
        _addQuad(
          mesh,
          at(s, side * 1.3, _deckY - 0.45),
          at(e, side * 1.3, _deckY - 0.45),
          at(e, side * 1.3, _deckY),
          at(s, side * 1.3, _deckY),
          const _Rgb.hex(0xB9B6AE),
          emissive: deckRed,
          doubleSided: true,
        );
      }
    }
    for (final s in [length * 0.18, length * 0.82]) {
      _addBeam(
        mesh,
        at(s, 0, _water - 0.5),
        at(s, 0, _deckY - 0.4),
        0.9,
        const _Rgb.hex(0xA8A49C),
      );
    }
    _reflections.quad(
      at(0, -1, _water + 0.04),
      at(length, -1, _water + 0.04),
      at(length, 1.6, _water + 0.04),
      at(0, 1.6, _water + 0.04),
      near: deckRed.scale(0.6),
      far: deckRed.scale(0.15),
    );
  }

  void _buildRoads(_LitMesh mesh) {
    for (var i = 1; i < _route.length; i += 1) {
      if (i == _bridgeEnd) {
        continue; // the bridge deck is built separately
      }
      final a = _route[i - 1];
      final b = _route[i];
      final du = b.$1 - a.$1;
      final dv = b.$2 - a.$2;
      final length = math.sqrt(du * du + dv * dv);
      final pu = -dv / length * 1.3;
      final pv = du / length * 1.3;
      final y = i <= _bridgeStart ? _deckY : height(b.$1, b.$2) + 0.08;
      final y0 = i <= _bridgeStart ? _deckY : height(a.$1, a.$2) + 0.08;
      _addQuad(
        mesh,
        (_worldX(a.$1 - pu), y0, _worldZ(a.$2 - pv)),
        (_worldX(b.$1 - pu), y, _worldZ(b.$2 - pv)),
        (_worldX(b.$1 + pu), y, _worldZ(b.$2 + pv)),
        (_worldX(a.$1 + pu), y0, _worldZ(a.$2 + pv)),
        const _Rgb.hex(0x3E4044),
        doubleSided: true,
      );
      if (i <= _bridgeStart) {
        // Viaduct: side barriers with a lit edge, and columns.
        for (final side in const [-1.0, 1.0]) {
          _addQuad(
            mesh,
            (_worldX(a.$1 + pu * side), y0 - 0.5, _worldZ(a.$2 + pv * side)),
            (_worldX(b.$1 + pu * side), y - 0.5, _worldZ(b.$2 + pv * side)),
            (_worldX(b.$1 + pu * side), y + 0.25, _worldZ(b.$2 + pv * side)),
            (_worldX(a.$1 + pu * side), y0 + 0.25, _worldZ(a.$2 + pv * side)),
            const _Rgb.hex(0xBDB9B0),
            emissive: const _Rgb.hex(0x7FD6FF),
            doubleSided: true,
          );
        }
      }
      // Street lamps along every stretch.
      for (var s = 2.0; s < length; s += 4.5) {
        final lu = a.$1 + du / length * s + pu * 1.05;
        final lv = a.$2 + dv / length * s + pv * 1.05;
        final ly = y0 + (y - y0) * (s / length);
        _addBeam(
          mesh,
          (_worldX(lu), ly, _worldZ(lv)),
          (_worldX(lu), ly + 1.1, _worldZ(lv)),
          0.06,
          const _Rgb.hex(0x6E6E6E),
        );
        _addBox(
          mesh,
          _worldX(lu),
          ly + 1.15,
          _worldZ(lv),
          width: 0.22,
          height: 0.1,
          depth: 0.22,
          color: const _Rgb.hex(0xDAD6CC),
          emissive: const _Rgb.hex(0xFFE0A0),
        );
      }
      if (i <= _bridgeStart) {
        for (var s = 0.0; s < length; s += 3.2) {
          final cu = a.$1 + du / length * s;
          final cv = a.$2 + dv / length * s;
          _addBeam(
            mesh,
            (_worldX(cu), height(cu, cv) - 0.2, _worldZ(cv)),
            (_worldX(cu), _deckY - 0.1, _worldZ(cv)),
            0.45,
            const _Rgb.hex(0x9E9A92),
          );
        }
      }
    }
  }

  void _buildTrees(_LitMesh foliage, _LitMesh solids) {
    final random = math.Random(0x7EE7);
    final unit = _unitIcosahedron(1);
    const greens = [
      _Rgb.hex(0x3F7A34),
      _Rgb.hex(0x5C9A3A),
      _Rgb.hex(0x2F6234),
      _Rgb.hex(0x7DAA3A),
    ];
    for (var i = 0; i < 70; i += 1) {
      final u = (random.nextDouble() - 0.5) * 92;
      final v = 1.5 + random.nextDouble() * 9;
      // Trees frame the sides of the bluff; the view across stays open.
      if (u.abs() < 7 + v * 0.6 || (v - 6.5 - u * 0.05).abs() < 1.6) {
        continue;
      }
      _addBroadleaf(
        foliage,
        solids,
        random,
        _worldX(u),
        height(u, v),
        _worldZ(v),
        0.8 + random.nextDouble() * 0.4,
        greens[random.nextInt(greens.length)],
        unit,
        birchChance: 0,
      );
    }
  }

  // --- Traffic --------------------------------------------------------------------

  void _buildCars() {
    final random = math.Random(0xCA25);
    final geometry = three.BoxGeometry(0.8, 0.32, 0.42);
    const paints = [0xE8E8E4, 0x2E3440, 0xB8302A, 0x2E5E9E, 0x9AA0A6, 0xD9B44A];
    for (var i = 0; i < 18; i += 1) {
      final material = three.MeshBasicMaterial.fromMap({'color': 0xFFFFFF});
      final mesh = three.Mesh(geometry, material);
      group.add(mesh);
      _cars.add(
        _Car(
          mesh: mesh,
          material: material,
          paint: _Rgb.hex(paints[random.nextInt(paints.length)]),
          distance: random.nextDouble() * _routeLengths.last,
          speed: 3.2 + random.nextDouble() * 2.2,
          forward: i.isEven,
        ),
      );
    }
    _placeCars();
  }

  void _placeCars() {
    for (final car in _cars) {
      final (u, v, heading) = _routeAt(car.distance);
      // Two lanes, offset either side of the centreline.
      final lane = car.forward ? -0.55 : 0.55;
      final lu = u - math.sin(heading) * lane;
      final lv = v + math.cos(heading) * lane;
      final onViaduct = car.distance <= _routeLengths[_bridgeEnd];
      final y = onViaduct ? _deckY : height(lu, lv) + 0.08;
      car.mesh.position.setValues(_worldX(lu), y + 0.2, _worldZ(lv));
      car.mesh.rotation.y = heading;
    }
  }

  @override
  void _onRelight(OutdoorLight light) {
    _night = light.windowGlow;
    final level = (light.ambientStrength + light.sunStrength * 0.7).clamp(
      0.0,
      1.3,
    );
    for (final car in _cars) {
      // By night only the lights read: headlights coming, tail lights going.
      final lights = car.forward
          ? const _Rgb.hex(0xFF2A1E)
          : const _Rgb.hex(0xFFF0C4);
      final color = _Rgb.lerp(car.paint.scale(level), lights, _night);
      car.material.color.setValues(
        srgbToLinear(color.r),
        srgbToLinear(color.g),
        srgbToLinear(color.b),
      );
    }
    _reflections.intensity = _night;
  }

  @override
  void _onAnimate(double dt) {
    _time += dt;
    for (final car in _cars) {
      car.distance += (car.forward ? 1 : -1) * car.speed * dt;
    }
    _placeCars();
    if (_night > 0) {
      _reflections.intensity = _night * (0.82 + 0.18 * math.sin(_time * 2.1));
    }
  }
}

class _Car {
  _Car({
    required this.mesh,
    required this.material,
    required this.paint,
    required this.distance,
    required this.speed,
    required this.forward,
  });

  final three.Mesh mesh;
  final three.MeshBasicMaterial material;
  final _Rgb paint;
  double distance;
  final double speed;
  final bool forward;
}
