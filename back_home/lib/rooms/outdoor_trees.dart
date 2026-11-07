part of 'outdoor_landscape.dart';

/// Trees shared by every scene. Crowns are sprays of painted leaves carried on
/// a frame of branches, lit yellow on top and shaded emerald beneath; conifers
/// are needled boughs around a dark core. Trees spend their detail by distance
/// from the window.
extension _TreeKit on OutdoorScene {
  static const _sunlit = _Rgb.hex(0xFFF27A);

  double _distanceToWindow(double x, double y, double z) {
    final dx = x - OutdoorScene._eyeX;
    final dy = y - OutdoorScene._eyeY;
    final dz = z - _eyeZ;
    return math.sqrt(dx * dx + dy * dy + dz * dz);
  }

  _Rgb _leafLight(_Rgb color) => _Rgb.lerp(color, _sunlit, 0.38).scale(1.08);

  // Shade goes cool rather than just darker, which keeps the crown colourful.
  _Rgb _leafShade(_Rgb color) =>
      _Rgb(color.r * 0.5, color.g * 0.6, color.b * 0.8);

  void _addBroadleaf(
    _LitMesh foliage,
    _LitMesh solids,
    math.Random random,
    double x,
    double baseY,
    double z,
    double scale,
    _Rgb color, {
    double birchChance = 0.15,
    double tallChance = 0.3,
    int maxDetail = 2,
  }) {
    final distance = _distanceToWindow(x, baseY, z);
    final detail = math.min(
      maxDetail,
      distance < 17 ? 2 : (distance < 27 ? 1 : 0),
    );
    final tall = random.nextDouble() < tallChance;
    final birch = random.nextDouble() < birchChance;
    final trunkHeight =
        (tall ? 1.7 : 1.35) * scale + random.nextDouble() * 0.45;
    final radius = (tall ? 1.3 : 1.7) * scale;
    final stretch = tall ? 1.4 : 0.86;
    final centerY = baseY + trunkHeight + radius * stretch * 0.62;
    final center = (x, centerY, z);
    final bottom = centerY - radius * stretch * 0.75;
    final top = centerY + radius * stretch;

    final bark = birch ? const _Rgb.hex(0xE2DED3) : const _Rgb.hex(0x6E5244);
    final barkLight = birch
        ? const _Rgb.hex(0xF2EFE6)
        : const _Rgb.hex(0x8A6A54);
    _addTrunk(
      solids,
      random,
      x,
      baseY,
      z,
      scale,
      trunkHeight,
      bark,
      barkLight,
      detail,
    );

    _addCrown(
      foliage,
      solids,
      random,
      center: center,
      fork: (x, baseY + trunkHeight * 0.82, z),
      radius: radius,
      stretch: stretch,
      bottom: bottom,
      top: top,
      scale: scale,
      color: color,
      bark: bark,
      detail: detail,
    );
    _shadows.add(
      _TreeShadow(x: x, z: z, radius: radius * 1.08, height: centerY - baseY),
    );
  }

