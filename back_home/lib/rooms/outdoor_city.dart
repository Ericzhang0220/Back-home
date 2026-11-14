part of 'outdoor_landscape.dart';

/// A riverside skyline at the reference's level of detail: towers whose
/// facades are painted window by window, near-black after dark with lights
/// clustered by tenant, stepped deco spires, rooftop signs and plant, blinking
/// aviation beacons, a distant glitter of far-off city, a cable-stayed bridge
/// and an expressway with cars in both directions.
class CityScene extends OutdoorScene {
  CityScene(super.wallZ) : super._();

  static const double _water = -5.2;
  static const double _bank = -3.6;

  final _FacadeMesh _facades = _FacadeMesh();
  final _CityRoad _road = _CityRoad();
  final _GlowMesh _halos = _GlowMesh();
  final _GlowMesh _beacons = _GlowMesh();
  final List<(double, double)> _towerTops = []; // (v, top y)
  final List<_Car> _cars = [];
  double _time = 0;
  double _night = 0;

  @override
  double get _groundUMin => -88;

  @override
  double get _groundUSpan => 176;

  @override
  double get _groundVSpan => 74;

  // The city's ground is flat and mostly hidden by towers.
  @override
  double get _groundStep => 0.8;

  // Keeps the night air clear enough for the towers to stay dark against it.
  @override
  double get _hazeScale => 0.55;

  @override
  void dispose() {
    _facades.dispose();
    super.dispose();
  }

  /// World positions of every car, for tests.
  @visibleForTesting
  Iterable<three.Vector3> get debugCarPositions =>
      _cars.map((car) => car.mesh.position);

  /// Road surface height nearest a world position, for tests.
  @visibleForTesting
  double debugRoadHeightNear(double x, double z) =>
      _road.heightNear(x - 1.0, _wallZ - z);

  /// Lowest clearance between the road deck and the ground, for tests.
  @visibleForTesting
  double get debugLowestRoadClearance {
    var lowest = double.infinity;
    for (var s = 0.0; s < _road.length; s += 1) {
      final p = _road.at(s);
      lowest = math.min(lowest, p.y - height(p.u, p.v));
    }
    return lowest;
  }

  @override
  double _obstacleTop(double v) {
    var top = -10.0;
    for (final (tv, y) in _towerTops) {
      if ((tv - v).abs() < 2.5) {
        top = math.max(top, y);
      }
    }
    return top;
  }

  double _riverMask(double u, double v) =>
      _smoothstep(10.5, 12.5, v) * (1 - _smoothstep(34, 36, v));

  @override
  double height(double u, double v) {
    final detail = _fbm(u * 0.15 + 3, v * 0.15 + 9) - 0.5;
    // The house sits on a wooded bluff above the near bank.
    var h =
        -0.4 - 3.2 * _smoothstep(2, 9, v) + detail * 0.8 * _smoothstep(3, 9, v);
    h += (_water - 1.6 - h) * _riverMask(u, v);
    // Far bank: flat embankment, rising gently into the city.
    final far = _smoothstep(35, 36.5, v);
    h += (_bank + _smoothstep(30, 56, v) * 1.2 - h) * far;
    // Hills behind the city close the horizon at the sides.
    h += _smoothstep(26, 50, u.abs()) * _smoothstep(36, 60, v) * 6;
    return h;
  }

