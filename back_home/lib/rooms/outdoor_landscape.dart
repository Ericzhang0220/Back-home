import 'dart:math' as math;
import 'dart:typed_data';

import 'package:three_js/three_js.dart' as three;

/// Lighting for the baked outdoor scene. Every outdoor surface is unlit
/// ([three.MeshBasicMaterial]) with this lighting written into its vertex
/// colours, so the landscape costs a handful of draw calls, never touches the
/// room's own lights or shadow map, and can be relit for a new time of day or
/// weather without rebuilding any geometry.
class OutdoorLight {
  const OutdoorLight({
    required this.sunX,
    required this.sunY,
    required this.sunZ,
    required this.sun,
    required this.sunStrength,
    required this.sky,
    required this.ground,
    required this.ambientStrength,
    required this.fog,
    required this.fogAmount,
    required this.shadowStrength,
    required this.saturation,
    required this.windowGlow,
  });

  /// Unit-ish direction pointing toward the key light (sun or moon).
  final double sunX;
  final double sunY;
  final double sunZ;
  final int sun;
  final double sunStrength;

  /// Hemisphere ambient: light from above and bounce light from below.
  final int sky;
  final int ground;
  final double ambientStrength;

  /// Aerial-perspective haze; matches the sky dome's horizon colour so the
  /// sea and far hills dissolve into the sky without a visible seam.
  final int fog;
  final double fogAmount;

  /// How dark the soft tree shadows on the ground are (0 = none).
  final double shadowStrength;

  /// 1 keeps the painted palette, lower values grey it out (rain/overcast).
  final double saturation;

  /// 0..1 strength of lit cottage windows (night).
  final double windowGlow;
}

/// The island beyond the room's window: golden meadow, groves of autumn,
/// lime and blossom trees, conifers on the hills, a rocky peak, stone walls,
/// a cottage and an old tower, all ringed by sea.
class OutdoorLandscape {
  OutdoorLandscape({required double wallZ}) : _wallZ = wallZ {
    _build();
  }

  final double _wallZ;
  final three.Group group = three.Group();
  final List<_LitMesh> _meshes = [];
  final List<_TreeShadow> _shadows = [];
  late final _LitMesh _groundMesh;
  late final Float32List _groundShadow;
  late final int _groundCols;
  late final int _groundRows;
  late final double _groundStep;
  late final double _groundMinU;
  late final double _groundMinV;

  static const double seaLevel = -4.4;
  static const double _groundSpacing = 0.55;

  // Window-centred coordinates: u runs across the view (0 = window centre),
  // v runs away from the back wall (0 = the wall, positive = outdoors).
  double _worldX(double u) => u + 1.0;
  double _worldZ(double v) => _wallZ - v;

  // Haze is measured from the window, where every outdoor view starts.
  static const double _eyeX = 1.0;
  static const double _eyeY = 2.3;
  double get _eyeZ => _wallZ + 0.6;

  void relight(OutdoorLight light) {
    _updateGroundShadows(light);
    for (final mesh in _meshes) {
      mesh.relight(
        light,
        _eyeX,
        _eyeY,
        _eyeZ,
        shadow: identical(mesh, _groundMesh) ? _groundShadow : null,
      );
    }
  }

  // --- Terrain ---------------------------------------------------------------

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

  void _build() {
    _buildGround();
    _buildSea();
    final foliage = _LitMesh(wrap: 0.45);
    final solids = _LitMesh(wrap: 0.15);
    _buildStructures(solids);
    _buildRocks(solids);
    _buildTrees(foliage, solids);
    _addMesh(solids);
    _addMesh(foliage);
  }

  void _addMesh(_LitMesh mesh) {
    if (mesh.count == 0) {
      return;
    }
    _meshes.add(mesh);
    group.add(mesh.createMesh());
  }