  /// A crown of real boughs: limbs fork out to tips spread over the top and
  /// shoulders of the tree, and each tip carries sprays of leaves. The underside
  /// stays open, so branches show and light gets between the boughs.
  void _addCrown(
    _LitMesh foliage,
    _LitMesh solids,
    math.Random random, {
    required (double, double, double) center,
    required (double, double, double) fork,
    required double radius,
    required double stretch,
    required double bottom,
    required double top,
    required double scale,
    required _Rgb color,
    required _Rgb bark,
    required int detail,
  }) {
    final (x, centerY, z) = center;
    final limbs = switch (detail) {
      2 => 6,
      1 => 4,
      _ => 0,
    };
    final spin = random.nextDouble() * math.pi * 2;
    final elbows = <(double, double, double)>[];
    for (var i = 0; i < limbs; i += 1) {
      final a =
          spin + i / limbs * math.pi * 2 + (random.nextDouble() - 0.5) * 0.5;
      final out = radius * (0.34 + random.nextDouble() * 0.14);
      final elbow = (
        fork.$1 + math.cos(a) * out,
        fork.$2 + (centerY - fork.$2) * (0.7 + random.nextDouble() * 0.5),
        fork.$3 + math.sin(a) * out,
      );
      elbows.add(elbow);
      _addLimb(
        solids,
        fork,
        elbow,
        scale * 0.1,
        scale * 0.055,
        bark,
        sides: detail == 2 ? 6 : 4,
      );
    }

    final tips = switch (detail) {
      2 => 20,
      1 => 11,
      _ => 6,
    };
    final sprays = switch (detail) {
      2 => 9,
      1 => 5,
      _ => 3,
    };
    final sprayHalf = switch (detail) {
      2 => 0.27,
      1 => 0.4,
      _ => 0.6,
    };
    for (var i = 0; i < tips; i += 1) {
      // Spiral over the crown from just below its waist up to the very top.
      final t = (i + 0.5) / tips;
      final rise = -0.42 + t * 1.38;
      final ring = math.sqrt(math.max(1 - rise * rise, 0.0));
      final a = i * 2.39996 + spin + (random.nextDouble() - 0.5) * 0.5;
      final out = radius * ring * (0.72 + random.nextDouble() * 0.26);
      final tip = (
        x + math.cos(a) * out,
        centerY + rise * radius * stretch * (0.8 + random.nextDouble() * 0.2),
        z + math.sin(a) * out,
      );
      if (elbows.isNotEmpty) {
        // Carried on a branch from the nearest limb.
        var best = elbows.first;
        var bestDistance = double.infinity;
        for (final elbow in elbows) {
          final dx = elbow.$1 - tip.$1;
          final dy = elbow.$2 - tip.$2;
          final dz = elbow.$3 - tip.$3;
          final d = dx * dx + dy * dy + dz * dz;
          if (d < bestDistance) {
            bestDistance = d;
            best = elbow;
          }
        }
        if (detail == 2 || i.isEven) {
          _addLimb(
            solids,
            best,
            tip,
            scale * 0.045,
            scale * 0.016,
            bark,
            sides: 4,
          );
        }
      }
      for (var c = 0; c < sprays; c += 1) {
        final spread = radius * sprayHalf * 1.15;
        final cx = tip.$1 + (random.nextDouble() - 0.5) * 2 * spread;
        final cy =
            tip.$2 + (random.nextDouble() - 0.5) * 1.3 * spread * stretch;
        final cz = tip.$3 + (random.nextDouble() - 0.5) * 2 * spread;
        _addLeafCard(
          random,
          cx,
          cy,
          cz,
          radius * sprayHalf * (0.8 + random.nextDouble() * 0.4),
          color,
          center: center,
          reach: radius,
          bottom: bottom,
          top: top,
          atlasCell: c == 0
              ? _LeafAtlas.loose
              : (c.isEven ? _LeafAtlas.denseA : _LeafAtlas.denseB),
        );
      }
    }
    // A dim core blocks the sky through the middle of the crown.
    _addLeafChunk(
      foliage,
      random,
      x,
      centerY + radius * stretch * 0.1,
      z,
      radius * 0.5,
      _leafShade(color).scale(0.6),
      center: center,
      bottom: top,
      top: top + 1,
      detail: 0,
    );
  }

