part of 'outdoor_landscape.dart';

/// Stylised trees shared by every scene. Crowns are built from many separate
/// faceted leaf chunks on an open frame of branches, lit yellow on top and
/// shaded emerald beneath; conifers from jagged, overlapping tiers. Trees
/// spend their detail by distance from the window.
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

    // Boughs: one crowning the tree, the rest in a ring around its shoulders,
    // leaving the underside open so the branches show.
    final lobeCount = switch (detail) {
      2 => 8,
      1 => 5,
      _ => 4,
    };
    final fork = (x, baseY + trunkHeight * 0.82, z);
    final spin = random.nextDouble() * math.pi * 2;
    for (var i = 0; i < lobeCount; i += 1) {
      final double lx;
      final double ly;
      final double lz;
      if (i == 0) {
        lx = (random.nextDouble() - 0.5) * radius * 0.25;
        ly = radius * stretch * 0.62;
        lz = (random.nextDouble() - 0.5) * radius * 0.25;
      } else {
        final a =
            spin +
            (i - 1) / (lobeCount - 1) * math.pi * 2 +
            (random.nextDouble() - 0.5) * 0.5;
        // Alternate a wide lower ring and a tighter upper one, for volume.
        final upper = i.isEven;
        final out =
            radius * ((upper ? 0.4 : 0.66) + random.nextDouble() * 0.14);
        lx = math.cos(a) * out;
        ly =
            radius *
            stretch *
            ((upper ? 0.34 : -0.06) + random.nextDouble() * 0.16);
        lz = math.sin(a) * out;
      }
      final lobe = (x + lx, centerY + ly, z + lz);
      // Visible limbs reach out from the fork to carry each bough.
      if (detail > 0 && (detail == 2 || i <= 3)) {
        final thick = scale * (detail == 2 ? 0.085 : 0.1);
        final elbow = (
          fork.$1 + lx * 0.45,
          fork.$2 + (lobe.$2 - fork.$2) * 0.42,
          fork.$3 + lz * 0.45,
        );
        _addLimb(solids, fork, elbow, thick, thick * 0.72, bark, sides: 5);
        if (detail == 2) {
          _addLimb(
            solids,
            elbow,
            lobe,
            thick * 0.72,
            thick * 0.4,
            bark,
            sides: 5,
          );
        }
      }
      final chunks = switch (detail) {
        2 => 6 + random.nextInt(2),
        1 => 3,
        _ => 1,
      };
      for (var c = 0; c < chunks; c += 1) {
        final spread = chunks == 1 ? 0.0 : radius * 0.34;
        final size =
            radius *
            switch (detail) {
              2 => 0.25 + random.nextDouble() * 0.11,
              1 => 0.36 + random.nextDouble() * 0.1,
              _ => 0.56 + random.nextDouble() * 0.1,
            };
        final cx = lobe.$1 + (random.nextDouble() - 0.5) * 2 * spread;
        final cy =
            lobe.$2 + (random.nextDouble() - 0.5) * 1.4 * spread * stretch;
        final cz = lobe.$3 + (random.nextDouble() - 0.5) * 2 * spread;
        _addLeafChunk(
          foliage,
          random,
          cx,
          cy,
          cz,
          size,
          color,
          center: center,
          bottom: bottom,
          top: top,
          detail: detail,
        );
      }
      // Loose leaves stand off each bough and break up its outline.
      final plates = detail == 2 ? 5 : (detail == 1 ? 2 : 0);
      for (var c = 0; c < plates; c += 1) {
        _addLeafPlate(
          foliage,
          random,
          lobe,
          center,
          radius * (detail == 2 ? 0.46 : 0.56),
          radius * (detail == 2 ? 0.26 : 0.34),
          color,
          bottom: bottom,
          top: top,
        );
      }
    }
    if (detail > 0) {
      // A dim core blocks the sky through the crown without a smooth blob.
      _addLeafChunk(
        foliage,
        random,
        x,
        centerY + radius * stretch * 0.12,
        z,
        radius * 0.6,
        _leafShade(color).scale(0.72),
        center: center,
        bottom: top,
        top: top + 1,
        detail: 0,
      );
    }
    _shadows.add(
      _TreeShadow(x: x, z: z, radius: radius * 1.08, height: centerY - baseY),
    );
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

  /// A single pointed leaf, folded along its spine and visible from both
  /// sides, pointing out and away from the middle of the crown.
  void _addLeafPlate(
    _LitMesh mesh,
    math.Random random,
    (double, double, double) lobe,
    (double, double, double) center,
    double reach,
    double size,
    _Rgb color, {
    required double bottom,
    required double top,
  }) {
    // Outward from the crown, scattered, with a slight droop.
    var dx = lobe.$1 - center.$1 + (random.nextDouble() - 0.5) * reach * 2.2;
    var dy = lobe.$2 - center.$2 + (random.nextDouble() - 0.7) * reach * 1.4;
    var dz = lobe.$3 - center.$3 + (random.nextDouble() - 0.5) * reach * 2.2;
    final dl = math.sqrt(dx * dx + dy * dy + dz * dz) + 0.0001;
    dx /= dl;
    dy /= dl;
    dz /= dl;
    final base = (
      lobe.$1 + dx * reach * 0.52,
      lobe.$2 + dy * reach * 0.52,
      lobe.$3 + dz * reach * 0.52,
    );
    // A sideways axis, with a random roll so leaves catch light differently.
    var sx = -dz + (random.nextDouble() - 0.5) * 0.6;
    var sy = 0.25 * (random.nextDouble() - 0.5);
    var sz = dx + (random.nextDouble() - 0.5) * 0.6;
    final sl = math.sqrt(sx * sx + sy * sy + sz * sz) + 0.0001;
    sx /= sl;
    sy /= sl;
    sz /= sl;
    final length = size * (0.8 + random.nextDouble() * 0.5);
    final half = length * 0.34;
    (double, double, double) along(double t, double side, double lift) => (
      base.$1 + dx * length * t + sx * half * side,
      base.$2 + dy * length * t + sy * half * side + lift * length,
      base.$3 + dz * length * t + sz * half * side,
    );
    final tail = along(0, 0, 0);
    final tip = along(1, 0, 0);
    final left = along(0.42, -1, -0.09);
    final right = along(0.42, 1, -0.09);
    final heightT = ((base.$2 - bottom) / (top - bottom)).clamp(0.0, 1.0);
    final ramp = (heightT * 0.85 + random.nextDouble() * 0.3).clamp(0.0, 1.0);
    final leaf = ramp > 0.5
        ? _Rgb.lerp(color, _leafLight(color), (ramp - 0.5) * 2)
        : _Rgb.lerp(_leafShade(color), color, ramp * 2);
    for (final (a, b, c) in [
      (tail, right, tip),
      (tail, tip, left),
      (tail, tip, right),
      (tail, left, tip),
    ]) {
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
          leaf,
          ao: 0.6 + 0.4 * ramp,
        );
      }
    }
  }

  /// Low undergrowth: a few leaf chunks instead of a single blob.
  void _addShrub(
    _LitMesh foliage,
    math.Random random,
    double x,
    double y,
    double z,
    double size,
    _Rgb color,
  ) {
    final count = 2 + random.nextInt(2);
    for (var i = 0; i < count; i += 1) {
      final a = random.nextDouble() * math.pi * 2;
      final spread = size * 0.55 * random.nextDouble();
      _addLeafChunk(
        foliage,
        random,
        x + math.cos(a) * spread,
        y + random.nextDouble() * size * 0.5,
        z + math.sin(a) * spread,
        size * (0.45 + random.nextDouble() * 0.2),
        color,
        center: (x, y, z),
        bottom: y - size * 0.4,
        top: y + size,
        detail: 1,
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
        jagged: jagged,
        aoBase: 0.5 + t * 0.28,
      );
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
