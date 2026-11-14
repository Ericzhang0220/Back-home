part of 'outdoor_landscape.dart';

const _warmWindow = _Rgb(1.0, 0.78, 0.42);

/// The island beyond the room's window: golden meadow, groves of autumn,
/// lime and blossom trees, conifers on the hills, a rocky peak, stone walls,
/// a cottage and an old tower, all ringed by sea.
class IslandScene extends OutdoorScene {
  IslandScene({required double wallZ}) : super._(wallZ);

  static const double seaLevel = -4.4;

  // Textured walls, roofs and stonework of the buildings.
  late final _LitMesh _masonry = _LitMesh(
    wrap: 0.15,
    indexed: true,
    cutout: _BuildingAtlas.instance.createTexture(),
  );

  @override
  void _populate() {
    _buildSea();
    final foliage = _LitMesh(wrap: 0.45);
    final solids = _LitMesh(wrap: 0.15);
    _buildStructures(solids);
    _buildRocks(solids);
    _buildTrees(foliage, solids);
    _addMesh(solids);
    _addMesh(foliage);
    _addMesh(_masonry);
  }

  double _pathU(double v) => math.sin(v * 0.11) * 3.2 + v * 0.1;

  /// Island mask radius: < 1 is land, rising to 1 at the coastline.
  double _islandRadius(double u, double v) {
    final ex = u / 46;
    final ez = (v - 14) / 21;
    final warp = (_fbm(u * 0.045 + 7.1, v * 0.045 - 3.3) - 0.5) * 0.34;
    return math.sqrt(ex * ex + ez * ez) + warp;
  }

  double _peakInfluence(double u, double v) {
    final du = (u - 25) / 11;
    final dv = (v - 31) / 9;
    return math.exp(-(du * du + dv * dv) * 1.4);
  }

  @override
  double height(double u, double v) {
    final broad = _fbm(u * 0.05, v * 0.05);
    final detail = _fbm(u * 0.14 + 31, v * 0.14 + 17) - 0.5;
    // The house sits on a rise; the meadow drops away into a valley so the
    // window looks down over the groves, then hills climb toward the back,
    // leaving a low saddle in the centre so the sea shows on the horizon.
    var h = -0.42 - 2.9 * _smoothstep(2.5, 13, v);
    h += detail * 1.2 * _smoothstep(6, 14, v);
    final back = _smoothstep(22, 46, v);
    final sides = _smoothstep(10, 32, u.abs());
    h += back * (sides * (3.0 + broad * 4.0) - (1 - sides) * 0.8);
    h += sides * 2.2 * _smoothstep(4, 20, v);
    // Rocky peak on the right, like the cliff in the reference.
    h += _peakInfluence(u, v) * (13 + broad * 5);
    // Keep the path walkable.
    final pathDistance = (u - _pathU(v)).abs();
    final pathFlatten = 1 - _smoothstep(0.6, 2.4, pathDistance);
    h -= detail * 0.5 * pathFlatten * _smoothstep(2, 9, v);
    final coast = _smoothstep(0.84, 1.02, _islandRadius(u, v));
    h += (seaLevel - 3.0 - h) * coast;
    // Distant forested headlands across the water fill the low band of sky
    // that the room's own sightline through the window sees.
    double headland(double cu, double cv, double ru, double rv, double peak) {
      final du = (u - cu) / ru;
      final dv = (v - cv) / rv;
      return seaLevel - 2 + peak * math.exp(-(du * du + dv * dv) * 1.6);
    }

    return math.max(
      h,
      math.max(
        headland(-8, 53, 17, 6, 7.5 + broad * 2.5),
        headland(19, 51, 11, 5, 6 + broad * 2),
      ),
    );
  }

  @override
  _Rgb _groundColor(double u, double v, double h, double ny) {
    final patch = _fbm(u * 0.09 + 101, v * 0.09 + 47);
    final fine = _hash2((u * 1.25).round(), (v * 1.25).round() + 977);
    // Golden meadow with lime and green patches, as in the reference.
    var color = _Rgb.lerp(
      const _Rgb.hex(0xC48A2C),
      const _Rgb.hex(0xD9A23A),
      fine,
    );
    final green = _smoothstep(0.5, 0.68, patch);
    color = _Rgb.lerp(
      color,
      _Rgb.lerp(const _Rgb.hex(0x9DBF3A), const _Rgb.hex(0x6E9F34), fine),
      green,
    );
    final rust = _smoothstep(0.34, 0.22, patch);
    color = _Rgb.lerp(color, const _Rgb.hex(0xC97B32), rust * 0.75);
    // Hillsides: greener and darker with altitude.
    color = _Rgb.lerp(
      color,
      _Rgb.lerp(const _Rgb.hex(0x5D8C35), const _Rgb.hex(0x7AA03E), fine),
      _smoothstep(1.2, 5.0, h) * 0.85,
    );
    // Bare rock on steep slopes and the peak.
    final rock = math.max(_smoothstep(0.8, 0.62, ny), _smoothstep(7.5, 11, h));
    color = _Rgb.lerp(
      color,
      _Rgb.lerp(const _Rgb.hex(0x8C8A86), const _Rgb.hex(0x6E6D6B), fine),
      rock,
    );
    // Stone path.
    final pathDistance = (u - _pathU(v)).abs();
    final path =
        (1 - _smoothstep(0.4, 0.85, pathDistance)) *
        _smoothstep(5, 8, v) *
        (1 - _smoothstep(30, 34, v));
    color = _Rgb.lerp(
      color,
      _Rgb.lerp(const _Rgb.hex(0xB3A58A), const _Rgb.hex(0x9C9078), fine),
      path,
    );
    // Sand at the waterline, then darker underwater shelf.
    final beach = _smoothstep(seaLevel + 1.0, seaLevel + 0.2, h);
    color = _Rgb.lerp(color, const _Rgb.hex(0xE2D3A0), beach);
    final underwater = _smoothstep(seaLevel, seaLevel - 1.2, h);
    return _Rgb.lerp(color, const _Rgb.hex(0x3F8D9A), underwater);
  }