  /// One spray of leaves. The window is the only place the scenery is seen
  /// from, so cards lean toward it and never turn edge-on to the viewer.
  void _addLeafCard(
    math.Random random,
    double cx,
    double cy,
    double cz,
    double half,
    _Rgb color, {
    required (double, double, double) center,
    required double reach,
    required double bottom,
    required double top,
    required int atlasCell,
  }) {
    var ex = OutdoorScene._eyeX - cx;
    var ey = OutdoorScene._eyeY - cy;
    var ez = _eyeZ - cz;
    final el = math.sqrt(ex * ex + ey * ey + ez * ez) + 1e-6;
    ex /= el;
    ey /= el;
    ez /= el;
    final ox = (cx - center.$1) / reach;
    final oy = (cy - center.$2) / reach;
    final oz = (cz - center.$3) / reach;
    var nx = ex * 0.9 + ox * 0.35 + (random.nextDouble() - 0.5) * 0.6;
    var ny = ey * 0.9 + oy * 0.35 + (random.nextDouble() - 0.5) * 0.6;
    var nz = ez * 0.9 + oz * 0.35 + (random.nextDouble() - 0.5) * 0.6;
    final nl = math.sqrt(nx * nx + ny * ny + nz * nz) + 1e-6;
    nx /= nl;
    ny /= nl;
    nz /= nl;
    final (rx, ry, rz) = ny.abs() < 0.9 ? (0.0, 1.0, 0.0) : (1.0, 0.0, 0.0);
    var tx = ry * nz - rz * ny;
    var ty = rz * nx - rx * nz;
    var tz = rx * ny - ry * nx;
    final tl = math.sqrt(tx * tx + ty * ty + tz * tz) + 1e-6;
    tx /= tl;
    ty /= tl;
    tz /= tl;
    final bx = ny * tz - nz * ty;
    final by = nz * tx - nx * tz;
    final bz = nx * ty - ny * tx;
    final roll = random.nextDouble() * math.pi * 2;
    final cr = math.cos(roll) * half;
    final sr = math.sin(roll) * half;

    final heightT = ((cy - bottom) / (top - bottom)).clamp(0.0, 1.0);
    final ramp = (heightT * 0.8 + random.nextDouble() * 0.32).clamp(0.0, 1.0);
    final tone = ramp > 0.5
        ? _Rgb.lerp(color, _leafLight(color), (ramp - 0.5) * 2)
        : _Rgb.lerp(_leafShade(color), color, ramp * 2);
    final card = tone.scale(1.25 + random.nextDouble() * 0.25);

    final (u0, v0, u1, v1) = _LeafAtlas.instance.cell(atlasCell);
    final base = _leaves.count;
    for (final (a, b, u, v) in [
      (-1.0, -1.0, u0, v0),
      (1.0, -1.0, u1, v0),
      (1.0, 1.0, u1, v1),
      (-1.0, 1.0, u0, v1),
    ]) {
      final px = cx + (tx * cr + bx * sr) * a + (-tx * sr + bx * cr) * b;
      final py = cy + (ty * cr + by * sr) * a + (-ty * sr + by * cr) * b;
      final pz = cz + (tz * cr + bz * sr) * a + (-tz * sr + bz * cr) * b;
      // Normals fan out from the crown, so it shades as one rounded mass.
      var vx = (px - center.$1) / reach;
      var vy = (py - center.$2) / reach + 0.2;
      var vz = (pz - center.$3) / reach;
      final vl = math.sqrt(vx * vx + vy * vy + vz * vz) + 1e-6;
      final depth = (vl / 1.1).clamp(0.0, 1.0);
      vx /= vl;
      vy /= vl;
      vz /= vl;
      _leaves.vertex(
        px,
        py,
        pz,
        vx,
        vy,
        vz,
        card,
        ao: 0.36 + 0.38 * depth + 0.26 * ramp,
      );
      _leaves._uvs.addAll([u, v]);
    }
    _leaves.indices!.addAll([
      base,
      base + 1,
      base + 2,
      base,
      base + 2,
      base + 3,
    ]);
  }