  void _buildGround() {
    _groundStep = _groundSpacing;
    _groundMinU = -54;
    _groundMinV = -4;
    _groundCols = (108 / _groundStep).round() + 1;
    _groundRows = (60 / _groundStep).round() + 1;
    final mesh = _LitMesh(wrap: 0.1, indexed: true);
    final heights = Float64List(_groundCols * _groundRows);
    for (var row = 0; row < _groundRows; row += 1) {
      for (var col = 0; col < _groundCols; col += 1) {
        heights[row * _groundCols + col] = height(
          _groundMinU + col * _groundStep,
          _groundMinV + row * _groundStep,
        );
      }
    }
    double heightAt(int col, int row) =>
        heights[row.clamp(0, _groundRows - 1) * _groundCols +
            col.clamp(0, _groundCols - 1)];

    for (var row = 0; row < _groundRows; row += 1) {
      for (var col = 0; col < _groundCols; col += 1) {
        final u = _groundMinU + col * _groundStep;
        final v = _groundMinV + row * _groundStep;
        final h = heightAt(col, row);
        // Central differences. +v is world -z, hence the flipped z term.
        final dhdu =
            (heightAt(col + 1, row) - heightAt(col - 1, row)) /
            (2 * _groundStep);
        final dhdv =
            (heightAt(col, row + 1) - heightAt(col, row - 1)) /
            (2 * _groundStep);
        var nx = -dhdu;
        var ny = 1.0;
        var nz = dhdv;
        final len = math.sqrt(nx * nx + ny * ny + nz * nz);
        nx /= len;
        ny /= len;
        nz /= len;
        final color = _groundColor(u, v, h, ny);
        mesh.vertex(_worldX(u), h, _worldZ(v), nx, ny, nz, color, ao: 1);
      }
    }
    for (var row = 0; row < _groundRows - 1; row += 1) {
      for (var col = 0; col < _groundCols - 1; col += 1) {
        final a = row * _groundCols + col;
        final b = a + 1;
        final c = a + _groundCols;
        final d = c + 1;
        // Wound for an upward-facing surface (v grows toward world -z).
        mesh.indices!.addAll([a, b, c, b, d, c]);
      }
    }
    _groundShadow = Float32List(_groundCols * _groundRows)
      ..fillRange(0, _groundCols * _groundRows, 1);
    _groundMesh = mesh;
    _addMesh(mesh);
  }

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
    color = _Rgb.lerp(color, const _Rgb.hex(0x3F8D9A), underwater);
    // Painterly grain so close ground doesn't read as a smooth gradient.
    final grain = _hash2(
      (u / _groundSpacing).round(),
      (v / _groundSpacing).round() + 31,
    );
    return color.scale(0.9 + grain * 0.18);
  }

  void _buildSea() {
    final mesh = _LitMesh(wrap: 0, indexed: true, water: true);
    const rings = 22;
    const segments = 72;
    const radius = 72.0;
    final cx = _eyeX;
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

  // --- Trees -----------------------------------------------------------------

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

  void _addBroadleaf(
    _LitMesh foliage,
    _LitMesh solids,
    math.Random random,
    double x,
    double baseY,
    double z,
    double scale,
    _Rgb color,
    List<double> unit,
  ) {
    final tall = random.nextDouble() < 0.3;
    final trunkHeight = (tall ? 1.6 : 1.2) * scale + random.nextDouble() * 0.5;
    final radius = (tall ? 1.15 : 1.45) * scale;
    final birch = random.nextDouble() < 0.15;
    _addPrism(
      solids,
      x,
      baseY - 0.1,
      z,
      bottomRadius: 0.13 * scale,
      topRadius: 0.08 * scale,
      height: trunkHeight + radius * 0.6,
      sides: 5,
      color: birch ? const _Rgb.hex(0xE2DED3) : const _Rgb.hex(0x5B4636),
    );
    final centerY = baseY + trunkHeight + radius * (tall ? 1.15 : 0.75);
    final stretch = tall ? 1.55 : 0.95;
    final bottom = centerY - radius * stretch;
    final top = centerY + radius * stretch;
    void blob(double dx, double dy, double dz, double r, double sy) {
      _addBlob(
        foliage,
        unit,
        random,
        x + dx,
        centerY + dy,
        z + dz,
        r,
        r * sy,
        r,
        color,
        bottom: bottom,
        top: top,
      );
    }

    blob(0, 0, 0, radius, stretch);
    final lobes = 3 + random.nextInt(3);
    for (var i = 0; i < lobes; i += 1) {
      final a = random.nextDouble() * math.pi * 2;
      final spread = radius * (0.55 + random.nextDouble() * 0.25);
      blob(
        math.cos(a) * spread,
        (random.nextDouble() - 0.6) * radius * stretch * 0.7,
        math.sin(a) * spread,
        radius * (0.55 + random.nextDouble() * 0.2),
        stretch * 0.9,
      );
    }
    _shadows.add(
      _TreeShadow(x: x, z: z, radius: radius * 1.25, height: centerY - baseY),
    );
  }

  void _addConifer(
    _LitMesh foliage,
    _LitMesh solids,
    math.Random random,
    double x,
    double baseY,
    double z,
    double scale,
  ) {
    final color = _Rgb.lerp(
      const _Rgb.hex(0x2B5A36),
      const _Rgb.hex(0x3F7038),
      random.nextDouble(),
    );
    final total = (3.4 + random.nextDouble() * 1.6) * scale;
    _addPrism(
      solids,
      x,
      baseY - 0.1,
      z,
      bottomRadius: 0.12 * scale,
      topRadius: 0.08 * scale,
      height: total * 0.35,
      sides: 5,
      color: const _Rgb.hex(0x4A3A2E),
    );
    final tiers = 3;
    for (var tier = 0; tier < tiers; tier += 1) {
      final t = tier / tiers;
      final tierBase = baseY + total * (0.22 + t * 0.42);
      final tierHeight = total * (0.5 - t * 0.08);
      final radius = scale * (1.15 - t * 0.32);
      _addCone(
        foliage,
        random,
        x,
        tierBase,
        z,
        radius,
        tierHeight,
        color,
        aoBase: 0.55 + t * 0.2,
      );
    }
    _shadows.add(
      _TreeShadow(x: x, z: z, radius: scale * 1.05, height: total * 0.55),
    );
  }

  void _addBlob(
    _LitMesh mesh,
    List<double> unit,
    math.Random random,
    double cx,
    double cy,
    double cz,
    double rx,
    double ry,
    double rz,
    _Rgb color, {
    required double bottom,
    required double top,
  }) {
    final hueShift = (random.nextDouble() - 0.5) * 0.12;
    final base = color.shift(hueShift);
    for (var i = 0; i < unit.length; i += 9) {
      // Shared corners displace identically, so the lumpy blob stays closed.
      final p = List<double>.filled(9, 0);
      for (var k = 0; k < 3; k += 1) {
        final ux = unit[i + k * 3];
        final uy = unit[i + k * 3 + 1];
        final uz = unit[i + k * 3 + 2];
        final bump =
            0.82 +
            0.36 *
                _hash3(
                  (ux * 997).round() + (cx * 13).round(),
                  (uy * 997).round() + (cy * 13).round(),
                  (uz * 997).round() + (cz * 13).round(),
                );
        p[k * 3] = cx + ux * rx * bump;
        p[k * 3 + 1] = cy + uy * ry * bump;
        p[k * 3 + 2] = cz + uz * rz * bump;
      }
      final face = _faceNormal(p);
      // Leafy speckle: each facet gets its own small brightness step.
      final speckle = 0.86 + random.nextDouble() * 0.24;
      final faceColor = base.scale(speckle);
      for (var k = 0; k < 3; k += 1) {
        final ux = unit[i + k * 3];
        final uy = unit[i + k * 3 + 1];
        final uz = unit[i + k * 3 + 2];
        // Blend the faceted and the round normal: chunky but not glassy.
        var nx = face.$1 * 0.55 + ux * 0.45;
        var ny = face.$2 * 0.55 + uy * 0.45;
        var nz = face.$3 * 0.55 + uz * 0.45;
        final len = math.sqrt(nx * nx + ny * ny + nz * nz);
        nx /= len;
        ny /= len;
        nz /= len;
        final y = p[k * 3 + 1];
        final heightT = ((y - bottom) / (top - bottom)).clamp(0.0, 1.0);
        // Self-shadowing: the underside and the core of the canopy are dark.
        final ao = 0.5 + 0.5 * math.pow(heightT, 0.7);
        mesh.vertex(
          p[k * 3],
          y,
          p[k * 3 + 2],
          nx,
          ny,
          nz,
          faceColor,
          ao: ao.toDouble(),
        );
      }
    }
  }

  void _addCone(
    _LitMesh mesh,
    math.Random random,
    double x,
    double baseY,
    double z,
    double radius,
    double height,
    _Rgb color, {
    required double aoBase,
  }) {
    const sides = 7;
    final twist = random.nextDouble() * math.pi;
    final slope = radius / height;
    for (var s = 0; s < sides; s += 1) {
      final a0 = twist + s / sides * math.pi * 2;
      final a1 = twist + (s + 1) / sides * math.pi * 2;
      final am = (a0 + a1) / 2;
      final nLen = math.sqrt(1 + slope * slope);
      final nx = math.cos(am) / nLen;
      final ny = slope / nLen;
      final nz = math.sin(am) / nLen;
      final faceColor = color.scale(0.9 + random.nextDouble() * 0.2);
      mesh.vertex(
        x + math.cos(a0) * radius,
        baseY,
        z + math.sin(a0) * radius,
        nx,
        ny,
        nz,
        faceColor,
        ao: aoBase,
      );
      mesh.vertex(x, baseY + height, z, nx, ny, nz, faceColor, ao: 1);
      mesh.vertex(
        x + math.cos(a1) * radius,
        baseY,
        z + math.sin(a1) * radius,
        nx,
        ny,
        nz,
        faceColor,
        ao: aoBase,
      );
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

  void _addRock(
    _LitMesh mesh,
    List<double> unit,
    math.Random random,
    double x,
    double y,
    double z,
    double size,
    _Rgb color,
  ) {
    final sx = size * (0.9 + random.nextDouble() * 0.6);
    final sy = size * (0.5 + random.nextDouble() * 0.35);
    final sz = size * (0.8 + random.nextDouble() * 0.5);
    final yaw = random.nextDouble() * math.pi;
    final c = math.cos(yaw);
    final s = math.sin(yaw);
    for (var i = 0; i < unit.length; i += 9) {
      final p = List<double>.filled(9, 0);
      for (var k = 0; k < 3; k += 1) {
        final ux = unit[i + k * 3];
        final uy = unit[i + k * 3 + 1];
        final uz = unit[i + k * 3 + 2];
        final bump =
            0.8 +
            0.4 *
                _hash3(
                  (ux * 991).round() + (x * 7).round(),
                  (uy * 991).round(),
                  (uz * 991).round() + (z * 7).round(),
                );
        final lx = ux * sx * bump;
        final lz = uz * sz * bump;
        p[k * 3] = x + lx * c - lz * s;
        p[k * 3 + 1] = y + uy * sy * bump;
        p[k * 3 + 2] = z + lx * s + lz * c;
      }
      final n = _faceNormal(p);
      final faceColor = color.scale(0.92 + random.nextDouble() * 0.12);
      for (var k = 0; k < 3; k += 1) {
        mesh.vertex(
          p[k * 3],
          p[k * 3 + 1],
          p[k * 3 + 2],
          n.$1,
          n.$2,
          n.$3,
          faceColor,
          ao: 0.7 + 0.3 * (unit[i + k * 3 + 1] * 0.5 + 0.5),
        );
      }
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
        glow: true,
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
        glow: y < top - 2,
      );
    }
    _shadows.add(_TreeShadow(x: x, z: z, radius: 1.8, height: 3.2));
  }

  // --- Geometry primitives ---------------------------------------------------

  void _addPrism(
    _LitMesh mesh,
    double x,
    double baseY,
    double z, {
    required double bottomRadius,
    required double topRadius,
    required double height,
    required int sides,
    required _Rgb color,
  }) {
    for (var s = 0; s < sides; s += 1) {
      final a0 = s / sides * math.pi * 2;
      final a1 = (s + 1) / sides * math.pi * 2;
      final b0 = (
        x + math.cos(a0) * bottomRadius,
        baseY,
        z + math.sin(a0) * bottomRadius,
      );
      final b1 = (
        x + math.cos(a1) * bottomRadius,
        baseY,
        z + math.sin(a1) * bottomRadius,
      );
      final t0 = (
        x + math.cos(a0) * topRadius,
        baseY + height,
        z + math.sin(a0) * topRadius,
      );
      final t1 = (
        x + math.cos(a1) * topRadius,
        baseY + height,
        z + math.sin(a1) * topRadius,
      );
      _addQuad(mesh, b1, b0, t0, t1, color.scale(0.94 + (s % 3) * 0.04));
    }
    // Flat cap.
    final center = (x, baseY + height, z);
    for (var s = 0; s < sides; s += 1) {
      final a0 = s / sides * math.pi * 2;
      final a1 = (s + 1) / sides * math.pi * 2;
      _addTriangle(
        mesh,
        center,
        (
          x + math.cos(a1) * topRadius,
          baseY + height,
          z + math.sin(a1) * topRadius,
        ),
        (
          x + math.cos(a0) * topRadius,
          baseY + height,
          z + math.sin(a0) * topRadius,
        ),
        color,
      );
    }
  }

  void _addBox(
    _LitMesh mesh,
    double x,
    double y,
    double z, {
    required double width,
    required double height,
    required double depth,
    double yaw = 0,
    required _Rgb color,
    bool glow = false,
  }) {
    final c = math.cos(yaw);
    final s = math.sin(yaw);
    final hw = width / 2;
    final hh = height / 2;
    final hd = depth / 2;
    (double, double, double) p(double lx, double ly, double lz) =>
        (x + lx * c + lz * s, y + ly, z - lx * s + lz * c);
    final corners = [
      p(-hw, -hh, -hd),
      p(hw, -hh, -hd),
      p(hw, hh, -hd),
      p(-hw, hh, -hd),
      p(-hw, -hh, hd),
      p(hw, -hh, hd),
      p(hw, hh, hd),
      p(-hw, hh, hd),
    ];
    void face(int a, int b, int cc, int d) => _addQuad(
      mesh,
      corners[a],
      corners[b],
      corners[cc],
      corners[d],
      color,
      glow: glow,
    );
    face(4, 5, 6, 7); // +z
    face(1, 0, 3, 2); // -z
    face(5, 1, 2, 6); // +x
    face(0, 4, 7, 3); // -x
    face(7, 6, 2, 3); // top
  }

  void _addQuad(
    _LitMesh mesh,
    (double, double, double) a,
    (double, double, double) b,
    (double, double, double) c,
    (double, double, double) d,
    _Rgb color, {
    bool glow = false,
  }) {
    _addTriangle(mesh, a, b, c, color, glow: glow);
    _addTriangle(mesh, a, c, d, color, glow: glow);
  }

  void _addTriangle(
    _LitMesh mesh,
    (double, double, double) a,
    (double, double, double) b,
    (double, double, double) c,
    _Rgb color, {
    bool glow = false,
  }) {
    final n = _faceNormal([
      a.$1,
      a.$2,
      a.$3,
      b.$1,
      b.$2,
      b.$3,
      c.$1,
      c.$2,
      c.$3,
    ]);
    for (final p in [a, b, c]) {
      mesh.vertex(p.$1, p.$2, p.$3, n.$1, n.$2, n.$3, color, ao: 1, glow: glow);
    }
  }

  // --- Shadows ---------------------------------------------------------------

  void _updateGroundShadows(OutdoorLight light) {
    final shadow = _groundShadow;
    shadow.fillRange(0, shadow.length, 1);
    if (light.shadowStrength <= 0) {
      return;
    }
    // Shadows stretch away from a low sun, but never into long streaks.
    final elevation = math.max(light.sunY, 0.35);
    final offsetX = (-light.sunX / elevation).clamp(-1.6, 1.6);
    final offsetZ = (-light.sunZ / elevation).clamp(-1.6, 1.6);
    for (final tree in _shadows) {
      final cx = tree.x + offsetX * tree.height * 0.55;
      final cz = tree.z + offsetZ * tree.height * 0.55;
      final r = tree.radius;
      final cu = cx - 1.0;
      final cv = _wallZ - cz;
      final minCol = ((cu - r - _groundMinU) / _groundStep).floor();
      final maxCol = ((cu + r - _groundMinU) / _groundStep).ceil();
      final minRow = ((cv - r - _groundMinV) / _groundStep).floor();
      final maxRow = ((cv + r - _groundMinV) / _groundStep).ceil();
      for (
        var row = math.max(0, minRow);
        row <= math.min(_groundRows - 1, maxRow);
        row += 1
      ) {
        for (
          var col = math.max(0, minCol);
          col <= math.min(_groundCols - 1, maxCol);
          col += 1
        ) {
          final du = _groundMinU + col * _groundStep - cu;
          final dv = _groundMinV + row * _groundStep - cv;
          final d = math.sqrt(du * du + dv * dv) / r;
          if (d >= 1) {
            continue;
          }
          final amount = light.shadowStrength * _smoothstep(1, 0.35, d);
          final index = row * _groundCols + col;
          shadow[index] = math.min(shadow[index], 1 - amount);
        }
      }
    }
  }
}

/// A puffy cumulus with a flat, shaded base and a sunlit crown.
three.Mesh buildOutdoorCloud({
  required int variant,
  required double scale,
  required int color,
  required int shadowColor,
  required double opacity,
}) {
  final random = math.Random(0xC10D5 + variant * 977);
  final unit = _unitIcosahedron(1);
  final positions = <double>[];
  final colors = <double>[];
  final top = _Rgb.hex(color);
  final base = _Rgb.hex(shadowColor);
  final highlight = _Rgb.lerp(top, const _Rgb.hex(0xFFFFFF), 0.5);
  final floor = -0.35 * scale;
  final lobes = 7 + random.nextInt(4);
  final width = (3.2 + random.nextDouble() * 1.6) * scale;
  for (var i = 0; i < lobes; i += 1) {
    final t = lobes == 1 ? 0.5 : i / (lobes - 1);
    final center = (1 - (2 * t - 1).abs());
    final r = scale * (0.55 + center * 0.75 + random.nextDouble() * 0.25);
    final cx = (t - 0.5) * width + (random.nextDouble() - 0.5) * 0.3 * scale;
    final cy = floor + r * (0.45 + random.nextDouble() * 0.35);
    final cz = (random.nextDouble() - 0.5) * 1.0 * scale;
    for (var k = 0; k < unit.length; k += 3) {
      final ux = unit[k];
      final uy = unit[k + 1];
      final uz = unit[k + 2];
      final y = math.max(cy + uy * r, floor);
      positions.addAll([cx + ux * r * 1.15, y, cz + uz * r]);
      final heightT = ((y - floor) / (scale * 2.2)).clamp(0.0, 1.0);
      // Lit from above and slightly toward the viewer.
      final facing = (uy * 0.7 + uz * 0.3 + 0.2).clamp(0.0, 1.0);
      final shade = (heightT * 0.65 + facing * 0.45).clamp(0.0, 1.0);
      final c = shade > 0.75
          ? _Rgb.lerp(top, highlight, (shade - 0.75) / 0.25)
          : _Rgb.lerp(base, top, shade / 0.75);
      colors.addAll([srgbToLinear(c.r), srgbToLinear(c.g), srgbToLinear(c.b)]);
    }
  }
  final geometry = three.BufferGeometry()
    ..setAttributeFromString(
      'position',
      three.Float32BufferAttribute.fromList(positions, 3),
    )
    ..setAttributeFromString(
      'color',
      three.Float32BufferAttribute.fromList(colors, 3),
    );
  return three.Mesh(
    geometry,
    three.MeshBasicMaterial.fromMap({
      'color': 0xFFFFFF,
      'vertexColors': true,
      if (opacity < 1.0) 'transparent': true,
      if (opacity < 1.0) 'opacity': opacity,
      if (opacity < 1.0) 'depthWrite': false,
    }),
  );
}

/// Vertex colours are treated as linear and encoded to sRGB on output, so
/// palette (sRGB) values are decoded first to keep their intended saturation.
double srgbToLinear(double value) {
  final v = value.clamp(0.0, 1.0);
  return v <= 0.04045
      ? v / 12.92
      : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
}

// --- Baked-lighting mesh -----------------------------------------------------

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
  final _glow = <double>[];
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
    bool glow = false,
  }) {
    _positions.addAll([x, y, z]);
    _normals.addAll([nx, ny, nz]);
    _albedo.addAll([color.r, color.g, color.b]);
    _ao.add(ao);
    _glow.add(glow ? 1 : 0);
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
        if (_glow[i] > 0 && light.windowGlow > 0) {
          r += (1.0 - r) * light.windowGlow;
          g += (0.78 - g) * light.windowGlow;
          b += (0.42 - b) * light.windowGlow;
        }
        final far = math.max(0.0, distance - 9) / 46;
        haze = (1 - math.exp(-far * far * 1.6)) * light.fogAmount;
      }
      if (sat < 1) {
        final grey = r * 0.3 + g * 0.55 + b * 0.15;
        r = grey + (r - grey) * sat;
        g = grey + (g - grey) * sat;
        b = grey + (b - grey) * sat;
      }
      out[i3] = srgbToLinear(r + (fog.r - r) * haze);
      out[i3 + 1] = srgbToLinear(g + (fog.g - g) * haze);
      out[i3 + 2] = srgbToLinear(b + (fog.b - b) * haze);
    }
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

// --- Noise and geometry helpers ----------------------------------------------

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