  void _buildSea() {
    // Larger waves than a river's, and kept from mirroring the sky outright at
    // a distance, so the sea line stays a crisp, deeper blue than the horizon.
    final sea = _MirrorWater(
      level: seaLevel,
      waveScale: 1.8,
      waveStrength: 1.15,
      maxFresnel: 0.72,
    );
    const rings = 26;
    const segments = 96;
    const radius = 72.0;
    final cx = OutdoorScene._eyeX;
    final cz = _eyeZ;
    int point(double x, double z) {
      final depth = seaLevel - height(x - 1, _wallZ - z);
      final shallow = 1 - _smoothstep(0.1, 2.6, depth);
      return sea.vertex(
        x,
        z,
        flowX: 0.06,
        flowZ: 0.03,
        // Surf breaking along the beaches.
        foam: (1 - _smoothstep(0.02, 0.4, depth)) * 0.8,
        tint: _Rgb.lerp(
          const _Rgb.hex(0x1D5F92),
          const _Rgb.hex(0x3AA2B4),
          shallow,
        ),
      );
    }

    final center = point(cx, cz);
    for (var ring = 1; ring <= rings; ring += 1) {
      // Rings bunch up near the window, where the shore needs the detail.
      final t = ring / rings;
      final r = radius * t * t;
      for (var s = 0; s < segments; s += 1) {
        final a = s / segments * math.pi * 2;
        point(cx + math.cos(a) * r, cz + math.sin(a) * r);
      }
    }
    for (var s = 0; s < segments; s += 1) {
      final next = (s + 1) % segments;
      sea.indices.addAll([center, center + 1 + next, center + 1 + s]);
    }
    for (var ring = 1; ring < rings; ring += 1) {
      final inner = center + 1 + (ring - 1) * segments;
      final outer = center + 1 + ring * segments;
      for (var s = 0; s < segments; s += 1) {
        final next = (s + 1) % segments;
        sea.indices.addAll([
          inner + s,
          inner + next,
          outer + s,
          inner + next,
          outer + next,
          outer + s,
        ]);
      }
    }
    _addWater(sea);
  }

  // --- Trees ---------------------------------------------------------------

  static const _palette = [
    _Rgb.hex(0xF28C1E), // orange
    _Rgb.hex(0xEA6A16), // deep orange
    _Rgb.hex(0xE7B623), // golden
    _Rgb.hex(0xB9D92B), // lime
    _Rgb.hex(0x93C437), // yellow-green
    _Rgb.hex(0x59A33A), // green
    _Rgb.hex(0x3F8436), // deep green
  ];
  static const _accents = [
    _Rgb.hex(0xC92A1C), // red
    _Rgb.hex(0xF4A3C8), // blossom pink
    _Rgb.hex(0xDE8BDA), // orchid
    _Rgb.hex(0xD6F05A), // bright lime
  ];

  bool _nearStructure(double u, double v) {
    for (final s in _structureFootprints) {
      final du = u - s.u;
      final dv = v - s.v;
      if (du * du + dv * dv < s.r * s.r) {
        return true;
      }
    }
    return false;
  }

  static const _houses = [
    (
      u: 9.0,
      v: 15.5,
      yaw: -0.35,
      width: 3.6,
      depth: 2.6,
      storeys: 1,
      wall: _Rgb.hex(0xF4EEE2),
      roof: _Rgb.hex(0xD8642A),
      fence: true,
    ),
    (
      u: -7.0,
      v: 13.0,
      yaw: 0.5,
      width: 3.0,
      depth: 2.3,
      storeys: 1,
      wall: _Rgb.hex(0xF0DDB0),
      roof: _Rgb.hex(0xC0532C),
      fence: false,
    ),
    (
      u: -12.0,
      v: 13.0,
      yaw: 0.7,
      width: 3.0,
      depth: 2.4,
      storeys: 2,
      wall: _Rgb.hex(0xF3E6C4),
      roof: _Rgb.hex(0x5E6872),
      fence: false,
    ),
    (
      u: 0.0,
      v: 25.5,
      yaw: 0.4,
      width: 3.2,
      depth: 2.4,
      storeys: 1,
      wall: _Rgb.hex(0xEFCDBF),
      roof: _Rgb.hex(0xD8642A),
      fence: true,
    ),
    (
      u: 8.0,
      v: 27.0,
      yaw: -0.4,
      width: 3.4,
      depth: 2.5,
      storeys: 1,
      wall: _Rgb.hex(0xDCE6DC),
      roof: _Rgb.hex(0xA8432C),
      fence: false,
    ),
    (
      u: -4.5,
      v: 29.0,
      yaw: 0.3,
      width: 3.2,
      depth: 2.5,
      storeys: 2,
      wall: _Rgb.hex(0xF4EEE2),
      roof: _Rgb.hex(0x7A6455),
      fence: false,
    ),
    (
      u: 16.0,
      v: 13.5,
      yaw: -0.6,
      width: 3.0,
      depth: 2.4,
      storeys: 1,
      wall: _Rgb.hex(0xF0D49A),
      roof: _Rgb.hex(0xD06A30),
      fence: false,
    ),
    (
      u: -10.0,
      v: 18.0,
      yaw: 0.6,
      width: 3.2,
      depth: 2.5,
      storeys: 2,
      wall: _Rgb.hex(0xEDEAE4),
      roof: _Rgb.hex(0x56616B),
      fence: false,
    ),
  ];

  static final _structureFootprints = [
    for (final house in _houses)
      (u: house.u, v: house.v, r: math.max(house.width, house.depth) / 2 + 1.9),
    (u: -7.5, v: 23.0, r: 3.4),
    (u: 1.6, v: 21.6, r: 1.8),
  ];

  void _buildTrees(_LitMesh foliage, _LitMesh solids) {
    final random = math.Random(0x7EE5);
    const spacing = 2.35;
    for (var v = 2.5; v < 55; v += spacing) {
      for (var u = -46.0; u < 46; u += spacing) {
        final tu = u + (random.nextDouble() - 0.5) * spacing * 0.9;
        final tv = v + (random.nextDouble() - 0.5) * spacing * 0.9;
        final accept = random.nextDouble();
        final roll = random.nextDouble();
        final h = height(tu, tv);
        if (h < seaLevel + 0.8 || (_islandRadius(tu, tv) > 0.86 && tv < 40)) {
          continue;
        }
        if ((tu - _pathU(tv)).abs() < 2.0 || _nearStructure(tu, tv)) {
          continue;
        }
        // Only a few frame-the-view trees right outside the window.
        if (tv < 7 && tu.abs() < 7) {
          continue;
        }
        // Keep the view straight out of the window open over the valley.
        final openMeadow = tv < 12 && tu.abs() < 3 + tv * 0.4;
        // A narrow vista down the valley keeps a glimpse of the sea.
        final vista = tv < 30 && (tu - _pathU(tv) * 0.6).abs() < 1.2 + tv * 0.1;
        if (openMeadow || vista) {
          continue;
        }
        final peak = _peakInfluence(tu, tv);
        if (peak > 0.55) {
          continue;
        }
        final grove = _fbm(tu * 0.075 + 20, tv * 0.075 - 9);
        final density = 0.18 + 0.78 * _smoothstep(0.36, 0.62, grove);
        if (accept > density) {
          continue;
        }
        final conifer =
            h > 2.8 || tv > 42 || (tv > 34 && roll < 0.75) || peak > 0.3;
        final scale = 0.85 + random.nextDouble() * 0.5;
        final x = _worldX(tu);
        final z = _worldZ(tv);
        if (conifer) {
          _addConifer(foliage, solids, random, x, h, z, scale);
        } else {
          final hueNoise = _fbm(tu * 0.06 + 50, tv * 0.06 + 11);
          final spread = ((hueNoise - 0.5) * 2.8 + 0.5).clamp(0.0, 0.999);
          var color = _palette[(spread * _palette.length).floor()];
          if (roll < 0.14) {
            color = _accents[random.nextInt(_accents.length)];
          }
          _addBroadleaf(foliage, solids, random, x, h, z, scale, color);
        }
      }
    }
  }