  /// A conifer bough: a needled card from the trunk to its drooping tip,
  /// turned about its own length to show its broad side to the window.
  void _addBough(
    (double, double, double) root,
    (double, double, double) tip,
    double width,
    _Rgb color, {
    required double rootShade,
    required double tipShade,
  }) {
    final ax = tip.$1 - root.$1;
    final ay = tip.$2 - root.$2;
    final az = tip.$3 - root.$3;
    final mx = (root.$1 + tip.$1) / 2;
    final my = (root.$2 + tip.$2) / 2;
    final mz = (root.$3 + tip.$3) / 2;
    final ex = OutdoorScene._eyeX - mx;
    final ey = OutdoorScene._eyeY - my;
    final ez = _eyeZ - mz;
    var wx = ay * ez - az * ey;
    var wy = az * ex - ax * ez;
    var wz = ax * ey - ay * ex;
    final wl = math.sqrt(wx * wx + wy * wy + wz * wz);
    if (wl < 1e-5) {
      return;
    }
    final half = width / 2 / wl;
    wx *= half;
    wy *= half;
    wz *= half;
    final al = math.sqrt(ax * ax + ay * ay + az * az) + 1e-6;
    final nx = ax / al * 0.7;
    final ny = 0.7;
    final nz = az / al * 0.7;
    final (u0, v0, u1, v1) = _LeafAtlas.instance.cell(_LeafAtlas.bough);
    final base = _leaves.count;
    for (final (p, side, v, ao) in [
      (root, -1.0, v0, rootShade),
      (root, 1.0, v0, rootShade),
      (tip, 1.0, v1, tipShade),
      (tip, -1.0, v1, tipShade),
    ]) {
      _leaves.vertex(
        p.$1 + wx * side,
        p.$2 + wy * side,
        p.$3 + wz * side,
        nx,
        ny,
        nz,
        color,
        ao: ao,
      );
      _leaves._uvs.addAll([side < 0 ? u0 : u1, v]);
    }
    _leaves.indices!.addAll([
      base,
      base + 1,
      base + 2,
      base,
      base + 2,
      base + 3,
    ]);
  }

  void _addTrunk(
    _LitMesh mesh,
    math.Random random,
    double x,
    double baseY,
    double z,
    double scale,
    double trunkHeight,
    _Rgb bark,
    _Rgb barkLight,
    int detail,
  ) {
    final sides = detail == 0 ? 5 : 8;
    final foot = (x, baseY - 0.12, z);
    if (detail == 0) {
      _addLimb(
        mesh,
        foot,
        (x, baseY + trunkHeight * 0.95, z),
        scale * 0.17,
        scale * 0.09,
        bark,
        sides: sides,
      );
      return;
    }
    // A flared, lighter foot that narrows into the main stem, with a lean.
    final leanX = (random.nextDouble() - 0.5) * scale * 0.18;
    final leanZ = (random.nextDouble() - 0.5) * scale * 0.18;
    final waist = (x + leanX * 0.4, baseY + trunkHeight * 0.3, z + leanZ * 0.4);
    final forkPoint = (x + leanX, baseY + trunkHeight * 0.85, z + leanZ);
    _addLimb(
      mesh,
      foot,
      waist,
      scale * 0.31,
      scale * 0.17,
      barkLight,
      sides: sides,
    );
    _addLimb(
      mesh,
      waist,
      forkPoint,
      scale * 0.17,
      scale * 0.13,
      bark,
      sides: sides,
    );
    if (detail == 2) {
      // Roots spreading into the ground.
      final roots = 4 + random.nextInt(2);
      for (var i = 0; i < roots; i += 1) {
        final a = i / roots * math.pi * 2 + random.nextDouble() * 0.6;
        final reach = scale * (0.42 + random.nextDouble() * 0.28);
        _addLimb(
          mesh,
          (x, baseY + scale * 0.2, z),
          (x + math.cos(a) * reach, baseY - 0.14, z + math.sin(a) * reach),
          scale * 0.11,
          scale * 0.025,
          barkLight,
          sides: 5,
        );
      }
    }
  }