  @override
  _Rgb _groundColor(double u, double v, double h, double ny) {
    final fine = _hash2((u * 1.6).round(), (v * 1.6).round() + 59);
    // Paved city blocks on the far bank, green bluff on the near one.
    if (v > 35.5) {
      return _Rgb.lerp(
        const _Rgb.hex(0x4E4D4C),
        const _Rgb.hex(0x62605C),
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
    final solids = _LitMesh(wrap: 0.2);
    final foliage = _LitMesh(wrap: 0.45);
    _buildSkyline(solids);
    _buildDistantLights();
    _buildBridge(solids);
    _buildRoad(solids);
    _buildTrees(foliage, solids);
    group.add(_facades.createMesh());
    _buildRiver();
    _addMesh(solids);
    _addMesh(foliage);
    group
      ..add(_halos.createMesh())
      ..add(_beacons.createMesh());
    _buildCars();
  }

  // --- Skyline -----------------------------------------------------------------

  void _buildSkyline(_LitMesh solids) {
    final random = math.Random(0xC17E);
    // Landmarks sit either side of the window's centre bar, where they frame
    // the view from the ledge and from inside the room.
    const landmarks = <_Landmark>[
      _Landmark(
        -13.5,
        49,
        3.0,
        2.6,
        23,
        _TowerForm.tapered,
        _FacadeStyle.ribbon,
        null,
      ),
      _Landmark(
        -8.5,
        52,
        3.4,
        3.0,
        26,
        _TowerForm.stepped,
        _FacadeStyle.curtain,
        4,
      ),
      _Landmark(
        -4.6,
        44,
        3.2,
        2.8,
        15,
        _TowerForm.box,
        _FacadeStyle.curtain,
        0,
      ),
      _Landmark(3.6, 49, 4.4, 3.8, 20, _TowerForm.box, _FacadeStyle.punched, 1),
      _Landmark(
        7.6,
        53,
        2.2,
        2.2,
        25,
        _TowerForm.round,
        _FacadeStyle.ribbon,
        3,
      ),
      _Landmark(
        7.2,
        43.5,
        4.0,
        3.2,
        13,
        _TowerForm.box,
        _FacadeStyle.ribbon,
        2,
      ),
      _Landmark(
        13.5,
        51,
        5.2,
        4.6,
        19,
        _TowerForm.deco,
        _FacadeStyle.deco,
        null,
      ),
      _Landmark(
        19.5,
        46,
        4.6,
        4.0,
        18,
        _TowerForm.box,
        _FacadeStyle.punched,
        null,
      ),
      _Landmark(
        -20,
        53,
        4.2,
        3.6,
        22,
        _TowerForm.stepped,
        _FacadeStyle.curtain,
        5,
      ),
      _Landmark(
        -27,
        48,
        3.6,
        3.2,
        17,
        _TowerForm.box,
        _FacadeStyle.ribbon,
        null,
      ),
      _Landmark(
        27,
        55,
        3.8,
        3.4,
        22,
        _TowerForm.tapered,
        _FacadeStyle.curtain,
        null,
      ),
      _Landmark(
        -37,
        54,
        3.8,
        3.4,
        20,
        _TowerForm.stepped,
        _FacadeStyle.punched,
        null,
      ),
      _Landmark(
        36,
        50,
        4.0,
        3.6,
        17,
        _TowerForm.box,
        _FacadeStyle.curtain,
        null,
      ),
    ];
    for (final landmark in landmarks) {
      _addBuilding(solids, random, landmark, tint: const _Rgb(1, 1, 1));
    }
    const tints = [
      _Rgb(1, 1, 1),
      _Rgb(0.82, 0.8, 0.78),
      _Rgb(0.62, 0.62, 0.66),
      _Rgb(0.9, 0.78, 0.66),
      _Rgb(0.78, 0.6, 0.5),
    ];
    const step = 3.7;
    for (var v = 43.0; v < 70; v += step) {
      for (var u = -74.0; u < 74; u += step) {
        if (random.nextDouble() < 0.1) {
          continue;
        }
        final bu = u + (random.nextDouble() - 0.5) * 1.1;
        final bv = v + (random.nextDouble() - 0.5) * 1.1;
        final width = 2.0 + random.nextDouble() * 1.5;
        final depth = 2.0 + random.nextDouble() * 1.3;
        if (_hitsLandmark(landmarks, bu, bv, width, depth)) {
          continue;
        }
        final dx = bu;
        final dv = bv + 0.6;
        // Past the far plane is never drawn.
        if (dx * dx + dv * dv > 76 * 76) {
          continue;
        }
        // Low blocks up front, rising toward the centre of town.
        final centre = math.exp(-math.pow(bu / 24, 2).toDouble());
        final depthRise = _smoothstep(42, 58, bv);
        final tall =
            3.2 +
            random.nextDouble() * 4 +
            depthRise * (2 + centre * 7) * (0.5 + random.nextDouble());
        final pick = random.nextDouble();
        _addBuilding(
          solids,
          random,
          _Landmark(
            bu,
            bv,
            width,
            depth,
            tall,
            tall > 11 && pick < 0.3 ? _TowerForm.stepped : _TowerForm.box,
            pick < 0.42
                ? _FacadeStyle.punched
                : pick < 0.74
                ? _FacadeStyle.curtain
                : pick < 0.88
                ? _FacadeStyle.ribbon
                : _FacadeStyle.deco,
            null,
          ),
          tint: tints[random.nextInt(tints.length)],
        );
      }
    }
  }

  bool _hitsLandmark(
    List<_Landmark> landmarks,
    double u,
    double v,
    double width,
    double depth,
  ) {
    for (final l in landmarks) {
      if ((l.u - u).abs() < (l.width + width) / 2 + 0.3 &&
          (l.v - v).abs() < (l.depth + depth) / 2 + 0.3) {
        return true;
      }
    }
    return false;
  }

  void _addBuilding(
    _LitMesh solids,
    math.Random random,
    _Landmark tower, {
    required _Rgb tint,
  }) {
    final x = _worldX(tower.u);
    final z = _worldZ(tower.v);
    final base = height(tower.u, tower.v) - 0.2;
    // Some towers are nearly dark, some working late.
    final emit = 0.62 + random.nextDouble() * 0.5;
    final near = tower.v < 58;
    final pitchX = near ? 0.2 + random.nextDouble() * 0.05 : 0.34;
    final pitchY = near ? 0.28 + random.nextDouble() * 0.05 : 0.44;
    void faces(
      double w,
      double d,
      double y,
      double h, {
      double taper = 1,
      required _FacadeStyle style,
    }) {
      _addBoxFacades(
        random,
        x,
        z,
        w,
        d,
        y,
        h,
        taper: taper,
        style: style,
        tint: tint,
        emit: emit,
        pitchX: pitchX,
        pitchY: pitchY,
      );
    }

    final wallTint = _Rgb(0.34 * tint.r, 0.34 * tint.g, 0.36 * tint.b);
    var top = base;
    var roofW = tower.width;
    var roofD = tower.depth;
    switch (tower.form) {
      case _TowerForm.box:
        faces(tower.width, tower.depth, base, tower.height, style: tower.style);
        top = base + tower.height;
      case _TowerForm.tapered:
        const taper = 0.78;
        faces(
          tower.width,
          tower.depth,
          base,
          tower.height,
          taper: taper,
          style: tower.style,
        );
        top = base + tower.height;
        roofW *= taper;
        roofD *= taper;
      case _TowerForm.stepped:
        final lower = tower.height * 0.58;
        faces(tower.width, tower.depth, base, lower, style: tower.style);
        _addLedge(
          solids,
          x,
          z,
          tower.width,
          tower.depth,
          base + lower,
          wallTint,
        );
        final upperW = tower.width * 0.78;
        final upperD = tower.depth * 0.78;
        faces(
          upperW,
          upperD,
          base + lower,
          tower.height - lower,
          style: tower.style,
        );
        top = base + tower.height;
        roofW = upperW;
        roofD = upperD;
      case _TowerForm.round:
        _addRoundFacades(
          random,
          x,
          z,
          tower.width,
          base,
          tower.height,
          style: tower.style,
          tint: tint,
          emit: emit,
          pitchX: pitchX,
          pitchY: pitchY,
        );
        top = base + tower.height;
      case _TowerForm.deco:
        // Art-deco setbacks climbing to a mast, with pilasters on each stage.
        var w = tower.width;
        var d = tower.depth;
        var y = base;
        const stages = [1.0, 0.46, 0.3, 0.2];
        for (var i = 0; i < stages.length; i += 1) {
          final h = tower.height * stages[i];
          faces(w, d, y, h, style: tower.style);
          _addPilasters(solids, x, z, w, d, y, h, wallTint);
          y += h;
          _addLedge(solids, x, z, w, d, y, wallTint);
          w *= 0.74;
          d *= 0.74;
        }
        _addPrism(
          solids,
          x,
          y,
          z,
          bottomRadius: w * 0.6,
          topRadius: 0.05,
          height: 6.5,
          sides: 4,
          color: wallTint.scale(1.5),
        );
        _addBeacon(solids, x, y + 6.6, z);
        top = y + 6.6;
        roofW = w;
        roofD = d;
    }
    if (tower.form != _TowerForm.deco) {
      _addRoof(solids, random, tower, x, z, roofW, roofD, top, wallTint);
    }
    final sign = tower.sign;
    if (sign != null) {
      _addSign(x, z, roofW, roofD, top, tower.form, sign, tint, emit);
    }
    // Lit street level along the front rows.
    if (tower.v < 52) {
      _addBox(
        solids,
        x,
        base + 0.42,
        z + tower.depth / 2 + 0.02,
        width: tower.width * 0.92,
        height: 0.32,
        depth: 0.03,
        color: wallTint,
        emissive: _Rgb.lerp(
          const _Rgb.hex(0xFFD9A0),
          const _Rgb.hex(0xFFF0DC),
          random.nextDouble(),
        ).scale(0.5),
      );
    }
    _towerTops.add((tower.v, top));
  }

  /// A patch of the atlas sized to a face, so windows keep a real-world size.
  (double, double, double, double) _patchFor(
    math.Random random,
    _FacadeStyle style,
    double faceWidth,
    double faceHeight,
    double pitchX,
    double pitchY,
  ) {
    final cols = (faceWidth / pitchX).round().clamp(
      2,
      _FacadeAtlas.columns - 2,
    );
    final rows = (faceHeight / pitchY).round().clamp(
      2,
      _FacadeAtlas.floors - 2,
    );
    return _FacadeAtlas.instance.patch(
      style,
      random.nextInt(_FacadeAtlas.columns - cols),
      random.nextInt(_FacadeAtlas.floors - rows),
      cols,
      rows,
    );
  }

  /// The faces the house can see: the front, plus whichever sides are turned
  /// toward the window (both, for towers near the centre of the view, since
  /// the camera can pan around the room).
  void _addBoxFacades(
    math.Random random,
    double x,
    double z,
    double width,
    double depth,
    double baseY,
    double height, {
    double taper = 1,
    required _FacadeStyle style,
    required _Rgb tint,
    required double emit,
    required double pitchX,
    required double pitchY,
  }) {
    final hw = width / 2;
    final hd = depth / 2;
    final tw = hw * taper;
    final td = hd * taper;
    final top = baseY + height;
    void face(
      (double, double) a,
      (double, double) b,
      (double, double) ta,
      (double, double) tb,
      double faceWidth,
    ) {
      _facades.quad(
        (a.$1, baseY, a.$2),
        (b.$1, baseY, b.$2),
        (tb.$1, top, tb.$2),
        (ta.$1, top, ta.$2),
        _patchFor(random, style, faceWidth, height, pitchX, pitchY),
        tint,
        emit,
      );
    }

    face(
      (x - hw, z + hd),
      (x + hw, z + hd),
      (x - tw, z + td),
      (x + tw, z + td),
      width,
    );
    final offset = x - OutdoorScene._eyeX;
    if (offset < 6) {
      face(
        (x + hw, z + hd),
        (x + hw, z - hd),
        (x + tw, z + td),
        (x + tw, z - td),
        depth,
      );
    }
    if (offset > -6) {
      face(
        (x - hw, z - hd),
        (x - hw, z + hd),
        (x - tw, z - td),
        (x - tw, z + td),
        depth,
      );
    }
    _addRoofCap(x, z, tw, td, top, tint);
  }

  void _addRoofCap(
    double x,
    double z,
    double hw,
    double hd,
    double y,
    _Rgb tint,
  ) {
    // Dark bare wall from the signs' panel colour; roofs are seen from above
    // only by a camera tilted well down.
    final uv = _FacadeAtlas.instance.signPatch(0);
    final solid = (uv.$1, uv.$2, uv.$1 + 0.0005, uv.$2 + 0.0005);
    _facades.quad(
      (x - hw, y, z + hd),
      (x + hw, y, z + hd),
      (x + hw, y, z - hd),
      (x - hw, y, z - hd),
      solid,
      tint,
      0,
    );
  }

  void _addRoundFacades(
    math.Random random,
    double x,
    double z,
    double radius,
    double baseY,
    double height, {
    required _FacadeStyle style,
    required _Rgb tint,
    required double emit,
    required double pitchX,
    required double pitchY,
  }) {
    const segments = 18;
    final segmentWidth = 2 * math.pi * radius / segments;
    final colsPerSegment = (segmentWidth / pitchX).round().clamp(1, 6);
    final rows = (height / pitchY).round().clamp(2, _FacadeAtlas.floors - 2);
    final firstFloor = random.nextInt(_FacadeAtlas.floors - rows);
    var column = 0;
    for (var i = 0; i < segments; i += 1) {
      final a0 = i / segments * math.pi * 2;
      final a1 = (i + 1) / segments * math.pi * 2;
      final mid = (a0 + a1) / 2;
      // Skip the half facing away from the house.
      if (math.sin(mid) < -0.25) {
        continue;
      }
      // Walking the angle downward keeps each quad wound to face outward.
      final uv = _FacadeAtlas.instance.patch(
        style,
        column,
        firstFloor,
        colsPerSegment,
        rows,
      );
      column += colsPerSegment;
      _facades.quad(
        (x + math.cos(a1) * radius, baseY, z + math.sin(a1) * radius),
        (x + math.cos(a0) * radius, baseY, z + math.sin(a0) * radius),
        (x + math.cos(a0) * radius, baseY + height, z + math.sin(a0) * radius),
        (x + math.cos(a1) * radius, baseY + height, z + math.sin(a1) * radius),
        uv,
        tint,
        emit,
      );
    }
  }

  void _addLedge(
    _LitMesh mesh,
    double x,
    double z,
    double width,
    double depth,
    double y,
    _Rgb color,
  ) {
    _addBox(
      mesh,
      x,
      y,
      z,
      width: width + 0.1,
      height: 0.14,
      depth: depth + 0.1,
      color: color.scale(1.3),
    );
  }

  /// Slim vertical fins standing proud of the front face.
  void _addPilasters(
    _LitMesh mesh,
    double x,
    double z,
    double width,
    double depth,
    double y,
    double height,
    _Rgb color,
  ) {
    final count = (width / 0.7).floor();
    for (var i = 0; i <= count; i += 1) {
      final px = x - width / 2 + width * i / math.max(1, count);
      _addBox(
        mesh,
        px,
        y + height / 2,
        z + depth / 2 + 0.03,
        width: 0.07,
        height: height,
        depth: 0.08,
        color: color.scale(1.4),
        back: false,
      );
    }
  }

  void _addRoof(
    _LitMesh mesh,
    math.Random random,
    _Landmark tower,
    double x,
    double z,
    double width,
    double depth,
    double top,
    _Rgb color,
  ) {
    if (tower.form != _TowerForm.round) {
      _addLedge(mesh, x, z, width, depth, top, color);
    }
    final span = tower.form == _TowerForm.round ? tower.width * 1.3 : width;
    // A plant room, then a scatter of smaller boxes and masts.
    _addBox(
      mesh,
      x + (random.nextDouble() - 0.5) * span * 0.2,
      top + 0.32,
      z,
      width: span * 0.5,
      height: 0.6,
      depth: span * 0.42,
      color: color.scale(1.15),
    );
    final extras = tower.height > 9 ? 3 : 1;
    for (var i = 0; i < extras; i += 1) {
      _addBox(
        mesh,
        x + (random.nextDouble() - 0.5) * span * 0.75,
        top + 0.14,
        z + (random.nextDouble() - 0.5) * span * 0.6,
        width: 0.2 + random.nextDouble() * 0.3,
        height: 0.26,
        depth: 0.2 + random.nextDouble() * 0.3,
        color: color.scale(1.3),
        back: false,
      );
    }
    // Only the tallest towers carry an aviation light: one, at the very top.
    final beaconed = tower.height >= 19 && tower.v < 60;
    if (beaconed || (tower.height > 9 && random.nextDouble() < 0.3)) {
      final mast = 1.4 + random.nextDouble() * 1.8;
      _addBeam(
        mesh,
        (x, top + 0.5, z),
        (x, top + mast, z),
        0.05,
        color.scale(1.6),
      );
      if (beaconed) {
        _addBeacon(mesh, x, top + mast, z);
      }
    }
  }

  /// A red aviation light: a tiny core plus a small, softly pulsing halo.
  void _addBeacon(_LitMesh mesh, double x, double y, double z) {
    _addBox(
      mesh,
      x,
      y,
      z,
      width: 0.07,
      height: 0.07,
      depth: 0.07,
      color: const _Rgb.hex(0x3A1414),
      emissive: const _Rgb.hex(0xFF2A20),
      back: false,
    );
    _beacons.fan((x, y, z + 0.06), 0.2, const _Rgb.hex(0xFF2A20));
  }

  void _addSign(
    double x,
    double z,
    double width,
    double depth,
    double top,
    _TowerForm form,
    int sign,
    _Rgb tint,
    double emit,
  ) {
    final uv = _FacadeAtlas.instance.signPatch(sign);
    final signWidth = form == _TowerForm.round ? width * 1.6 : width * 0.82;
    final signHeight = signWidth * 72 / 244;
    final y = form == _TowerForm.round ? top + 0.1 : top - signHeight - 0.18;
    final front = form == _TowerForm.round
        ? z + width + 0.05
        : z + depth / 2 + 0.03;
    _facades.quad(
      (x - signWidth / 2, y, front),
      (x + signWidth / 2, y, front),
      (x + signWidth / 2, y + signHeight, front),
      (x - signWidth / 2, y + signHeight, front),
      uv,
      const _Rgb(1, 1, 1),
      1.15,
    );
  }

  /// The far side of town: out-of-focus points of light low on the horizon.
  void _buildDistantLights() {
    final random = math.Random(0xB0CE);
    for (var i = 0; i < 520; i += 1) {
      final angle = (random.nextDouble() - 0.5) * 2.2;
      final distance = 66 + random.nextDouble() * 11;
      final u = math.sin(angle) * distance;
      final v = math.cos(angle) * distance - 0.6;
      if (v < 40) {
        continue;
      }
      final pick = random.nextDouble();
      final color = pick < 0.65
          ? const _Rgb.hex(0xFFB866)
          : pick < 0.9
          ? const _Rgb.hex(0xFFE7C4)
          : const _Rgb.hex(0xA8C8FF);
      _halos.fan(
        (_worldX(u), -2.6 + random.nextDouble() * 4.4, _worldZ(v)),
        0.16 + random.nextDouble() * 0.34,
        color.scale(0.25 + random.nextDouble() * 0.45),
      );
    }
  }

  // --- Road -----------------------------------------------------------------------

  /// One continuous deck from edge to edge of the view: the road surface,
  /// barriers and columns all read the same centreline the cars drive on.
  void _buildRoad(_LitMesh mesh) {
    final road = _road;
    const halfWidth = _CityRoad.halfWidth;
    const step = 1.5;
    final count = (road.length / step).floor();
    (double, double, double) side(_RoadPoint p, double across, double y) => (
      _worldX(p.u - math.sin(p.heading) * across),
      y,
      _worldZ(p.v + math.cos(p.heading) * across),
    );
    for (var i = 0; i < count; i += 1) {
      final s0 = i * step;
      final s1 = math.min(s0 + step, road.length);
      final a = road.at(s0);
      final b = road.at(s1);
      final onBridge = road.isBridge((s0 + s1) / 2);
      _addQuad(
        mesh,
        side(a, -halfWidth, a.y),
        side(b, -halfWidth, b.y),
        side(b, halfWidth, b.y),
        side(a, halfWidth, a.y),
        const _Rgb.hex(0x3A3C40),
        doubleSided: true,
      );
      // Dashed centre line.
      if (i.isEven) {
        _addQuad(
          mesh,
          side(a, -0.04, a.y + 0.015),
          side(b, -0.04, b.y + 0.015),
          side(b, 0.04, b.y + 0.015),
          side(a, 0.04, a.y + 0.015),
          const _Rgb.hex(0xC8C6BE),
          doubleSided: true,
        );
      }
      for (final edge in const [-1.0, 1.0]) {
        final e = edge * halfWidth;
        if (onBridge) {
          // The bridge's truss carries the deck; only a slim rail shows here.
          _addQuad(
            mesh,
            side(a, e, a.y),
            side(b, e, b.y),
            side(b, e, b.y + 0.12),
            side(a, e, a.y + 0.12),
            const _Rgb.hex(0x8E8C86),
            doubleSided: true,
          );
          continue;
        }
        // Girder beneath, low barrier above with a thin light line along it.
        _addQuad(
          mesh,
          side(a, e, a.y - 0.42),
          side(b, e, b.y - 0.42),
          side(b, e, b.y + 0.14),
          side(a, e, a.y + 0.14),
          const _Rgb.hex(0x8E8C86),
          doubleSided: true,
        );
        _addQuad(
          mesh,
          side(a, e * 1.01, a.y - 0.24),
          side(b, e * 1.01, b.y - 0.24),
          side(b, e * 1.01, b.y - 0.15),
          side(a, e * 1.01, a.y - 0.15),
          const _Rgb.hex(0x8E8C86),
          emissive: const _Rgb.hex(0xFFC98A),
          doubleSided: true,
        );
      }
    }
    // Columns and street lamps, leaving the river to the bridge's own piers.
    for (var s = 2.0; s < road.length; s += 5.0) {
      final p = road.at(s);
      if (road.isBridge(s)) {
        continue;
      }
      _addBeam(
        mesh,
        (_worldX(p.u), height(p.u, p.v) - 0.3, _worldZ(p.v)),
        (_worldX(p.u), p.y - 0.3, _worldZ(p.v)),
        0.5,
        const _Rgb.hex(0x8E8A82),
      );
    }
    var lampSide = 1.0;
    for (var s = 3.0; s < road.length; s += 6.0) {
      final p = road.at(s);
      lampSide = -lampSide;
      final foot = side(p, lampSide * (halfWidth - 0.08), p.y);
      final head = (foot.$1, foot.$2 + 1.25, foot.$3);
      _addBeam(mesh, foot, head, 0.05, const _Rgb.hex(0x6E6E6E));
      _addBox(
        mesh,
        head.$1,
        head.$2,
        head.$3,
        width: 0.18,
        height: 0.07,
        depth: 0.18,
        color: const _Rgb.hex(0xBDBAB2),
        emissive: const _Rgb.hex(0xFFD9A0),
        back: false,
      );
      _halos.fan(
        (head.$1, head.$2, head.$3 + 0.1),
        0.2,
        const _Rgb.hex(0xFFC27A).scale(0.4),
        right: _facingRight(head),
      );
    }
  }

  void _buildTrees(_LitMesh foliage, _LitMesh solids) {
    final random = math.Random(0x7EE7);
    const greens = [
      _Rgb.hex(0x3F7A34),
      _Rgb.hex(0x5C9A3A),
      _Rgb.hex(0x2F6234),
      _Rgb.hex(0x7DAA3A),
      _Rgb.hex(0x9CBF3E),
    ];
    _Rgb green() => greens[random.nextInt(greens.length)];

    // Trees stand back from the expressway, and on the left stay clear of the
    // line of sight from the window to the bridge.
    bool treeFits(double u, double v) {
      if (_road.distanceTo(u, v) < 3.2) {
        return false;
      }
      final toBridge = u > -21 && u < -2.5 && v > 2.5;
      return !toBridge && u.abs() > 3 + v * 0.14;
    }

    // Close trees rising into the lower corners of the window's view; the low
    // ones toward the middle leave the river and skyline clear above them.
    const framing = [
      (2.9, 8.8, 1.2),
      (-3.2, 9.2, 1.3),
      (0.5, 9.9, 0.62),
      (-1.3, 8.4, 0.66),
      (3.9, 6.2, 0.85),
      (5.2, 7.6, 1.4),
      (7.6, 5.2, 1.25),
      (9.6, 8.6, 1.05),
      (12.4, 4.0, 1.3),
      (14.0, 7.4, 1.1),
      (-23.5, 3.6, 1.2),
      (-25.5, 1.8, 1.1),
    ];
    for (final (u, v, scale) in framing) {
      _addBroadleaf(
        foliage,
        solids,
        random,
        _worldX(u),
        height(u, v),
        _worldZ(v),
        scale,
        green(),
        birchChance: 0,
      );
    }
    // A wooded bluff either side, thinning out with distance.
    for (var i = 0; i < 150; i += 1) {
      final u = (random.nextDouble() - 0.5) * 120;
      final v = 1.5 + random.nextDouble() * 8.5;
      if (!treeFits(u, v) || u.abs() < 15) {
        continue;
      }
      _addBroadleaf(
        foliage,
        solids,
        random,
        _worldX(u),
        height(u, v),
        _worldZ(v),
        0.8 + random.nextDouble() * 0.45,
        green(),
        birchChance: 0.05,
        maxDetail: 1,
      );
    }
    // Undergrowth covers the slope down to the water, kept low enough that it
    // never rises into the view of the river.
    for (var i = 0; i < 260; i += 1) {
      final u = (random.nextDouble() - 0.5) * 70;
      final v = 2.2 + random.nextDouble() * 8.0;
      if (_road.distanceTo(u, v) < 2.4) {
        continue;
      }
      // Denser toward the edge of the bluff and away from the centre line.
      if (random.nextDouble() > 0.45 + v * 0.05 + u.abs() * 0.02) {
        continue;
      }
      _addShrub(
        foliage,
        random,
        _worldX(u),
        height(u, v) + 0.1,
        _worldZ(v),
        // Smaller right under the window, where they're seen from up close.
        (0.5 + random.nextDouble() * 0.65) * (0.5 + 0.5 * _smoothstep(2, 8, v)),
        green(),
      );
    }
  }

  // --- Traffic --------------------------------------------------------------------

  void _buildCars() {
    final random = math.Random(0xCA25);
    const paints = [
      0xE8E8E4,
      0x2E3440,
      0xB8302A,
      0x2E5E9E,
      0x9AA0A6,
      0xE8C23A, // taxi
    ];
    for (var i = 0; i < 26; i += 1) {
      final body = _LitMesh(wrap: 0.3);
      _buildCarModel(
        body,
        _Rgb.hex(paints[random.nextInt(paints.length)]),
        suv: random.nextDouble() < 0.3,
      );
      final mesh = body.createMesh();
      group.add(mesh);
      _cars.add(
        _Car(
          mesh: mesh,
          body: body,
          distance: random.nextDouble() * _road.length,
          speed: 3.2 + random.nextDouble() * 2.2,
          forward: i.isEven,
        ),
      );
    }
    _placeCars();
  }

  /// A small car facing +x, built around its own origin: body, glass cabin
  /// and roof, four wheels, headlights and tail lights.
  void _buildCarModel(_LitMesh mesh, _Rgb paint, {required bool suv}) {
    const length = 0.92;
    const width = 0.42;
    final cabinHeight = suv ? 0.2 : 0.15;
    _addBox(
      mesh,
      0,
      0.17,
      0,
      width: length,
      height: 0.16,
      depth: width,
      color: paint,
    );
    // Glass cabin, set back from the bonnet, with a painted roof.
    _addBox(
      mesh,
      -0.06,
      0.25 + cabinHeight / 2,
      0,
      width: suv ? 0.62 : 0.5,
      height: cabinHeight,
      depth: width * 0.9,
      color: const _Rgb.hex(0x2A3440),
    );
    _addBox(
      mesh,
      -0.06,
      0.26 + cabinHeight,
      0,
      width: suv ? 0.6 : 0.46,
      height: 0.025,
      depth: width * 0.86,
      color: paint,
    );
    for (final wx in const [-0.28, 0.28]) {
      for (final wz in const [-0.2, 0.2]) {
        _addBox(
          mesh,
          wx,
          0.08,
          wz,
          width: 0.17,
          height: 0.16,
          depth: 0.07,
          color: const _Rgb.hex(0x1A1A1C),
        );
      }
    }
    for (final lz in const [-0.13, 0.13]) {
      _addBox(
        mesh,
        length / 2 + 0.01,
        0.19,
        lz,
        width: 0.03,
        height: 0.06,
        depth: 0.1,
        color: const _Rgb.hex(0xE8E6DC),
        emissive: const _Rgb.hex(0xFFF4D2),
      );
      _addBox(
        mesh,
        -length / 2 - 0.01,
        0.19,
        lz,
        width: 0.03,
        height: 0.06,
        depth: 0.1,
        color: const _Rgb.hex(0x9A2228),
        emissive: const _Rgb.hex(0xFF2A1E),
      );
    }
  }

  void _placeCars() {
    for (final car in _cars) {
      final p = _road.at(car.distance);
      // Two lanes, offset either side of the centreline.
      final lane = car.forward ? -0.55 : 0.55;
      final lu = p.u - math.sin(p.heading) * lane;
      final lv = p.v + math.cos(p.heading) * lane;
      // Height comes from the same centreline as the deck, so a car can never
      // leave the road surface.
      car.mesh.position.setValues(_worldX(lu), p.y + 0.01, _worldZ(lv));
      // Cars face the way they drive, nose up or down with the deck's slope.
      car.mesh.rotation
        ..y = car.forward ? p.heading : p.heading + math.pi
        ..z = car.forward ? p.slope : -p.slope;
    }
  }

  @override
  List<three.Object3D> get _reflectionMovers => [
    for (final car in _cars) car.mesh,
  ];

  /// A glossy river spanning the view; banks and bluffs hide its edges.
  void _buildRiver() {
    final river = _MirrorWater(level: _water);
    const tint = _Rgb.hex(0x124268);
    final corners = [
      for (final (u, v) in const [
        (-92.0, 10.0),
        (92.0, 10.0),
        (-92.0, 36.5),
        (92.0, 36.5),
      ])
        river.vertex(_worldX(u), _worldZ(v), flowX: 0.12, tint: tint),
    ];
    river.indices.addAll([
      corners[0], corners[1], corners[2], //
      corners[1], corners[3], corners[2],
    ]);
    _addWater(river);
  }

  @override
  void _onRelight(OutdoorLight light) {
    _night = light.windowGlow;
    _facades.relight(light, OutdoorScene._eyeX, OutdoorScene._eyeY, _eyeZ);
    for (final car in _cars) {
      // Car models sit at their own origin; light them as if near the house.
      car.body.relight(light, 0, 1, 6);
    }
    _halos.intensity = _night;
    _beacons.intensity = _night;
  }

  @override
  void _onAnimate(double dt) {
    _time += dt;
    for (final car in _cars) {
      final moved = car.distance + (car.forward ? 1 : -1) * car.speed * dt;
      // Past the far plane at both ends, so the wrap is never seen.
      car.distance = (moved % _road.length + _road.length) % _road.length;
    }
    _placeCars();
    if (_night > 0) {
      // Aviation lights breathe slowly rather than flash.
      _beacons.intensity =
          _night * (0.65 + 0.35 * math.sin(_time * math.pi / 2.5));
    }
  }
}

enum _TowerForm { box, tapered, stepped, round, deco }

class _Landmark {
  const _Landmark(
    this.u,
    this.v,
    this.width,
    this.depth,
    this.height,
    this.form,
    this.style,
    this.sign,
  );

  final double u;
  final double v;
  final double width;
  final double depth;
  final double height;
  final _TowerForm form;
  final _FacadeStyle style;
  final int? sign;
}

/// A point on the road: where it is, which way it runs and how high it stands.
class _RoadPoint {
  const _RoadPoint(this.u, this.v, this.y, this.heading, this.slope);

  final double u;
  final double v;
  final double y;
  final double heading;
  final double slope;
}

/// The expressway's centreline: a smooth curve from one side of the view to
/// the other, sampled evenly, with one height profile for everything on it.
class _CityRoad {
  _CityRoad() {
    _resample();
  }

  static const double halfWidth = 1.3;
  static const double _deckY = -1.6;
  static const double _spacing = 0.5;
  static const _waypoints = <(double, double)>[
    (-90, 6.8),
    (-84, 6.8),
    (-62, 6.9),
    (-40, 7.0),
    (-26, 7.4),
    (-17, 9.4),
    (-13.5, 12.5),
    (-8.5, 34.0),
    (-5.5, 37.4),
    (2, 39.0),
    (20, 39.2),
    (40, 39.2),
    (86, 39.4),
    (92, 39.4),
  ];

  final List<double> _us = [];
  final List<double> _vs = [];
  late final double length;
  late final double bridgeStart;
  late final double bridgeEnd;

  void _resample() {
    // Dense Catmull-Rom points, then even steps along their arc length.
    final dense = <(double, double)>[];
    for (var i = 1; i < _waypoints.length - 2; i += 1) {
      final p0 = _waypoints[i - 1];
      final p1 = _waypoints[i];
      final p2 = _waypoints[i + 1];
      final p3 = _waypoints[i + 2];
      for (var k = 0; k < 40; k += 1) {
        final t = k / 40;
        double spline(double a, double b, double c, double d) =>
            0.5 *
            (2 * b +
                (c - a) * t +
                (2 * a - 5 * b + 4 * c - d) * t * t +
                (3 * b - a - 3 * c + d) * t * t * t);
        dense.add((
          spline(p0.$1, p1.$1, p2.$1, p3.$1),
          spline(p0.$2, p1.$2, p2.$2, p3.$2),
        ));
      }
    }
    dense.add(_waypoints[_waypoints.length - 2]);
    _us.add(dense.first.$1);
    _vs.add(dense.first.$2);
    var carried = 0.0;
    for (var i = 1; i < dense.length; i += 1) {
      final a = dense[i - 1];
      final b = dense[i];
      final du = b.$1 - a.$1;
      final dv = b.$2 - a.$2;
      final segment = math.sqrt(du * du + dv * dv);
      var at = _spacing - carried;
      while (at <= segment) {
        final t = at / segment;
        _us.add(a.$1 + du * t);
        _vs.add(a.$2 + dv * t);
        at += _spacing;
      }
      carried = segment - (at - _spacing);
    }
    length = (_us.length - 1) * _spacing;
    var start = 0.0;
    var end = length;
    for (var i = 0; i < _vs.length; i += 1) {
      if (_vs[i] < 10) {
        start = i * _spacing;
      }
      if (_vs[i] > 36.5 && end == length) {
        end = i * _spacing;
      }
    }
    bridgeStart = start;
    bridgeEnd = end;
  }

  bool isBridge(double s) => s >= bridgeStart && s <= bridgeEnd;

  /// A gentle arch over the river, level everywhere else.
  double _heightAt(double s) {
    if (!isBridge(s)) {
      return _deckY;
    }
    final arch = math.sin(
      (s - bridgeStart) / (bridgeEnd - bridgeStart) * math.pi,
    );
    return _deckY + 1.0 * arch * arch;
  }

  /// The road at [distance] along it; any distance wraps onto the road.
  _RoadPoint at(double distance) {
    final s = (distance % length + length) % length;
    final f = s / _spacing;
    final i = math.min(f.floor(), _us.length - 2);
    final t = f - i;
    final u = _us[i] + (_us[i + 1] - _us[i]) * t;
    final v = _vs[i] + (_vs[i + 1] - _vs[i]) * t;
    // Heading from a wider baseline, so cars turn smoothly through curves.
    final a = math.max(0, i - 1);
    final b = math.min(_us.length - 1, i + 2);
    final heading = math.atan2(_vs[b] - _vs[a], _us[b] - _us[a]);
    final slope = math.atan2(
      _heightAt(math.min(s + 0.5, length)) - _heightAt(math.max(s - 0.5, 0)),
      1,
    );
    return _RoadPoint(u, v, _heightAt(s), heading, slope);
  }

  double distanceTo(double u, double v) {
    var best = double.infinity;
    for (var i = 0; i < _us.length; i += 4) {
      final du = _us[i] - u;
      final dv = _vs[i] - v;
      best = math.min(best, du * du + dv * dv);
    }
    return math.sqrt(best);
  }

  /// Deck height at the point of the road nearest (u, v).
  double heightNear(double u, double v) {
    var best = double.infinity;
    var bestIndex = 0;
    for (var i = 0; i < _us.length; i += 1) {
      final du = _us[i] - u;
      final dv = _vs[i] - v;
      final d = du * du + dv * dv;
      if (d < best) {
        best = d;
        bestIndex = i;
      }
    }
    return _heightAt(bestIndex * _spacing);
  }
}

class _Car {
  _Car({
    required this.mesh,
    required this.body,
    required this.distance,
    required this.speed,
    required this.forward,
  });

  final three.Mesh mesh;
  final _LitMesh body;
  double distance;
  final double speed;
  final bool forward;
}