  // --- Rocks, walls and buildings --------------------------------------------

  void _buildRocks(_LitMesh solids) {
    final random = math.Random(0x0CC5);
    final unit = _unitIcosahedron(0);
    // Pale sea cliffs and boulders along the coast.
    for (var i = 0; i < 70; i += 1) {
      final a = random.nextDouble() * math.pi * 2;
      // Walk outward from the island centre to the shoreline.
      var u = 0.0;
      var v = 14.0;
      for (var step = 0; step < 60; step += 1) {
        u = math.cos(a) * step * 0.9;
        v = 14 + math.sin(a) * step * 0.9;
        if (_islandRadius(u, v) > 0.9) {
          break;
        }
      }
      if (v < 1.5) {
        continue;
      }
      final h = height(u, v);
      final size = 0.9 + random.nextDouble() * 2.2;
      final tone = _Rgb.lerp(
        const _Rgb.hex(0xD9D5CB),
        const _Rgb.hex(0xA7A39B),
        random.nextDouble(),
      );
      _addRock(
        solids,
        unit,
        random,
        _worldX(u),
        math.max(h, seaLevel - 0.4) + size * 0.25,
        _worldZ(v),
        size,
        tone,
      );
    }
    // Scattered boulders in the meadow.
    for (var i = 0; i < 26; i += 1) {
      final u = (random.nextDouble() - 0.5) * 60;
      final v = 4 + random.nextDouble() * 30;
      if (_islandRadius(u, v) > 0.82 ||
          (u - _pathU(v)).abs() < 1.6 ||
          _nearStructure(u, v) ||
          (v < 8 && u.abs() < 3)) {
        continue;
      }
      final size = 0.35 + random.nextDouble() * 0.7;
      _addRock(
        solids,
        unit,
        random,
        _worldX(u),
        height(u, v) + size * 0.2,
        _worldZ(v),
        size,
        _Rgb.lerp(
          const _Rgb.hex(0x8F8D88),
          const _Rgb.hex(0x6F6E6A),
          random.nextDouble(),
        ),
      );
    }
  }

  void _buildStructures(_LitMesh solids) {
    // A little village strung along the path: cottages in lime-wash and
    // pastel plaster under clay or slate roofs, a well on a small square,
    // and lanterns lighting the way after dark.
    for (final house in _houses) {
      _addCottage(
        solids,
        u: house.u,
        v: house.v,
        yaw: house.yaw,
        width: house.width,
        depth: house.depth,
        storeys: house.storeys,
        wallColor: house.wall,
        roofColor: house.roof,
        fence: house.fence,
      );
    }
    _addTower(solids, u: -7.5, v: 23.0);
    _addWell(solids, u: 1.6, v: 21.6);
    for (final (v, side) in const [
      (11.0, 1.0),
      (15.5, -1.0),
      (20.0, 1.0),
      (24.5, -1.0),
      (29.0, 1.0),
    ]) {
      _addLantern(solids, u: _pathU(v) + side * 1.7, v: v);
    }

    // Low dry-stone walls bordering the meadow and the path.
    final random = math.Random(0x5701);
    void wall(double u0, double v0, double u1, double v1) {
      final length = math.sqrt((u1 - u0) * (u1 - u0) + (v1 - v0) * (v1 - v0));
      final pieces = (length / 1.4).ceil();
      for (var i = 0; i < pieces; i += 1) {
        final t0 = i / pieces;
        final t1 = (i + 1) / pieces;
        final ua = u0 + (u1 - u0) * t0;
        final va = v0 + (v1 - v0) * t0;
        final ub = u0 + (u1 - u0) * t1;
        final vb = v0 + (v1 - v0) * t1;
        final um = (ua + ub) / 2;
        final vm = (va + vb) / 2;
        final segLength = length / pieces;
        final yaw = math.atan2(vb - va, ub - ua);
        final top = 0.45 + random.nextDouble() * 0.12;
        _addBox(
          solids,
          _worldX(um),
          height(um, vm) + top / 2 - 0.12,
          _worldZ(vm),
          width: segLength + 0.05,
          height: top + 0.12,
          depth: 0.42,
          yaw: yaw,
          color: _Rgb.lerp(
            const _Rgb.hex(0x8C877E),
            const _Rgb.hex(0x6E6962),
            random.nextDouble(),
          ),
        );
      }
    }

    wall(-14, 6, -3.2, 7.5);
    wall(4.2, 8.5, 16, 7.0);
    wall(16, 7.0, 20, 18);
    wall(-3.0, 12, -4.2, 21);
    wall(4.8, 20, 12, 25);
    wall(-22, 12, -14, 6);
  }

