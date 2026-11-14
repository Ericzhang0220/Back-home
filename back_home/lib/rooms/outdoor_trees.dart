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
    final (fork, rise) = _addTrunk(
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
      birch: birch,
    );

    _addCrown(
      foliage,
      solids,
      random,
      center: center,
      fork: fork,
      rise: rise,
      trunkRadius: scale * 0.115,
      radius: radius,
      stretch: stretch,
      bottom: bottom,
      top: top,
      scale: scale,
      color: color,
      bark: bark,
      barkCell: birch ? _LeafAtlas.birchBark : _LeafAtlas.bark,
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
    required (double, double, double) rise,
    required double trunkRadius,
    required double radius,
    required double stretch,
    required double bottom,
    required double top,
    required double scale,
    required _Rgb color,
    required _Rgb bark,
    required int barkCell,
    required int detail,
  }) {
    final (x, centerY, z) = center;
    // The trunk carries on up through the crown as a tapering leader; the
    // main limbs leave it at staggered heights and curve up and out, and
    // twigs leave the limbs partway along. Every branch starts inside its
    // parent at a matching thickness, so the wood reads as one piece.
    final limbCount = switch (detail) {
      2 => 6,
      1 => 4,
      _ => 0,
    };
    final spin = random.nextDouble() * math.pi * 2;
    final limbs =
        <
          (
            (double, double, double),
            (double, double, double),
            (double, double, double),
            double,
            double,
          )
        >[];
    if (detail > 0) {
      final leaderLength = centerY + radius * stretch * 0.45 - fork.$2;
      final leaderEnd = (
        x + (random.nextDouble() - 0.5) * radius * 0.2,
        centerY + radius * stretch * 0.45,
        z + (random.nextDouble() - 0.5) * radius * 0.2,
      );
      final leaderBend = (
        fork.$1 + rise.$1 * leaderLength * 0.45,
        fork.$2 + rise.$2 * leaderLength * 0.45,
        fork.$3 + rise.$3 * leaderLength * 0.45,
      );
      final leaderTip = scale * 0.025;
      _addBranch(
        fork,
        leaderBend,
        leaderEnd,
        trunkRadius,
        leaderTip,
        color: bark,
        barkCell: barkCell,
        sides: detail == 2 ? 12 : 8,
        rings: detail == 2 ? 7 : 4,
      );
      for (var k = 0; k < limbCount; k += 1) {
        final along = 0.06 + 0.6 * k / math.max(1, limbCount - 1);
        final start = _curvePoint(fork, leaderBend, leaderEnd, along);
        final parent = trunkRadius + (leaderTip - trunkRadius) * along;
        final a = spin + k * 2.39996 + (random.nextDouble() - 0.5) * 0.4;
        final length = radius * (0.62 + random.nextDouble() * 0.2);
        final lift = length * (0.3 + random.nextDouble() * 0.25) * stretch;
        final end = (
          start.$1 + math.cos(a) * length * 0.9,
          start.$2 + lift,
          start.$3 + math.sin(a) * length * 0.9,
        );
        // Leaves the leader fairly flat, then sweeps upward.
        final bend = (
          start.$1 + math.cos(a) * length * 0.5,
          start.$2 + lift * 0.15,
          start.$3 + math.sin(a) * length * 0.5,
        );
        final r0 = parent * 0.72;
        final r1 = scale * 0.022;
        limbs.add((start, bend, end, r0, r1));
        _addBranch(
          start,
          bend,
          end,
          r0,
          r1,
          color: bark,
          barkCell: barkCell,
          sides: detail == 2 ? 8 : 6,
          rings: detail == 2 ? 6 : 3,
        );
      }
    }

    // Farther crowns take fewer, larger cards painted with smaller leaves, so
    // a leaf is the same size on every tree.
    final cells = switch (detail) {
      2 => const [_LeafAtlas.loose, _LeafAtlas.denseA, _LeafAtlas.denseB],
      1 => const [_LeafAtlas.middle],
      _ => const [_LeafAtlas.far],
    };
    final cardHalf = _LeafAtlas.cardHalf(cells.last);
    final coverage = radius / cardHalf;
    final tips = (coverage * coverage * 2.4).round().clamp(4, 26);
    final spread = radius * (detail == 2 ? 0.34 : 0.42);
    final sprays = ((spread / cardHalf) * (spread / cardHalf) * 5)
        .round()
        .clamp(2, 9);
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
      if (limbs.isNotEmpty && (detail == 2 || i.isEven)) {
        // Carried on a twig from the nearest point along a limb.
        var best = limbs.first;
        var bestAlong = 1.0;
        var bestDistance = double.infinity;
        for (final limb in limbs) {
          for (final along in const [0.45, 0.65, 0.85, 1.0]) {
            final p = _curvePoint(limb.$1, limb.$2, limb.$3, along);
            final dx = p.$1 - tip.$1;
            final dy = p.$2 - tip.$2;
            final dz = p.$3 - tip.$3;
            final d = dx * dx + dy * dy + dz * dz;
            if (d < bestDistance) {
              bestDistance = d;
              best = limb;
              bestAlong = along;
            }
          }
        }
        final start = _curvePoint(best.$1, best.$2, best.$3, bestAlong);
        final parent = best.$4 + (best.$5 - best.$4) * bestAlong;
        final sag = math.sqrt(bestDistance) * 0.12;
        _addBranch(
          start,
          (
            (start.$1 + tip.$1) / 2,
            (start.$2 + tip.$2) / 2 + sag,
            (start.$3 + tip.$3) / 2,
          ),
          tip,
          math.max(parent * 0.8, scale * 0.014),
          scale * 0.008,
          color: bark,
          barkCell: barkCell,
          sides: detail == 2 ? 5 : 4,
          rings: detail == 2 ? 3 : 2,
        );
      }
      for (var c = 0; c < sprays; c += 1) {
        final cx = tip.$1 + (random.nextDouble() - 0.5) * 2 * spread;
        final cy =
            tip.$2 + (random.nextDouble() - 0.5) * 1.3 * spread * stretch;
        final cz = tip.$3 + (random.nextDouble() - 0.5) * 2 * spread;
        _addLeafCard(
          random,
          cx,
          cy,
          cz,
          cardHalf * (0.85 + random.nextDouble() * 0.3),
          color,
          center: center,
          reach: radius,
          bottom: bottom,
          top: top,
          atlasCell: cells[c % cells.length],
        );
      }
    }
    // Shaded sprays deep inside the crown, so it reads full rather than
    // hollow where the outer boughs part.
    final inner = (tips / 3).round();
    for (var i = 0; i < inner; i += 1) {
      final a = random.nextDouble() * math.pi * 2;
      final out = radius * 0.38 * math.sqrt(random.nextDouble());
      _addLeafCard(
        random,
        x + math.cos(a) * out,
        centerY + (random.nextDouble() - 0.35) * radius * stretch * 0.6,
        z + math.sin(a) * out,
        cardHalf,
        _leafShade(color).scale(0.85),
        center: center,
        reach: radius,
        bottom: top,
        top: top + 1,
        atlasCell: cells.last,
      );
    }
  }

  (double, double, double) _curvePoint(
    (double, double, double) a,
    (double, double, double) b,
    (double, double, double) c,
    double t,
  ) {
    final u = 1 - t;
    return (
      u * u * a.$1 + 2 * u * t * b.$1 + t * t * c.$1,
      u * u * a.$2 + 2 * u * t * b.$2 + t * t * c.$2,
      u * u * a.$3 + 2 * u * t * b.$3 + t * t * c.$3,
    );
  }

  /// A branch as one smooth, tapering tube along a curve from [from] past
  /// [bend] to [to], wrapped in bark. Its rings turn with the curve, so a
  /// branch bends rather than kinking from one straight piece to the next.
  void _addBranch(
    (double, double, double) from,
    (double, double, double) bend,
    (double, double, double) to,
    double fromRadius,
    double toRadius, {
    required _Rgb color,
    required int barkCell,
    required int sides,
    required int rings,
  }) {
    final (u0, v0, u1, v1) = _LeafAtlas.instance.cell(barkCell);
    var length = 0.0;
    var last = from;
    for (var i = 1; i <= 8; i += 1) {
      final p = _curvePoint(from, bend, to, i / 8);
      final dx = p.$1 - last.$1;
      final dy = p.$2 - last.$2;
      final dz = p.$3 - last.$3;
      length += math.sqrt(dx * dx + dy * dy + dz * dz);
      last = p;
    }
    if (length < 1e-4) {
      return;
    }
    final vSpan = math.min(length / 2.4, 0.96);
    final tint = color.scale(1.25);
    // A frame carried along the curve without twisting.
    var nx = 0.0;
    var ny = 0.0;
    var nz = 0.0;
    final base = _leaves.count;
    for (var i = 0; i <= rings; i += 1) {
      final t = i / rings;
      final c = _curvePoint(from, bend, to, t);
      // Tangent of the curve at t.
      var tx = 2 * (1 - t) * (bend.$1 - from.$1) + 2 * t * (to.$1 - bend.$1);
      var ty = 2 * (1 - t) * (bend.$2 - from.$2) + 2 * t * (to.$2 - bend.$2);
      var tz = 2 * (1 - t) * (bend.$3 - from.$3) + 2 * t * (to.$3 - bend.$3);
      final tl = math.sqrt(tx * tx + ty * ty + tz * tz) + 1e-9;
      tx /= tl;
      ty /= tl;
      tz /= tl;
      if (i == 0) {
        final (ax, ay, az) = ty.abs() < 0.9 ? (0.0, 1.0, 0.0) : (1.0, 0.0, 0.0);
        nx = ay * tz - az * ty;
        ny = az * tx - ax * tz;
        nz = ax * ty - ay * tx;
      } else {
        final along = nx * tx + ny * ty + nz * tz;
        nx -= tx * along;
        ny -= ty * along;
        nz -= tz * along;
      }
      final nl = math.sqrt(nx * nx + ny * ny + nz * nz) + 1e-9;
      nx /= nl;
      ny /= nl;
      nz /= nl;
      final bx = ty * nz - tz * ny;
      final by = tz * nx - tx * nz;
      final bz = tx * ny - ty * nx;
      final r = fromRadius + (toRadius - fromRadius) * math.pow(t, 0.85);
      for (var j = 0; j <= sides; j += 1) {
        final a = j / sides * math.pi * 2;
        final ca = math.cos(a);
        final sa = math.sin(a);
        final ox = nx * ca + bx * sa;
        final oy = ny * ca + by * sa;
        final oz = nz * ca + bz * sa;
        _leaves.vertex(
          c.$1 + ox * r,
          c.$2 + oy * r,
          c.$3 + oz * r,
          ox,
          oy,
          oz,
          tint,
          ao: 0.7 + 0.3 * t,
        );
        _leaves._uvs.addAll([
          u0 + (u1 - u0) * j / sides,
          v0 + (v1 - v0) * (0.02 + vSpan * t),
        ]);
      }
    }
    final stride = sides + 1;
    for (var i = 0; i < rings; i += 1) {
      for (var j = 0; j < sides; j += 1) {
        final a = base + i * stride + j;
        _leaves.indices!.addAll([
          a,
          a + 1,
          a + stride + 1,
          a,
          a + stride + 1,
          a + stride,
        ]);
      }
    }
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

  /// The trunk, returning the point where it forks into the crown. Near trees
  /// get a gently bent trunk with ridged, furrowed bark, a buttressed foot,
  /// moss on the shady side and spreading roots; birches get their dark
  /// lenticel dashes and blackened foot. Far ones stay a simple tapered post.
  ((double, double, double), (double, double, double)) _addTrunk(
    _LitMesh mesh,
    math.Random random,
    double x,
    double baseY,
    double z,
    double scale,
    double trunkHeight,
    _Rgb bark,
    _Rgb barkLight,
    int detail, {
    bool birch = false,
  }) {
    final barkCell = birch ? _LeafAtlas.birchBark : _LeafAtlas.bark;
    if (detail == 0) {
      _addLimb(
        mesh,
        (x, baseY - 0.12, z),
        (x, baseY + trunkHeight * 0.95, z),
        scale * 0.17,
        scale * 0.09,
        bark,
        sides: 6,
        barkCell: barkCell,
      );
      return ((x, baseY + trunkHeight * 0.82, z), (0.0, 1.0, 0.0));
    }
    final rings = detail == 2 ? 14 : 6;
    final sides = detail == 2 ? 16 : 9;
    final leanX = (random.nextDouble() - 0.5) * scale * 0.3;
    final leanZ = (random.nextDouble() - 0.5) * scale * 0.3;
    final wobble = random.nextDouble() * math.pi * 2;
    final bottomY = baseY - 0.12;
    final topY = baseY + trunkHeight * 0.86;
    (double, double, double) spine(double t) {
      final bend = math.pow(t, 1.4);
      return (
        x + leanX * bend + math.sin(t * math.pi * 1.3 + wobble) * scale * 0.035,
        bottomY + (topY - bottomY) * t,
        z + leanZ * bend + math.cos(t * math.pi * 1.1 + wobble) * scale * 0.03,
      );
    }

    // Ridges run the length of the trunk; a few strong ones flare into
    // buttresses at the foot.
    final ridges = [
      for (var j = 0; j < sides; j += 1) random.nextDouble(),
      0.0,
    ];
    ridges[sides] = ridges[0];
    final buttressPhase = random.nextDouble() * math.pi * 2;
    final mossFacing = random.nextDouble() * math.pi * 2;
    const moss = _Rgb.hex(0x5C7A30);
    const birchMark = _Rgb.hex(0x37322C);
    final ridgeDepth = detail == 2 ? 0.16 : 0.1;
    final points = <(double, double, double)>[];
    final normals = <(double, double, double)>[];
    final colors = <_Rgb>[];
    for (var i = 0; i <= rings; i += 1) {
      final t = i / rings;
      final c = spine(t);
      final flare = math.exp(-t * 7);
      final radius = scale * (0.165 - 0.05 * t) + scale * 0.15 * flare;
      for (var j = 0; j <= sides; j += 1) {
        final a = j / sides * math.pi * 2;
        final ridge = ridges[j];
        final buttress =
            math.pow(math.max(0.0, math.cos(a * 2.5 + buttressPhase)), 3) *
            flare;
        final r = radius * (1 + (ridge - 0.5) * ridgeDepth + buttress * 0.55);
        points.add((c.$1 + math.cos(a) * r, c.$2, c.$3 + math.sin(a) * r));
        normals.add((math.cos(a), 0.12, math.sin(a)));
        // Furrows dark, ridges catching the light, paler toward the foot.
        var color = _Rgb.lerp(
          barkLight,
          bark,
          _smoothstep(0, 0.35, t),
        ).scale(0.74 + 0.36 * ridge + (random.nextDouble() - 0.5) * 0.08);
        if (birch) {
          if (t < 0.12) {
            color = _Rgb.lerp(color, birchMark, 0.75);
          } else if (random.nextDouble() < 0.22) {
            color = _Rgb.lerp(color, birchMark, 0.85);
          }
        } else {
          final shady = math.cos(a - mossFacing);
          color = _Rgb.lerp(
            color,
            moss,
            _smoothstep(0.2, 0.8, shady) *
                (1 - _smoothstep(0.1, 0.45, t)) *
                0.7,
          );
        }
        colors.add(color);
      }
    }
    // The seam column repeats the first, so the bark joins up.
    final stride = sides + 1;
    for (var i = 0; i <= rings; i += 1) {
      colors[i * stride + sides] = colors[i * stride];
    }
    final (u0, v0, u1, v1) = _LeafAtlas.instance.cell(barkCell);
    final base = _leaves.count;
    for (var k = 0; k < points.length; k += 1) {
      final p = points[k];
      final n = normals[k];
      final ring = k ~/ stride;
      _leaves.vertex(
        p.$1,
        p.$2,
        p.$3,
        n.$1,
        n.$2,
        n.$3,
        colors[k].scale(1.25),
        ao: 0.55 + 0.45 * ring / rings,
      );
      _leaves._uvs.addAll([
        u0 + (u1 - u0) * (k % stride) / sides,
        v0 + (v1 - v0) * (0.02 + 0.96 * ring / rings),
      ]);
    }
    for (var i = 0; i < rings; i += 1) {
      for (var j = 0; j < sides; j += 1) {
        final a = base + i * stride + j;
        final b = a + 1;
        final c = a + stride + 1;
        final d = a + stride;
        // Wound to face outward.
        _leaves.indices!.addAll([a, d, c, a, c, b]);
      }
    }
    if (detail == 2) {
      // Roots arch out of the buttresses and dive into the ground.
      final roots = 4 + random.nextInt(2);
      for (var i = 0; i < roots; i += 1) {
        final a =
            i / roots * math.pi * 2 +
            buttressPhase / 2.5 +
            random.nextDouble() * 0.4;
        final reach = scale * (0.55 + random.nextDouble() * 0.3);
        final start = (
          x + math.cos(a) * scale * 0.18,
          baseY + scale * 0.22,
          z + math.sin(a) * scale * 0.18,
        );
        final knee = (
          x + math.cos(a) * reach * 0.55,
          baseY + scale * 0.05,
          z + math.sin(a) * reach * 0.55,
        );
        final end = (
          x + math.cos(a) * reach,
          baseY - 0.14,
          z + math.sin(a) * reach,
        );
        _addBranch(
          start,
          knee,
          end,
          scale * 0.11,
          scale * 0.012,
          color: barkLight,
          barkCell: barkCell,
          sides: 7,
          rings: 4,
        );
      }
      // Now and then, the stub of a lost branch.
      if (random.nextDouble() < 0.5) {
        final from = spine(0.45 + random.nextDouble() * 0.3);
        final a = random.nextDouble() * math.pi * 2;
        final end = (
          from.$1 + math.cos(a) * scale * 0.32,
          from.$2 + scale * 0.12,
          from.$3 + math.sin(a) * scale * 0.32,
        );
        _addBranch(
          (
            from.$1 - math.cos(a) * scale * 0.08,
            from.$2 - scale * 0.03,
            from.$3 - math.sin(a) * scale * 0.08,
          ),
          (
            (from.$1 + end.$1) / 2,
            (from.$2 + end.$2) / 2 - scale * 0.02,
            (from.$3 + end.$3) / 2,
          ),
          end,
          scale * 0.07,
          scale * 0.04,
          color: bark.scale(0.9),
          barkCell: barkCell,
          sides: 7,
          rings: 3,
        );
      }
    }
    final top = spine(1);
    final below = spine(0.85);
    final dx = top.$1 - below.$1;
    final dy = top.$2 - below.$2;
    final dz = top.$3 - below.$3;
    final dl = math.sqrt(dx * dx + dy * dy + dz * dz);
    return (top, (dx / dl, dy / dl, dz / dl));
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
    int? barkCell,
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

    if (barkCell != null) {
      // Painted bark, wrapped once around and run along the limb.
      final (u0, v0, u1, v1) = _LeafAtlas.instance.cell(barkCell);
      final along = (length / 2.4).clamp(0.08, 1.0);
      final base = _leaves.count;
      final tint = color.scale(1.25);
      for (var end = 0; end < 2; end += 1) {
        final o = end == 0 ? from : to;
        final r = end == 0 ? fromRadius : toRadius;
        for (var i = 0; i <= sides; i += 1) {
          final a = i / sides * math.pi * 2;
          final c = math.cos(a);
          final s = math.sin(a);
          final p = ring(o, r, a);
          _leaves.vertex(
            p.$1,
            p.$2,
            p.$3,
            px * c + qx * s,
            py * c + qy * s,
            pz * c + qz * s,
            tint,
            ao: 0.85,
          );
          _leaves._uvs.addAll([
            u0 + (u1 - u0) * i / sides,
            v0 + (v1 - v0) * (end == 0 ? 0.02 : 0.02 + along * 0.96),
          ]);
        }
      }
      for (var i = 0; i < sides; i += 1) {
        final a = base + i;
        final b = a + 1;
        final c = base + sides + 1 + i + 1;
        final d = base + sides + 1 + i;
        _leaves.indices!.addAll([a, b, c, a, c, d]);
      }
      return;
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

  /// Low undergrowth: a mound of leaf sprays, with leaves the size of the
  /// trees' leaves.
  void _addShrub(
    _LitMesh foliage,
    math.Random random,
    double x,
    double y,
    double z,
    double size,
    _Rgb color,
  ) {
    final distance = _distanceToWindow(x, y, z);
    final cells = distance < 17
        ? const [_LeafAtlas.loose, _LeafAtlas.denseA, _LeafAtlas.denseB]
        : (distance < 27 ? const [_LeafAtlas.middle] : const [_LeafAtlas.far]);
    final half = _LeafAtlas.cardHalf(cells.last);
    final cover = size / half;
    final count = (cover * cover * 4).round().clamp(2, 10);
    final center = (x, y, z);
    for (var i = 0; i < count; i += 1) {
      final a = random.nextDouble() * math.pi * 2;
      final spread = size * 0.62 * math.sqrt(random.nextDouble());
      _addLeafCard(
        random,
        x + math.cos(a) * spread,
        y + size * (0.12 + random.nextDouble() * 0.62),
        z + math.sin(a) * spread,
        // A card never spills far outside the shrub it belongs to.
        math.min(half, size * 0.9) * (0.85 + random.nextDouble() * 0.3),
        color,
        center: center,
        reach: size,
        bottom: y - size * 0.2,
        top: y + size,
        atlasCell: cells[i % cells.length],
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
    // Every pine is built from needled boughs, near or far; distant ones
    // simply get fewer of them.
    final near = distance < 26;
    final middle = distance < 48;
    final whorls = near ? 17 : (middle ? 9 : 6);
    final perWhorl = near ? 8 : (middle ? 5 : 4);
    // Up close long boughs are split so needles keep their size; farther
    // away nobody can tell, and the vertices go further as whole boughs.
    final maxPieces = near ? 4 : (middle ? 2 : 1);
    final total = (3.6 + random.nextDouble() * 1.6) * scale * slender;
    final topY = baseY + total;
    _addLimb(
      solids,
      (x, baseY - 0.1, z),
      (x, baseY + total * 0.9, z),
      scale * 0.14,
      scale * 0.03,
      const _Rgb.hex(0x5A4638),
      sides: near ? 8 : 5,
      barkCell: _LeafAtlas.bark,
    );
    final hue = random.nextDouble();
    _Rgb toneAt(double t) => _Rgb.lerp(
      _Rgb.lerp(dark, light, 0.35 + t * 0.5 + hue * 0.15),
      _sunlit,
      0.05 + t * 0.1,
    ).scale(1.35 + random.nextDouble() * 0.3);
    for (var w = 0; w < whorls; w += 1) {
      final t = w / whorls;
      final y = baseY + total * (0.2 + t * 0.76);
      final twist = random.nextDouble() * math.pi * 2;
      // Lower whorls hold more boughs, so the skirt stays full without a core.
      final count = perWhorl + (t < 0.5 ? (near ? 2 : 1) : 0);
      for (var i = 0; i < count; i += 1) {
        final a = twist + (i + random.nextDouble() * 0.4) / count * math.pi * 2;
        final length =
            scale * (1.5 - 1.3 * t) * (0.85 + random.nextDouble() * 0.3);
        final droop = 0.2 + (1 - t) * 0.42 + random.nextDouble() * 0.15;
        final tip = (
          x + math.cos(a) * math.cos(droop) * length,
          y - math.sin(droop) * length,
          z + math.sin(a) * math.cos(droop) * length,
        );
        _addBoughRun((x, y, z), tip, length, toneAt(t), t, maxPieces);
      }
    }
    // A leader at the very top, pointing up.
    _addBoughRun(
      (x, baseY + total * 0.9, z),
      (x, topY, z),
      total * 0.1,
      toneAt(1),
      1,
      1,
    );
    if (castShadow) {
      _shadows.add(
        _TreeShadow(x: x, z: z, radius: scale * 1.05, height: total * 0.55),
      );
    }
  }

  /// A bough from [root] to [tip], laid as several shorter cards end to end
  /// when it is long, so the needles keep one size all over the tree.
  void _addBoughRun(
    (double, double, double) root,
    (double, double, double) tip,
    double length,
    _Rgb tone,
    double t,
    int maxPieces,
  ) {
    final pieces = (length / 0.75).round().clamp(1, maxPieces);
    (double, double, double) at(double f) => (
      root.$1 + (tip.$1 - root.$1) * f,
      root.$2 + (tip.$2 - root.$2) * f,
      root.$3 + (tip.$3 - root.$3) * f,
    );
    for (var k = 0; k < pieces; k += 1) {
      final k0 = k / pieces;
      final k1 = (k + 1) / pieces;
      _addBough(
        at(math.max(0, k0 - 0.08)),
        at(k1),
        length / pieces * 0.85 * (1.15 - 0.4 * k0),
        tone,
        rootShade: 0.4 + 0.3 * k0,
        tipShade: 0.62 + 0.38 * k1 + t * 0.1,
      );
    }
  }
}
