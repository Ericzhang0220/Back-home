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
    cutout: _BuildingAtlas.instance.texture,
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

  static const _structureFootprints = [
    (u: 9.0, v: 15.5, r: 4.2),
    (u: -7.5, v: 23.0, r: 3.4),
    (u: -17.0, v: 31.0, r: 3.2),
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
    // Cottage: white walls under a terracotta roof, beside the path.
    _addCottage(solids, u: 9.0, v: 15.5, yaw: -0.35, width: 3.6, depth: 2.6);
    _addCottage(solids, u: -17.0, v: 31.0, yaw: 0.5, width: 3.0, depth: 2.4);
    _addTower(solids, u: -7.5, v: 23.0);

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
  }) {
    final random = math.Random((u * 31 + v * 7).round());
    final x = _worldX(u);
    final z = _worldZ(v);
    final ground = height(u, v);
    final painted = _masonry;
    const wallHeight = 2.0;
    const wallColor = _Rgb.hex(0xF4EEE2);
    const roofColor = _Rgb.hex(0xD8642A);
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
    box(
      0,
      ground - 0.35 + footing / 2 + 0.17,
      0,
      width + 0.12,
      footing + 0.7,
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

    final windowY = ground + 1.25;
    window(-width * 0.29, windowY, depth / 2, 1);
    window(width * 0.29, windowY, depth / 2, 1);
    window(0, windowY, -depth / 2, -1);
    window(width / 2, windowY, 0, 2);
    window(-width / 2, windowY, 0, -2);

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

  void _addTower(_LitMesh mesh, {required double u, required double v}) {
    final x = _worldX(u);
    final z = _worldZ(v);
    final ground = height(u, v);
    const stone = _Rgb.hex(0xC9B998);
    const towerHeight = 7.5;
    _addPrism(
      mesh,
      x,
      ground - 0.4,
      z,
      bottomRadius: 1.55,
      topRadius: 1.35,
      height: towerHeight,
      sides: 8,
      color: stone,
    );
    final top = ground - 0.4 + towerHeight;
    // Crenellations around the top.
    for (var i = 0; i < 8; i += 1) {
      if (i.isOdd) {
        continue;
      }
      final a = (i + 0.5) / 8 * math.pi * 2;
      _addBox(
        mesh,
        x + math.cos(a) * 1.3,
        top + 0.3,
        z + math.sin(a) * 1.3,
        width: 0.55,
        height: 0.6,
        depth: 0.4,
        yaw: -a + math.pi / 2,
        color: stone.scale(0.95),
      );
    }
    // Dark arched openings facing the house.
    const opening = _Rgb.hex(0x2F2A26);
    for (final y in [top - 1.4, top - 3.6]) {
      _addBox(
        mesh,
        x,
        y,
        z + 1.36,
        width: 0.5,
        height: 1.0,
        depth: 0.12,
        color: opening,
        emissive: y < top - 2 ? _warmWindow : null,
      );
    }
    _shadows.add(_TreeShadow(x: x, z: z, radius: 1.8, height: 3.2));
  }
}