  /// A stone-footed cottage: lime-washed walls, a tiled roof with deep eaves,
  /// fascia boards and a ridge cap, framed and shuttered windows with flower
  /// boxes, a plank door under a little hood, a stone chimney, and shrubs
  /// growing against the walls.
  void _addCottage(
    _LitMesh mesh, {
    required double u,
    required double v,
    required double yaw,
    required double width,
    required double depth,
    int storeys = 1,
    _Rgb wallColor = const _Rgb.hex(0xF4EEE2),
    _Rgb roofColor = const _Rgb.hex(0xD8642A),
    bool fence = false,
  }) {
    final random = math.Random((u * 31 + v * 7).round());
    final x = _worldX(u);
    final z = _worldZ(v);
    // The floor sits at the highest corner; the footing reaches down to the
    // lowest, so a house on a slope never floats.
    var ground = height(u, v);
    var lowest = ground;
    for (final (du, dv) in [
      (width / 2, depth / 2),
      (-width / 2, depth / 2),
      (width / 2, -depth / 2),
      (-width / 2, -depth / 2),
    ]) {
      final cu = u + du * math.cos(yaw) + dv * math.sin(yaw);
      final cv = v + du * math.sin(yaw) - dv * math.cos(yaw);
      final h = height(cu, cv);
      ground = math.max(ground, h);
      lowest = math.min(lowest, h);
    }
    final painted = _masonry;
    final wallHeight = storeys == 2 ? 3.35 : 2.0;
    const stoneColor = _Rgb.hex(0xC2B49C);
    const timber = _Rgb.hex(0x7A5636);
    const trim = _Rgb.hex(0xF7F3EA);
    final shutter = random.nextBool()
        ? const _Rgb.hex(0x4F7E8C)
        : const _Rgb.hex(0x5E8A4E);
    final c = math.cos(yaw);
    final s = math.sin(yaw);
    (double, double, double) local(double lx, double ly, double lz) =>
        (x + lx * c + lz * s, ly, z - lx * s + lz * c);
    (double, double, double) turn(double lx, double ly, double lz) =>
        (lx * c + lz * s, ly, -lx * s + lz * c);

    /// A quad with its painting laid on in world units along [ua] and [va].
    void face(
      (double, double, double) a,
      (double, double, double) b,
      (double, double, double) cc,
      (double, double, double) d,
      int cell,
      _Rgb color, {
      double shade = 1,
    }) {
      final n = _faceNormal([
        a.$1,
        a.$2,
        a.$3,
        b.$1,
        b.$2,
        b.$3,
        cc.$1,
        cc.$2,
        cc.$3,
      ]);
      final span = _BuildingAtlas.span(cell);
      final (u0, v0, u1, v1) = _BuildingAtlas.instance.cell(cell);
      // Texture axes: along a->b, and along a->d.
      final ex = (b.$1 - a.$1, b.$2 - a.$2, b.$3 - a.$3);
      final ey = (d.$1 - a.$1, d.$2 - a.$2, d.$3 - a.$3);
      final lx = math.sqrt(ex.$1 * ex.$1 + ex.$2 * ex.$2 + ex.$3 * ex.$3);
      final ly = math.sqrt(ey.$1 * ey.$1 + ey.$2 * ey.$2 + ey.$3 * ey.$3);
      final offset = random.nextDouble() * 0.3;
      final base = painted.count;
      for (final (p, fu, fv) in [
        (a, 0.0, 0.0),
        (b, 1.0, 0.0),
        (cc, 1.0, 1.0),
        (d, 0.0, 1.0),
      ]) {
        painted.vertex(
          p.$1,
          p.$2,
          p.$3,
          n.$1,
          n.$2,
          n.$3,
          color.scale(1.18 * shade),
          ao: 1,
        );
        final tu = ((offset + fu * lx / span) % 1.0001).clamp(0.01, 0.99);
        final tv = (fv * ly / span).clamp(0.01, 0.99);
        painted._uvs.addAll([u0 + (u1 - u0) * tu, v0 + (v1 - v0) * tv]);
      }
      painted.indices!.addAll([
        base,
        base + 1,
        base + 2,
        base,
        base + 2,
        base + 3,
      ]);
    }

    /// A box in the cottage's frame, centred at (cx, cy, cz).
    void box(
      double cx,
      double cy,
      double cz,
      double w,
      double h,
      double d,
      int cell,
      _Rgb color,
    ) {
      (double, double, double) p(double sx, double sy, double sz) =>
          local(cx + sx * w / 2, cy + sy * h / 2, cz + sz * d / 2);
      face(p(-1, -1, 1), p(1, -1, 1), p(1, 1, 1), p(-1, 1, 1), cell, color);
      face(p(1, -1, -1), p(-1, -1, -1), p(-1, 1, -1), p(1, 1, -1), cell, color);
      face(p(1, -1, 1), p(1, -1, -1), p(1, 1, -1), p(1, 1, 1), cell, color);
      face(p(-1, -1, -1), p(-1, -1, 1), p(-1, 1, 1), p(-1, 1, -1), cell, color);
      face(p(-1, 1, 1), p(1, 1, 1), p(1, 1, -1), p(-1, 1, -1), cell, color);
    }

    // Stone footing, then the walls standing on it.
    const footing = 0.45;
    final footingLow = lowest - 0.3;
    final footingTop = ground + footing + 0.05;
    box(
      0,
      (footingLow + footingTop) / 2,
      0,
      width + 0.12,
      footingTop - footingLow,
      depth + 0.12,
      _BuildingAtlas.stone,
      stoneColor,
    );
    final wallBase = ground + footing;
    final wallTop = ground + wallHeight;
    box(
      0,
      (wallBase + wallTop) / 2,
      0,
      width,
      wallTop - wallBase,
      depth,
      _BuildingAtlas.plaster,
      wallColor,
    );
    // Timber corner posts.
    for (final sx in const [-1.0, 1.0]) {
      for (final sz in const [-1.0, 1.0]) {
        box(
          sx * (width / 2 - 0.04),
          (wallBase + wallTop) / 2,
          sz * (depth / 2 - 0.04),
          0.14,
          wallTop - wallBase,
          0.14,
          _BuildingAtlas.wood,
          timber,
        );
      }
    }
    // Gable ends, plastered.
    const roofRise = 1.3;
    final ridgeY = wallTop + roofRise;
    for (final side in const [-1.0, 1.0]) {
      final lx = side * width / 2;
      final a = local(lx, wallTop, side * depth / 2);
      final b = local(lx, wallTop, -side * depth / 2);
      final apex = local(lx, ridgeY - 0.06, 0);
      face(a, b, apex, apex, _BuildingAtlas.plaster, wallColor);
      // A round attic vent in each gable.
      final vent = local(lx + side * 0.02, wallTop + roofRise * 0.42, 0);
      _addBox(
        mesh,
        vent.$1,
        vent.$2,
        vent.$3,
        width: 0.06,
        height: 0.3,
        depth: 0.3,
        yaw: yaw,
        color: const _Rgb.hex(0x3A3430),
        emissive: _warmWindow.scale(0.6),
      );
    }

    // Roof: two thick tiled slabs with deep eaves, boards along the edges and
    // a ridge cap.
    final eaveOut = 0.32;
    final halfW = width / 2 + 0.28;
    final halfD = depth / 2 + eaveOut;
    final drop = roofRise * eaveOut / (depth / 2);
    for (final side in const [1.0, -1.0]) {
      final eaveY = wallTop - drop;
      final low = side * halfD;
      final shade = side > 0 ? 1.0 : 0.9;
      // Tiles, from ridge to eave.
      face(
        local(halfW * side, ridgeY + 0.12, 0),
        local(-halfW * side, ridgeY + 0.12, 0),
        local(-halfW * side, eaveY + 0.12, low),
        local(halfW * side, eaveY + 0.12, low),
        _BuildingAtlas.tiles,
        roofColor,
        shade: shade,
      );
      // Underside of the eaves, in shadow.
      face(
        local(-halfW * side, eaveY, low),
        local(-halfW * side, ridgeY - 0.02, 0),
        local(halfW * side, ridgeY - 0.02, 0),
        local(halfW * side, eaveY, low),
        _BuildingAtlas.wood,
        timber,
        shade: 0.55,
      );
      // Fascia along the eave.
      face(
        local(-halfW * side, eaveY - 0.02, low + side * 0.01),
        local(halfW * side, eaveY - 0.02, low + side * 0.01),
        local(halfW * side, eaveY + 0.16, low + side * 0.01),
        local(-halfW * side, eaveY + 0.16, low + side * 0.01),
        _BuildingAtlas.wood,
        timber,
      );
      // Barge boards up each gable edge.
      for (final end in const [-1.0, 1.0]) {
        final ex = end * (halfW + 0.01);
        final a = local(ex, eaveY - 0.02, low);
        final b = local(ex, ridgeY - 0.02, 0);
        final up = turn(0, 0.18, 0);
        final first = end * side > 0 ? a : b;
        final second = end * side > 0 ? b : a;
        face(
          first,
          second,
          (second.$1 + up.$1, second.$2 + up.$2, second.$3 + up.$3),
          (first.$1 + up.$1, first.$2 + up.$2, first.$3 + up.$3),
          _BuildingAtlas.wood,
          timber,
        );
      }
    }
    box(
      0,
      ridgeY + 0.14,
      0,
      halfW * 2 + 0.04,
      0.12,
      0.2,
      _BuildingAtlas.tiles,
      roofColor.scale(0.85),
    );

    // Windows: recessed glass with a crossbar, a white frame and sill,
    // shutters open to either side, and a box of flowers.
    void window(double lx, double ly, double lz, double facing) {
      (double, double, double) at(double ax, double ay, double out) {
        // Along the wall, up, and out from it, for a wall facing +z or -z
        // (facing = ±1) or +x / -x (facing = ±2).
        return switch (facing) {
          1.0 => local(lx + ax, ly + ay, lz + out),
          -1.0 => local(lx - ax, ly + ay, lz - out),
          2.0 => local(lx + out, ly + ay, lz - ax),
          _ => local(lx - out, ly + ay, lz + ax),
        };
      }

      final wallYaw =
          yaw +
          switch (facing) {
            1.0 => 0.0,
            -1.0 => math.pi,
            2.0 => math.pi / 2,
            _ => -math.pi / 2,
          };
      final glass = at(0, 0, 0.01);
      _addBox(
        mesh,
        glass.$1,
        glass.$2,
        glass.$3,
        width: 0.48,
        height: 0.58,
        depth: 0.04,
        yaw: wallYaw,
        color: const _Rgb.hex(0x33424F),
        emissive: _warmWindow,
      );
      for (final bar in [(0.0, 0.0, 0.035, 0.58), (0.0, 0.03, 0.48, 0.035)]) {
        final p = at(bar.$1, bar.$2, 0.04);
        _addBox(
          mesh,
          p.$1,
          p.$2,
          p.$3,
          width: bar.$3,
          height: bar.$4,
          depth: 0.03,
          yaw: wallYaw,
          color: trim,
        );
      }
      for (final edge in [
        (-0.27, 0.0, 0.06, 0.7),
        (0.27, 0.0, 0.06, 0.7),
        (0.0, 0.32, 0.6, 0.06),
      ]) {
        final p = at(edge.$1, edge.$2, 0.05);
        _addBox(
          mesh,
          p.$1,
          p.$2,
          p.$3,
          width: edge.$3,
          height: edge.$4,
          depth: 0.08,
          yaw: wallYaw,
          color: trim,
        );
      }
      final sill = at(0, -0.34, 0.08);
      _addBox(
        mesh,
        sill.$1,
        sill.$2,
        sill.$3,
        width: 0.7,
        height: 0.07,
        depth: 0.18,
        yaw: wallYaw,
        color: trim,
      );
      for (final side in const [-1.0, 1.0]) {
        final p = at(side * 0.5, 0, 0.06);
        _addBox(
          mesh,
          p.$1,
          p.$2,
          p.$3,
          width: 0.24,
          height: 0.66,
          depth: 0.04,
          yaw: wallYaw,
          color: shutter,
        );
        for (final slat in const [-0.2, 0.0, 0.2]) {
          final q = at(side * 0.5, slat, 0.09);
          _addBox(
            mesh,
            q.$1,
            q.$2,
            q.$3,
            width: 0.2,
            height: 0.03,
            depth: 0.02,
            yaw: wallYaw,
            color: shutter.scale(0.75),
          );
        }
      }
      final planter = at(0, -0.45, 0.14);
      _addBox(
        mesh,
        planter.$1,
        planter.$2,
        planter.$3,
        width: 0.62,
        height: 0.14,
        depth: 0.16,
        yaw: wallYaw,
        color: timber,
      );
      for (var f = 0; f < 7; f += 1) {
        final p = at(
          -0.26 + f * 0.087,
          -0.34 + random.nextDouble() * 0.04,
          0.15,
        );
        _addBox(
          mesh,
          p.$1,
          p.$2,
          p.$3,
          width: 0.07,
          height: 0.07,
          depth: 0.07,
          yaw: wallYaw + f,
          color: f.isEven ? const _Rgb.hex(0xD8344A) : const _Rgb.hex(0x4E8A34),
        );
      }
    }

    for (var storey = 0; storey < storeys; storey += 1) {
      final windowY = ground + 1.25 + storey * 1.35;
      final front = storey == 0
          ? [-width * 0.29, width * 0.29]
          : [-width * 0.3, 0.0, width * 0.3];
      for (final lx in front) {
        window(lx, windowY, depth / 2, 1);
      }
      window(0, windowY, -depth / 2, -1);
      window(width / 2, windowY, 0, 2);
      window(-width / 2, windowY, 0, -2);
    }

    // Plank door in a frame, a stone step, and a little hood above it.
    face(
      local(-0.29, ground + footing, depth / 2 + 0.02),
      local(0.29, ground + footing, depth / 2 + 0.02),
      local(0.29, ground + 1.55, depth / 2 + 0.02),
      local(-0.29, ground + 1.55, depth / 2 + 0.02),
      _BuildingAtlas.wood,
      const _Rgb.hex(0x6B4A33),
    );
    for (final edge in [(-0.33, 0.07, 1.15), (0.33, 0.07, 1.15)]) {
      box(
        edge.$1,
        ground + footing + 0.55,
        depth / 2 + 0.03,
        edge.$2,
        edge.$3,
        0.06,
        _BuildingAtlas.wood,
        timber,
      );
    }
    box(
      0,
      ground + 1.6,
      depth / 2 + 0.03,
      0.74,
      0.08,
      0.06,
      _BuildingAtlas.wood,
      timber,
    );
    box(
      0,
      ground + footing - 0.05,
      depth / 2 + 0.22,
      0.9,
      0.12,
      0.36,
      _BuildingAtlas.stone,
      stoneColor.scale(0.9),
    );
    box(
      0,
      ground + 1.82,
      depth / 2 + 0.18,
      0.9,
      0.06,
      0.4,
      _BuildingAtlas.tiles,
      roofColor,
    );
    final handle = local(0.18, ground + 1.0, depth / 2 + 0.05);
    _addBox(
      mesh,
      handle.$1,
      handle.$2,
      handle.$3,
      width: 0.05,
      height: 0.05,
      depth: 0.04,
      yaw: yaw,
      color: const _Rgb.hex(0x2E2A26),
    );

    // A stone chimney with a cap.
    box(
      -width * 0.3,
      ridgeY + 0.1,
      -depth * 0.18,
      0.46,
      1.4,
      0.46,
      _BuildingAtlas.stone,
      stoneColor,
    );
    box(
      -width * 0.3,
      ridgeY + 0.84,
      -depth * 0.18,
      0.56,
      0.08,
      0.56,
      _BuildingAtlas.stone,
      stoneColor.scale(0.8),
    );

    if (fence) {
      // A white picket fence across the front garden, open at the gate.
      final reach = depth / 2 + 1.5;
      for (var lx = -width / 2 - 0.3; lx <= width / 2 + 0.3; lx += 0.2) {
        if (lx.abs() < 0.45) {
          continue;
        }
        final p = local(lx, 0, reach);
        final foot = height(p.$1 - 1, _wallZ - p.$3);
        _addBox(
          mesh,
          p.$1,
          foot + 0.28,
          p.$3,
          width: 0.07,
          height: 0.62,
          depth: 0.05,
          yaw: yaw,
          color: trim,
        );
      }
      for (final side in const [-1.0, 1.0]) {
        final mid = side * (width / 4 + 0.32);
        final p = local(mid, 0, reach - 0.04);
        final foot = height(p.$1 - 1, _wallZ - p.$3);
        for (final rail in const [0.18, 0.42]) {
          _addBox(
            mesh,
            p.$1,
            foot + rail,
            p.$3,
            width: width / 2 - 0.05,
            height: 0.05,
            depth: 0.03,
            yaw: yaw,
            color: trim.scale(0.92),
          );
        }
      }
    }

    // Shrubs growing against the walls.
    for (var i = 0; i < 5; i += 1) {
      final along = (random.nextDouble() - 0.5) * width;
      if (along.abs() < 0.5) {
        continue;
      }
      final p = local(along, 0, depth / 2 + 0.35);
      final bush = height(p.$1 - 1, _wallZ - p.$3);
      _addShrub(
        mesh,
        random,
        p.$1,
        bush,
        p.$3,
        0.45 + random.nextDouble() * 0.25,
        const _Rgb.hex(0x5E9A3C),
      );
    }
  }

