import 'dart:math' as math;
import 'dart:typed_data';

import 'package:three_js/three_js.dart' as three;

import 'room_state.dart' show OutdoorEnvironment;

part 'outdoor_city.dart';
part 'outdoor_forest.dart';
part 'outdoor_island.dart';
part 'outdoor_kit.dart';
part 'outdoor_waterfall.dart';

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
    this.daylight = 1,
    this.twilight = 0,
    this.clearness = 1,
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

  /// 0..1 strength of lit windows, street lights and neon (night).
  final double windowGlow;

  /// 0 at night, 1 in full day.
  final double daylight;

  /// 1 around sunrise and sunset.
  final double twilight;

  /// 1 under a clear sky, falling toward 0 in overcast and rain.
  final double clearness;
}

/// The scenery beyond the room's window. Each environment builds its geometry
/// once; [relight] rewrites the baked lighting for a new time of day or
/// weather, and [animate] drives anything that moves (water, cars, birds).
abstract class OutdoorScene {
  OutdoorScene._(this._wallZ);

  static OutdoorScene build(
    OutdoorEnvironment environment, {
    required double wallZ,
  }) {
    final OutdoorScene scene = switch (environment) {
      OutdoorEnvironment.island => IslandScene(wallZ: wallZ),
      OutdoorEnvironment.waterfall => _WaterfallScene(wallZ),
      OutdoorEnvironment.city => _CityScene(wallZ),
      OutdoorEnvironment.forest => _ForestScene(wallZ),
    };
    return scene;
  }

  final double _wallZ;
  final three.Group group = three.Group();
  final List<_LitMesh> _meshes = [];
  final List<_FlowMesh> _flows = [];
  final List<_TreeShadow> _shadows = [];
  _LitMesh? _groundMesh;
  Float32List? _groundShadow;
  int _groundCols = 0;
  int _groundRows = 0;
  final double _groundStep = 0.55;
  double _groundMinU = 0;
  double _groundMinV = 0;
  bool _built = false;

  // Window-centred coordinates: u runs across the view (0 = window centre),
  // v runs away from the back wall (0 = the wall, positive = outdoors).
  double _worldX(double u) => u + 1.0;
  double _worldZ(double v) => _wallZ - v;

  // Haze is measured from the window, where every outdoor view starts.
  static const double _eyeX = 1.0;
  static const double _eyeY = 2.3;
  double get _eyeZ => _wallZ + 0.6;

  /// Ground height at window-centred coordinates.
  double height(double u, double v);

  _Rgb _groundColor(double u, double v, double h, double ny);

  /// Adds everything other than the ground mesh.
  void _populate();

  // Ground grid extent, in window-centred coordinates.
  double get _groundUMin => -54;
  double get _groundUSpan => 108;
  double get _groundVMin => -4;
  double get _groundVSpan => 60;

  /// How far (in canopy heights) shadows may stretch under a low sun.
  double get _shadowReach => 1.6;

  void _ensureBuilt() {
    if (_built) {
      return;
    }
    _built = true;
    _buildGround();
    _populate();
  }

  void relight(OutdoorLight light) {
    _ensureBuilt();
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
    for (final flow in _flows) {
      flow.relight(light, _eyeX, _eyeY, _eyeZ);
    }
    _onRelight(light);
  }

  void _onRelight(OutdoorLight light) {}

  /// Advances moving scenery by [dt] seconds.
  void animate(double dt) {
    for (final flow in _flows) {
      flow.animate(dt);
    }
    _onAnimate(dt);
  }

  void _onAnimate(double dt) {}

  void _addMesh(_LitMesh mesh) {
    if (mesh.count == 0) {
      return;
    }
    _meshes.add(mesh);
    group.add(mesh.createMesh());
  }

  void _addFlow(_FlowMesh flow) {
    if (flow.count == 0) {
      return;
    }
    _flows.add(flow);
    group.add(flow.createMesh());
  }

  // --- Ground ------------------------------------------------------------------

