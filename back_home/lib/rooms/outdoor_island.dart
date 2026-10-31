part of 'outdoor_landscape.dart';

const _warmWindow = _Rgb(1.0, 0.78, 0.42);

/// The island beyond the room's window: golden meadow, groves of autumn,
/// lime and blossom trees, conifers on the hills, a rocky peak, stone walls,
/// a cottage and an old tower, all ringed by sea.
class IslandScene extends OutdoorScene {
  IslandScene({required double wallZ}) : super._(wallZ);

  static const double seaLevel = -4.4;

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
    final mesh = _LitMesh(wrap: 0, indexed: true, water: true);
    const rings = 22;
    const segments = 72;
    const radius = 72.0;
    final cx = OutdoorScene._eyeX;
    final cz = _eyeZ;
    mesh.vertex(cx, seaLevel, cz, 0, 1, 0, const _Rgb.hex(0x2E7FA6), ao: 1);
    for (var ring = 1; ring <= rings; ring += 1) {
      // Rings bunch up near the window so haze interpolates smoothly.
      final t = ring / rings;
      final r = radius * t * t;
      for (var s = 0; s < segments; s += 1) {
        final a = s / segments * math.pi * 2;
        mesh.vertex(
          cx + math.cos(a) * r,
          seaLevel,
          cz + math.sin(a) * r,
          0,
          1,
          0,
          const _Rgb.hex(0x2E7FA6),
          ao: 1,
        );
      }
    }
    for (var s = 0; s < segments; s += 1) {
      final next = (s + 1) % segments;
      mesh.indices!.addAll([0, 1 + next, 1 + s]);
    }
    for (var ring = 1; ring < rings; ring += 1) {
      final inner = 1 + (ring - 1) * segments;
      final outer = 1 + ring * segments;
      for (var s = 0; s < segments; s += 1) {
        final next = (s + 1) % segments;
        mesh.indices!.addAll([
          inner + s,
          inner + next,
          outer + s,
          inner + next,
          outer + next,
          outer + s,
        ]);
      }
    }
    _addMesh(mesh);
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
    final unitHigh = _unitIcosahedron(1);
    final unitLow = _unitIcosahedron(0);
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
          _addBroadleaf(
            foliage,
            solids,
            random,
            x,
            h,
            z,
            scale,
            color,
            tv < 16 ? unitHigh : unitLow,
          );
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

  void _addCottage(
    _LitMesh mesh, {
    required double u,
    required double v,
    required double yaw,
    required double width,
    required double depth,
  }) {
    final x = _worldX(u);
    final z = _worldZ(v);
    final ground = height(u, v);
    const wallHeight = 2.0;
    const wallColor = _Rgb.hex(0xEEE8DC);
    const roofColor = _Rgb.hex(0xDD6A2A);
    _addBox(
      mesh,
      x,
      ground + wallHeight / 2 - 0.3,
      z,
      width: width,
      height: wallHeight + 0.6,
      depth: depth,
      yaw: yaw,
      color: wallColor,
    );
    // Gable roof as two sloped slabs.
    final c = math.cos(yaw);
    final s = math.sin(yaw);
    const roofRise = 1.25;
    final roofBase = ground + wallHeight;
    final halfW = width / 2 + 0.22;
    final halfD = depth / 2 + 0.25;
    (double, double, double) local(double lx, double ly, double lz) =>
        (x + lx * c + lz * s, ly, z - lx * s + lz * c);
    void quad(
      (double, double, double) a,
      (double, double, double) b,
      (double, double, double) cc,
      (double, double, double) d,
      _Rgb color,
    ) {
      _addQuad(mesh, a, b, cc, d, color);
    }

    final ridgeY = roofBase + roofRise;
    // Front and back slopes.
    quad(
      local(-halfW, roofBase, halfD),
      local(halfW, roofBase, halfD),
      local(halfW, ridgeY, 0),
      local(-halfW, ridgeY, 0),
      roofColor,
    );
    quad(
      local(halfW, roofBase, -halfD),
      local(-halfW, roofBase, -halfD),
      local(-halfW, ridgeY, 0),
      local(halfW, ridgeY, 0),
      roofColor.scale(0.92),
    );
    // Gable ends.
    for (final side in const [-1.0, 1.0]) {
      final lx = side * (width / 2);
      final a = local(lx, roofBase, side * (depth / 2));
      final b = local(lx, roofBase, -side * (depth / 2));
      final apex = local(lx, ridgeY - 0.05, 0);
      _addTriangle(mesh, a, b, apex, wallColor);
    }
    // Windows and door on the front face.
    const windowColor = _Rgb.hex(0x3E4E5C);
    for (final lx in [-width * 0.28, width * 0.28]) {
      final p = local(lx, ground + 1.25, depth / 2 + 0.03);
      _addBox(
        mesh,
        p.$1,
        p.$2,
        p.$3,
        width: 0.5,
        height: 0.55,
        depth: 0.06,
        yaw: yaw,
        color: windowColor,
        emissive: _warmWindow,
      );
    }
    final door = local(0, ground + 0.5, depth / 2 + 0.03);
    _addBox(
      mesh,
      door.$1,
      door.$2,
      door.$3,
      width: 0.55,
      height: 1.1,
      depth: 0.06,
      yaw: yaw,
      color: const _Rgb.hex(0x6B4A33),
    );
    final chimney = local(-width * 0.3, ridgeY - 0.1, -depth * 0.15);
    _addBox(
      mesh,
      chimney.$1,
      chimney.$2,
      chimney.$3,
      width: 0.4,
      height: 1.0,
      depth: 0.4,
      yaw: yaw,
      color: const _Rgb.hex(0x9A8F82),
    );
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