  /// A round stone well under a little tiled roof on two posts.
  void _addWell(_LitMesh mesh, {required double u, required double v}) {
    final x = _worldX(u);
    final z = _worldZ(v);
    final ground = height(u, v);
    const stone = _Rgb.hex(0xB7AA92);
    const timber = _Rgb.hex(0x7A5636);
    _addPrism(
      mesh,
      x,
      ground - 0.3,
      z,
      bottomRadius: 0.62,
      topRadius: 0.6,
      height: 1.05,
      sides: 12,
      color: stone,
    );
    _addPrism(
      mesh,
      x,
      ground + 0.72,
      z,
      bottomRadius: 0.66,
      topRadius: 0.66,
      height: 0.08,
      sides: 12,
      color: stone.scale(0.9),
    );
    _addPrism(
      mesh,
      x,
      ground + 0.7,
      z,
      bottomRadius: 0.48,
      topRadius: 0.48,
      height: 0.05,
      sides: 12,
      color: const _Rgb.hex(0x24343E),
    );
    for (final side in const [-1.0, 1.0]) {
      _addBox(
        mesh,
        x + side * 0.55,
        ground + 1.25,
        z,
        width: 0.1,
        height: 1.3,
        depth: 0.1,
        color: timber,
      );
    }
    _addBox(
      mesh,
      x,
      ground + 1.75,
      z,
      width: 1.25,
      height: 0.08,
      depth: 0.08,
      color: timber,
    );
    // Roof: two sloped planes and the bucket hanging under it.
    const roof = _Rgb.hex(0xC85F2E);
    for (final side in const [-1.0, 1.0]) {
      _addQuad(
        mesh,
        (x - 0.8, ground + 2.15, z),
        (x + 0.8, ground + 2.15, z),
        (x + 0.8, ground + 1.72, z + side * 0.62),
        (x - 0.8, ground + 1.72, z + side * 0.62),
        side > 0 ? roof : roof.scale(0.9),
        doubleSided: true,
      );
    }
    _addBox(
      mesh,
      x + 0.1,
      ground + 1.35,
      z,
      width: 0.18,
      height: 0.2,
      depth: 0.18,
      color: const _Rgb.hex(0x6B4A33),
    );
  }