  void _buildGround() {
    _groundMinU = _groundUMin;
    _groundMinV = _groundVMin;
    _groundCols = (_groundUSpan / _groundStep).round() + 1;
    _groundRows = (_groundVSpan / _groundStep).round() + 1;
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
        // Painterly grain so close ground doesn't read as a smooth gradient.
        final grain = _hash2(col, row + 31);
        mesh.vertex(
          _worldX(u),
          h,
          _worldZ(v),
          nx,
          ny,
          nz,
          color.scale(0.9 + grain * 0.18),
          ao: 1,
        );
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

  void _updateGroundShadows(OutdoorLight light) {
    final shadow = _groundShadow;
    if (shadow == null) {
      return;
    }
    shadow.fillRange(0, shadow.length, 1);
    if (light.shadowStrength <= 0) {
      return;
    }
    // Shadows stretch away from a low sun, within the scene's reach.
    final reach = _shadowReach;
    final elevation = math.max(light.sunY, 0.6 / reach);
    final offsetX = (-light.sunX / elevation).clamp(-reach, reach);
    final offsetZ = (-light.sunZ / elevation).clamp(-reach, reach);
    for (final tree in _shadows) {
      final stretch = math.sqrt(offsetX * offsetX + offsetZ * offsetZ);
      // Long shadows are cast as a row of soft discs along the sun line.
      final steps = math.max(1, (stretch * 1.2).ceil());
      for (var step = 1; step <= steps; step += 1) {
        final t = step / steps;
        final cx = tree.x + offsetX * tree.height * 0.55 * t;
        final cz = tree.z + offsetZ * tree.height * 0.55 * t;
        final r = tree.radius * (0.75 + 0.25 * t);
        _stampShadow(shadow, cx, cz, r, light.shadowStrength);
      }
    }
  }

  void _stampShadow(
    Float32List shadow,
    double cx,
    double cz,
    double r,
    double strength,
  ) {
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
        final amount = strength * _smoothstep(1, 0.35, d);
        final index = row * _groundCols + col;
        shadow[index] = math.min(shadow[index], 1 - amount);
      }
    }
  }

  // --- Trees -------------------------------------------------------------------

  void _addBroadleaf(
    _LitMesh foliage,
    _LitMesh solids,
    math.Random random,
    double x,
    double baseY,
    double z,
    double scale,
    _Rgb color,
    List<double> unit, {
    double birchChance = 0.15,
    double tallChance = 0.3,
  }) {
    final tall = random.nextDouble() < tallChance;
    final trunkHeight = (tall ? 1.6 : 1.2) * scale + random.nextDouble() * 0.5;
    final radius = (tall ? 1.15 : 1.45) * scale;
    final birch = random.nextDouble() < birchChance;
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
    double scale, {
    _Rgb dark = const _Rgb.hex(0x2B5A36),
    _Rgb light = const _Rgb.hex(0x3F7038),
    int tiers = 3,
    int sides = 7,
    double slender = 1,
    bool castShadow = true,
  }) {
    final color = _Rgb.lerp(dark, light, random.nextDouble());
    final total = (3.4 + random.nextDouble() * 1.6) * scale * slender;
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
        sides: sides,
      );
    }
    if (castShadow) {
      _shadows.add(
        _TreeShadow(x: x, z: z, radius: scale * 1.05, height: total * 0.55),
      );
    }
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
    int sides = 7,
  }) {
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

  // --- Rocks and primitives ------------------------------------------------------

  void _addRock(
    _LitMesh mesh,
    List<double> unit,
    math.Random random,
    double x,
    double y,
    double z,
    double size,
    _Rgb color, {
    _Rgb? moss,
  }) {
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
      var faceColor = color.scale(0.92 + random.nextDouble() * 0.12);
      // Moss gathers on the upward-facing facets.
      if (moss != null && n.$2 > 0.45) {
        faceColor = _Rgb.lerp(faceColor, moss, (n.$2 - 0.45) * 1.6);
      }
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
    _Rgb? emissive,
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
      _addQuad(
        mesh,
        b1,
        b0,
        t0,
        t1,
        color.scale(0.94 + (s % 3) * 0.04),
        emissive: emissive,
      );
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
        emissive: emissive,
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
    _Rgb? emissive,
    bool back = true,
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
      emissive: emissive,
    );
    face(4, 5, 6, 7); // +z
    if (back) {
      face(1, 0, 3, 2); // -z
    }
    face(5, 1, 2, 6); // +x
    face(0, 4, 7, 3); // -x
    face(7, 6, 2, 3); // top
  }

  /// A thin square beam between two points: cables, struts, bridge legs.
  void _addBeam(
    _LitMesh mesh,
    (double, double, double) from,
    (double, double, double) to,
    double thickness,
    _Rgb color, {
    _Rgb? emissive,
  }) {
    var dx = to.$1 - from.$1;
    var dy = to.$2 - from.$2;
    var dz = to.$3 - from.$3;
    final length = math.sqrt(dx * dx + dy * dy + dz * dz);
    if (length == 0) {
      return;
    }
    dx /= length;
    dy /= length;
    dz /= length;
    // Any axis not parallel to the beam gives two perpendiculars.
    final (ax, ay, az) = dy.abs() < 0.9 ? (0.0, 1.0, 0.0) : (1.0, 0.0, 0.0);
    var px = dy * az - dz * ay;
    var py = dz * ax - dx * az;
    var pz = dx * ay - dy * ax;
    final pl = math.sqrt(px * px + py * py + pz * pz);
    px = px / pl * thickness / 2;
    py = py / pl * thickness / 2;
    pz = pz / pl * thickness / 2;
    final qx = (dy * pz - dz * py);
    final qy = (dz * px - dx * pz);
    final qz = (dx * py - dy * px);
    (double, double, double) corner(
      (double, double, double) o,
      double sp,
      double sq,
    ) => (
      o.$1 + px * sp + qx * sq,
      o.$2 + py * sp + qy * sq,
      o.$3 + pz * sp + qz * sq,
    );
    const signs = [(1.0, 1.0), (-1.0, 1.0), (-1.0, -1.0), (1.0, -1.0)];
    for (var i = 0; i < 4; i += 1) {
      final a = signs[i];
      final b = signs[(i + 1) % 4];
      _addQuad(
        mesh,
        corner(from, a.$1, a.$2),
        corner(from, b.$1, b.$2),
        corner(to, b.$1, b.$2),
        corner(to, a.$1, a.$2),
        color,
        emissive: emissive,
        doubleSided: true,
      );
    }
  }

  void _addQuad(
    _LitMesh mesh,
    (double, double, double) a,
    (double, double, double) b,
    (double, double, double) c,
    (double, double, double) d,
    _Rgb color, {
    _Rgb? emissive,
    bool doubleSided = false,
  }) {
    _addTriangle(mesh, a, b, c, color, emissive: emissive);
    _addTriangle(mesh, a, c, d, color, emissive: emissive);
    if (doubleSided) {
      _addTriangle(mesh, a, c, b, color, emissive: emissive);
      _addTriangle(mesh, a, d, c, color, emissive: emissive);
    }
  }

  void _addTriangle(
    _LitMesh mesh,
    (double, double, double) a,
    (double, double, double) b,
    (double, double, double) c,
    _Rgb color, {
    _Rgb? emissive,
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
      mesh.vertex(
        p.$1,
        p.$2,
        p.$3,
        n.$1,
        n.$2,
        n.$3,
        color,
        ao: 1,
        emissive: emissive,
      );
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