  /// A tapered, faceted branch from one point to another.
  void _addLimb(
    _LitMesh mesh,
    (double, double, double) from,
    (double, double, double) to,
    double fromRadius,
    double toRadius,
    _Rgb color, {
    required int sides,
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
    final (ax, ay, az) = dy.abs() < 0.9 ? (0.0, 1.0, 0.0) : (1.0, 0.0, 0.0);
    var px = dy * az - dz * ay;
    var py = dz * ax - dx * az;
    var pz = dx * ay - dy * ax;
    final pl = math.sqrt(px * px + py * py + pz * pz);
    px /= pl;
    py /= pl;
    pz /= pl;
    final qx = dy * pz - dz * py;
    final qy = dz * px - dx * pz;
    final qz = dx * py - dy * px;
    (double, double, double) ring(
      (double, double, double) o,
      double r,
      double a,
    ) {
      final c = math.cos(a) * r;
      final s = math.sin(a) * r;
      return (
        o.$1 + px * c + qx * s,
        o.$2 + py * c + qy * s,
        o.$3 + pz * c + qz * s,
      );
    }

    for (var i = 0; i < sides; i += 1) {
      final a0 = i / sides * math.pi * 2;
      final a1 = (i + 1) / sides * math.pi * 2;
      _addQuad(
        mesh,
        ring(from, fromRadius, a0),
        ring(from, fromRadius, a1),
        ring(to, toRadius, a1),
        ring(to, toRadius, a0),
        color.scale(0.88 + (i % 3) * 0.1),
      );
    }
  }

  /// One faceted clump of leaves: an irregular, turned polyhedron with crisp
  /// flat faces, brightening with its height in the crown.
  void _addLeafChunk(
    _LitMesh mesh,
    math.Random random,
    double cx,
    double cy,
    double cz,
    double size,
    _Rgb color, {
    required (double, double, double) center,
    required double bottom,
    required double top,
    required int detail,
  }) {
    final unit = _unitIcosahedron(0);
    final yaw = random.nextDouble() * math.pi * 2;
    final tilt = (random.nextDouble() - 0.5) * 0.7;
    final cy0 = math.cos(yaw);
    final sy0 = math.sin(yaw);
    final ct = math.cos(tilt);
    final st = math.sin(tilt);
    // Broader than tall, so top faces catch the light like the reference.
    final sx = size * (1.0 + random.nextDouble() * 0.25);
    final sy = size * (0.8 + random.nextDouble() * 0.25);
    final sz = size * (0.9 + random.nextDouble() * 0.25);
    final seed = random.nextInt(1 << 20);
    final heightT = ((cy - bottom) / (top - bottom)).clamp(0.0, 1.0);
    // Each chunk gets its own step along the shade-to-sunlit ramp.
    final ramp = (heightT * 0.85 + random.nextDouble() * 0.3).clamp(0.0, 1.0);
    final base = _Rgb.lerp(
      _leafShade(color),
      color,
      (ramp * 2).clamp(0.0, 1.0),
    );
    final chunkColor = ramp > 0.5
        ? _Rgb.lerp(color, _leafLight(color), (ramp - 0.5) * 2)
        : base;
    for (var i = 0; i < unit.length; i += 9) {
      final p = List<double>.filled(9, 0);
      for (var k = 0; k < 3; k += 1) {
        final ux = unit[i + k * 3];
        final uy = unit[i + k * 3 + 1];
        final uz = unit[i + k * 3 + 2];
        // Shared corners displace identically, so the chunk stays closed.
        final bump =
            0.66 +
            0.66 *
                _hash3(
                  (ux * 991).round() + seed,
                  (uy * 991).round(),
                  (uz * 991).round() + seed * 3,
                );
        final lx = ux * sx * bump;
        final ly0 = uy * sy * bump;
        final lz0 = uz * sz * bump;
        // Tilt about x, then yaw about y: a rotation, so winding holds.
        final ly = ly0 * ct - lz0 * st;
        final lz = ly0 * st + lz0 * ct;
        p[k * 3] = cx + lx * cy0 + lz * sy0;
        p[k * 3 + 1] = cy + ly;
        p[k * 3 + 2] = cz - lx * sy0 + lz * cy0;
      }
      final n = _faceNormal(p);
      final faceColor = chunkColor.scale(0.96 + random.nextDouble() * 0.08);
      for (var k = 0; k < 3; k += 1) {
        final x = p[k * 3];
        final y = p[k * 3 + 1];
        final z = p[k * 3 + 2];
        // Half faceted, half round, so chunks read as clumps of leaves and
        // not as cut blocks with hard shaded sides.
        var nx = n.$1 * 0.5 + (x - cx) / size * 0.5;
        var ny = n.$2 * 0.5 + (y - cy) / size * 0.5;
        var nz = n.$3 * 0.5 + (z - cz) / size * 0.5;
        final nl = math.sqrt(nx * nx + ny * ny + nz * nz);
        nx /= nl;
        ny /= nl;
        nz /= nl;
        // Self-shadow toward the middle of the crown and its underside.
        final ox = x - center.$1;
        final oy = y - center.$2;
        final oz = z - center.$3;
        final out = math.sqrt(ox * ox + oy * oy + oz * oz);
        final reach = (top - center.$2).abs() + 0.001;
        final depth = (out / reach).clamp(0.0, 1.0);
        final ao = 0.42 + 0.33 * depth + 0.25 * ramp;
        mesh.vertex(x, y, z, nx, ny, nz, faceColor, ao: ao);
      }
    }
  }

  /// Low undergrowth: a mound of leaf sprays.
  void _addShrub(
    _LitMesh foliage,
    math.Random random,
    double x,
    double y,
    double z,
    double size,
    _Rgb color,
  ) {
    final near = _distanceToWindow(x, y, z) < 16;
    final count = near ? 9 : 4;
    final center = (x, y, z);
    final half = size * (near ? 0.5 : 0.72);
    for (var i = 0; i < count; i += 1) {
      final a = random.nextDouble() * math.pi * 2;
      final spread = size * 0.62 * math.sqrt(random.nextDouble());
      _addLeafCard(
        random,
        x + math.cos(a) * spread,
        y + size * (0.12 + random.nextDouble() * 0.62),
        z + math.sin(a) * spread,
        half * (0.8 + random.nextDouble() * 0.4),
        color,
        center: center,
        reach: size,
        bottom: y - size * 0.2,
        top: y + size,
        atlasCell: i == 0
            ? _LeafAtlas.loose
            : (i.isEven ? _LeafAtlas.denseA : _LeafAtlas.denseB),
      );
    }
  }

  void _addConifer(
    _LitMesh foliage,
    _LitMesh solids,
    math.Random random,
    double x,
    double baseY,
    double z,
    double scale, {
    _Rgb dark = const _Rgb.hex(0x24533A),
    _Rgb light = const _Rgb.hex(0x4A8240),
    int tiers = 3,
    int sides = 7,
    double slender = 1,
    bool castShadow = true,
  }) {
    final distance = _distanceToWindow(x, baseY, z);
    // Jagged boughs near the window; plain cones only where they can't be read.
    final jagged = distance < 48;
    final near = distance < 26;
    final tierCount = near ? tiers + 2 : tiers;
    final teeth = near ? 9 : (jagged ? 6 : sides);
    final total = (3.6 + random.nextDouble() * 1.6) * scale * slender;
    _addLimb(
      solids,
      (x, baseY - 0.1, z),
      (x, baseY + total * 0.55, z),
      scale * 0.14,
      scale * 0.05,
      const _Rgb.hex(0x5A4638),
      sides: near ? 5 : 4,
    );
    final hue = random.nextDouble();
    if (jagged) {
      // A dark inner cone keeps the tree solid; boughs give it its outline.
      _addConeTier(
        foliage,
        random,
        x,
        baseY + total * 0.2,
        z,
        scale * 0.62,
        total * 0.8,
        _Rgb.lerp(dark, const _Rgb(0, 0, 0), 0.4),
        dark,
        teeth: 7,
        jagged: false,
        aoBase: 0.45,
      );
      final whorls = near ? 15 : 8;
      final perWhorl = near ? 7 : 5;
      for (var w = 0; w < whorls; w += 1) {
        final t = w / whorls;
        final y = baseY + total * (0.2 + t * 0.78);
        final twist = random.nextDouble() * math.pi * 2;
        for (var i = 0; i < perWhorl; i += 1) {
          final a = twist + i / perWhorl * math.pi * 2;
          final length =
              scale * (1.5 - 1.3 * t) * (0.85 + random.nextDouble() * 0.3);
          final droop = 0.2 + (1 - t) * 0.42 + random.nextDouble() * 0.15;
          final tip = (
            x + math.cos(a) * math.cos(droop) * length,
            y - math.sin(droop) * length,
            z + math.sin(a) * math.cos(droop) * length,
          );
          final tone = _Rgb.lerp(
            _Rgb.lerp(dark, light, 0.35 + t * 0.5 + hue * 0.15),
            _sunlit,
            0.05 + t * 0.1,
          ).scale(1.35 + random.nextDouble() * 0.3);
          _addBough(
            (x, y, z),
            tip,
            length * 0.72,
            tone,
            rootShade: 0.42,
            tipShade: 0.72 + t * 0.28,
          );
        }
      }
    } else {
      for (var tier = 0; tier < tierCount; tier += 1) {
        final t = tier / tierCount;
        final tierBase = baseY + total * (0.2 + t * 0.56);
        final tierHeight = total * (0.46 - t * 0.14);
        final radius = scale * (1.22 - t * 0.86);
        // Tiers brighten toward the tip, where the light reaches.
        final tierDark = _Rgb.lerp(dark, light, t * 0.45 + hue * 0.2);
        final tierLight = _Rgb.lerp(
          light,
          _sunlit,
          0.1 + t * 0.14,
        ).scale(0.95 + hue * 0.15);
        _addConeTier(
          foliage,
          random,
          x,
          tierBase,
          z,
          radius,
          tierHeight,
          tierDark,
          tierLight,
          teeth: teeth,
          jagged: false,
          aoBase: 0.5 + t * 0.28,
        );
      }
    }
    if (castShadow) {
      _shadows.add(
        _TreeShadow(x: x, z: z, radius: scale * 1.05, height: total * 0.55),
      );
    }
  }

  /// A skirt of boughs. Jagged tiers alternate long drooping tips with short
  /// notches around the rim, each facet shaded on its own.
  void _addConeTier(
    _LitMesh mesh,
    math.Random random,
    double x,
    double baseY,
    double z,
    double radius,
    double height,
    _Rgb dark,
    _Rgb light, {
    required int teeth,
    required bool jagged,
    required double aoBase,
  }) {
    final twist = random.nextDouble() * math.pi * 2;
    final count = jagged ? teeth * 2 : teeth;
    final apex = (x, baseY + height, z);
    (double, double, double) rim(int i) {
      final a = twist + i / count * math.pi * 2;
      final tip = !jagged || i.isEven;
      final r = radius * (tip ? 1.0 : 0.68);
      final y =
          baseY -
          (jagged && tip ? height * 0.12 : 0) +
          (tip ? 0 : height * 0.1);
      return (x + math.cos(a) * r, y, z + math.sin(a) * r);
    }

    for (var i = 0; i < count; i += 1) {
      final a = rim(i);
      final b = rim((i + 1) % count);
      final n = _faceNormal([
        a.$1,
        a.$2,
        a.$3,
        apex.$1,
        apex.$2,
        apex.$3,
        b.$1,
        b.$2,
        b.$3,
      ]);
      final face = _Rgb.lerp(dark, light, random.nextDouble() * 0.35 + 0.3);
      final tipColor = i.isEven ? light : face;
      final notchColor = i.isEven ? face : light;
      mesh
        ..vertex(a.$1, a.$2, a.$3, n.$1, n.$2, n.$3, tipColor, ao: aoBase)
        ..vertex(apex.$1, apex.$2, apex.$3, n.$1, n.$2, n.$3, dark, ao: 1)
        ..vertex(b.$1, b.$2, b.$3, n.$1, n.$2, n.$3, notchColor, ao: aoBase);
    }
  }
}