  /// A lantern post along the path, alight at night.
  void _addLantern(_LitMesh mesh, {required double u, required double v}) {
    final x = _worldX(u);
    final z = _worldZ(v);
    final ground = height(u, v);
    const iron = _Rgb.hex(0x2F2D2B);
    _addBox(
      mesh,
      x,
      ground + 0.75,
      z,
      width: 0.08,
      height: 1.6,
      depth: 0.08,
      color: iron,
    );
    _addBox(
      mesh,
      x,
      ground + 1.62,
      z,
      width: 0.2,
      height: 0.24,
      depth: 0.2,
      color: const _Rgb.hex(0x9C8A62),
      emissive: _warmWindow,
    );
    _addBox(
      mesh,
      x,
      ground + 1.78,
      z,
      width: 0.26,
      height: 0.05,
      depth: 0.26,
      color: iron,
    );
  }

  /// A painted quad on the buildings' atlas. Its picture is laid on in world
  /// units along a->b and a->d, from a random spot in the cell.
  void _paintedQuad(
    (double, double, double) a,
    (double, double, double) b,
    (double, double, double) c,
    (double, double, double) d,
    (double, double, double) normal,
    int cell,
    _Rgb color,
    math.Random random,
  ) {
    final span = _BuildingAtlas.span(cell);
    final (u0, v0, u1, v1) = _BuildingAtlas.instance.cell(cell);
    double length((double, double, double) p, (double, double, double) q) {
      final dx = q.$1 - p.$1;
      final dy = q.$2 - p.$2;
      final dz = q.$3 - p.$3;
      return math.sqrt(dx * dx + dy * dy + dz * dz);
    }

    final wide = math.min(length(a, b) / span, 0.96);
    final tall = math.min(length(a, d) / span, 0.96);
    final su = random.nextDouble() * (0.98 - wide);
    final sv = random.nextDouble() * (0.98 - tall);
    final base = _masonry.count;
    for (final (p, fu, fv) in [
      (a, 0.0, 0.0),
      (b, 1.0, 0.0),
      (c, 1.0, 1.0),
      (d, 0.0, 1.0),
    ]) {
      _masonry.vertex(
        p.$1,
        p.$2,
        p.$3,
        normal.$1,
        normal.$2,
        normal.$3,
        color.scale(1.18),
        ao: 1,
      );
      _masonry._uvs.addAll([
        u0 + (u1 - u0) * (0.01 + su + fu * wide),
        v0 + (v1 - v0) * (0.01 + sv + fv * tall),
      ]);
    }
    _masonry.indices!.addAll([
      base,
      base + 1,
      base + 2,
      base,
      base + 2,
      base + 3,
    ]);
  }

  /// A round band of stone (or slate) between two heights and radii.
  void _paintedRing(
    double x,
    double z,
    double y0,
    double y1,
    double r0,
    double r1,
    int sides,
    int cell,
    _Rgb color,
    math.Random random, {
    bool inward = false,
  }) {
    for (var j = 0; j < sides; j += 1) {
      final a0 = j / sides * math.pi * 2;
      final a1 = (j + 1) / sides * math.pi * 2;
      final am = (a0 + a1) / 2;
      final slope = (r0 - r1) / math.max(y1 - y0, 0.01);
      var nx = math.cos(am);
      var ny = slope;
      var nz = math.sin(am);
      final nl = math.sqrt(nx * nx + ny * ny + nz * nz);
      final sign = inward ? -1.0 : 1.0;
      nx = nx / nl * sign;
      ny = ny / nl * sign;
      nz = nz / nl * sign;
      _paintedQuad(
        (x + math.cos(a0) * r0, y0, z + math.sin(a0) * r0),
        (x + math.cos(a1) * r0, y0, z + math.sin(a1) * r0),
        (x + math.cos(a1) * r1, y1, z + math.sin(a1) * r1),
        (x + math.cos(a0) * r1, y1, z + math.sin(a0) * r1),
        (nx, ny, nz),
        cell,
        color.scale(0.94 + random.nextDouble() * 0.1),
        random,
      );
    }
  }

  /// An old stone watchtower: a battered footing, courses of rubble stone
  /// tied by projecting bands, a corbelled walkway with battlements, a slate
  /// cone and a pennant above. Arrow slits and a lit window in stone frames,
  /// an arched door toward the village, and ivy climbing the wall.
  void _addTower(_LitMesh mesh, {required double u, required double v}) {
    final random = math.Random(0x70E4);
    final x = _worldX(u);
    final z = _worldZ(v);
    final ground = height(u, v);
    const wall = _Rgb.hex(0xC4B396);
    const footingStone = _Rgb.hex(0xA3957D);
    const band = _Rgb.hex(0xD8CAB0);
    const slate = _Rgb.hex(0x5A636D);
    const timber = _Rgb.hex(0x6B4A33);
    const sides = 18;
    const bottomRadius = 1.55;
    const topRadius = 1.38;
    final base = ground - 0.2;
    final top = base + 7.4;
    double radiusAt(double y) =>
        bottomRadius + (topRadius - bottomRadius) * ((y - base) / (top - base));

    // Footing, sloped out at the ground.
    _paintedRing(
      x,
      z,
      ground - 0.7,
      ground + 0.75,
      1.82,
      1.6,
      sides,
      _BuildingAtlas.stone,
      footingStone,
      random,
    );
    // The wall, in lifts of stone.
    for (var y = ground + 0.75; y < top - 0.01; y += 1.7) {
      final y1 = math.min(y + 1.7, top);
      _paintedRing(
        x,
        z,
        y,
        y1,
        radiusAt(y),
        radiusAt(y1),
        sides,
        _BuildingAtlas.stone,
        wall,
        random,
      );
    }
    // Projecting string courses.
    for (final y in [ground + 2.9, ground + 5.3]) {
      final r = radiusAt(y) + 0.07;
      _paintedRing(
        x,
        z,
        y,
        y + 0.16,
        r,
        r,
        sides,
        _BuildingAtlas.stone,
        band,
        random,
      );
    }
    // Corbels carrying the walkway, then its parapet with battlements.
    for (var j = 0; j < sides; j += 1) {
      final a = (j + 0.5) / sides * math.pi * 2;
      _addBox(
        mesh,
        x + math.cos(a) * (topRadius + 0.12),
        top - 0.2,
        z + math.sin(a) * (topRadius + 0.12),
        width: 0.2,
        height: 0.36,
        depth: 0.26,
        yaw: -a + math.pi / 2,
        color: band.scale(0.85),
      );
    }
    const walk = topRadius + 0.3;
    _paintedRing(
      x,
      z,
      top,
      top + 0.85,
      walk,
      walk,
      sides,
      _BuildingAtlas.stone,
      wall,
      random,
    );
    _paintedRing(
      x,
      z,
      top,
      top + 0.85,
      walk - 0.2,
      walk - 0.2,
      sides,
      _BuildingAtlas.stone,
      wall.scale(0.8),
      random,
      inward: true,
    );
    // Underside of the overhang, in shadow.
    _paintedRing(
      x,
      z,
      top - 0.02,
      top,
      topRadius,
      walk,
      sides,
      _BuildingAtlas.stone,
      wall.scale(0.6),
      random,
      inward: true,
    );
    for (var j = 0; j < sides; j += 2) {
      final a = (j + 0.5) / sides * math.pi * 2;
      _addBox(
        mesh,
        x + math.cos(a) * (walk - 0.1),
        top + 1.12,
        z + math.sin(a) * (walk - 0.1),
        width: 0.42,
        height: 0.55,
        depth: 0.22,
        yaw: -a + math.pi / 2,
        color: wall.scale(0.97),
      );
    }
    // Slate cone rising from inside the battlements.
    const cone = 10;
    for (var j = 0; j < cone; j += 1) {
      final a0 = j / cone * math.pi * 2;
      final a1 = (j + 1) / cone * math.pi * 2;
      final am = (a0 + a1) / 2;
      final r = walk - 0.3;
      final apex = (x, top + 3.0, z);
      final n = (math.cos(am) * 0.8, 0.6, math.sin(am) * 0.8);
      _paintedQuad(
        (x + math.cos(a0) * r, top + 0.55, z + math.sin(a0) * r),
        (x + math.cos(a1) * r, top + 0.55, z + math.sin(a1) * r),
        apex,
        apex,
        n,
        _BuildingAtlas.tiles,
        slate.scale(0.92 + random.nextDouble() * 0.12),
        random,
      );
    }
    // A pennant on a pole at the very top.
    _addBox(
      mesh,
      x,
      top + 3.45,
      z,
      width: 0.05,
      height: 1.0,
      depth: 0.05,
      color: const _Rgb.hex(0x2F2D2B),
    );
    _addTriangle(mesh, (x, top + 3.9, z), (x, top + 3.6, z), (
      x + 0.7,
      top + 3.78,
      z + 0.05,
    ), const _Rgb.hex(0xB8322A));
    _addTriangle(mesh, (x, top + 3.9, z), (x + 0.7, top + 3.78, z + 0.05), (
      x,
      top + 3.6,
      z,
    ), const _Rgb.hex(0xA02A24));

    // Openings: each a dark recess in a frame of dressed stone.
    void opening(double a, double y, double w, double h, {bool lit = false}) {
      final r = radiusAt(y) + 0.02;
      final px = x + math.cos(a) * r;
      final pz = z + math.sin(a) * r;
      final yaw = -a + math.pi / 2;
      _addBox(
        mesh,
        px,
        y,
        pz,
        width: w,
        height: h,
        depth: 0.1,
        yaw: yaw,
        color: const _Rgb.hex(0x29241F),
        emissive: lit ? _warmWindow : null,
      );
      final fx = x + math.cos(a) * (r + 0.04);
      final fz = z + math.sin(a) * (r + 0.04);
      final c = math.cos(yaw);
      final s = math.sin(yaw);
      for (final side in const [-1.0, 1.0]) {
        _addBox(
          mesh,
          fx + c * side * (w / 2 + 0.07),
          y,
          fz - s * side * (w / 2 + 0.07),
          width: 0.14,
          height: h + 0.14,
          depth: 0.1,
          yaw: yaw,
          color: band,
        );
      }
      _addBox(
        mesh,
        fx,
        y + h / 2 + 0.08,
        fz,
        width: w + 0.34,
        height: 0.16,
        depth: 0.12,
        yaw: yaw,
        color: band,
      );
      _addBox(
        mesh,
        fx,
        y - h / 2 - 0.06,
        fz,
        width: w + 0.24,
        height: 0.1,
        depth: 0.14,
        yaw: yaw,
        color: band,
      );
    }

    // Toward the house, and toward the path to the village.
    for (final a in const [1.2, 1.9, 0.4]) {
      opening(a, ground + 2.0, 0.12, 0.62);
      opening(a + 0.3, ground + 4.3, 0.12, 0.62);
    }
    opening(1.55, ground + 6.3, 0.42, 0.72, lit: true);
    opening(0.8, ground + 6.3, 0.42, 0.72, lit: true);

    // An arched plank door facing the village path, up a stone step.
    const doorAngle = 0.45;
    final dr = bottomRadius + 0.06;
    final dc = math.cos(-doorAngle + math.pi / 2);
    final ds = math.sin(-doorAngle + math.pi / 2);
    final dx = x + math.cos(doorAngle) * dr;
    final dz = z + math.sin(doorAngle) * dr;
    final doorBottom = ground + 0.75;
    _paintedQuad(
      (dx - dc * 0.42, doorBottom, dz + ds * 0.42),
      (dx + dc * 0.42, doorBottom, dz - ds * 0.42),
      (dx + dc * 0.42, doorBottom + 1.35, dz - ds * 0.42),
      (dx - dc * 0.42, doorBottom + 1.35, dz + ds * 0.42),
      (math.cos(doorAngle), 0, math.sin(doorAngle)),
      _BuildingAtlas.wood,
      timber,
      random,
    );
    // Voussoirs round the arch.
    for (var k = 0; k <= 6; k += 1) {
      final t = k / 6 * math.pi;
      final ox = math.cos(t) * 0.52;
      final oy = math.sin(t) * 0.4;
      _addBox(
        mesh,
        dx + dc * ox + math.cos(doorAngle) * 0.04,
        doorBottom + 1.25 + oy,
        dz - ds * ox + math.sin(doorAngle) * 0.04,
        width: 0.2,
        height: 0.18,
        depth: 0.14,
        yaw: -doorAngle + math.pi / 2 + t,
        color: band,
      );
    }
    _addBox(
      mesh,
      dx + math.cos(doorAngle) * 0.3,
      ground + 0.6,
      dz + math.sin(doorAngle) * 0.3,
      width: 1.1,
      height: 0.2,
      depth: 0.5,
      yaw: -doorAngle + math.pi / 2,
      color: footingStone,
    );

    // Ivy climbing the side toward the house, thinning out as it climbs.
    for (var i = 0; i < 46; i += 1) {
      final a = 1.6 + (random.nextDouble() - 0.5) * 2.2;
      final rise = math.pow(random.nextDouble(), 1.8) * 5.2;
      final y = ground + 0.4 + rise;
      final r = radiusAt(y) + 0.1;
      _addLeafCard(
        random,
        x + math.cos(a) * r,
        y,
        z + math.sin(a) * r,
        0.32 + random.nextDouble() * 0.12,
        const _Rgb.hex(0x3E7A32),
        center: (x, y, z),
        reach: r,
        bottom: ground,
        top: ground + 6,
        atlasCell: i.isEven ? _LeafAtlas.denseA : _LeafAtlas.loose,
      );
    }
    _shadows.add(_TreeShadow(x: x, z: z, radius: 1.9, height: 3.4));
  }
}
