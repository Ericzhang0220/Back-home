part of 'outdoor_landscape.dart';

/// Painted sprays of leaves that tree crowns are built from: hundreds of small
/// folded leaves per card, so a crown shows real leaves for the vertex cost of
/// a few faceted blocks. Colour comes from the card's vertices; the texture
/// only shades it, dark for the leaves underneath and bright for the top ones.
class _LeafAtlas {
  _LeafAtlas._();

  static final _LeafAtlas instance = _LeafAtlas._();

  static const int _width = 1024;
  static const int _height = 2048;
  static const int _cell = 512;

  /// Two dense sprays and a loose outline spray for near trees, one conifer
  /// bough, and sprays of ever smaller leaves for cards that cover more of a
  /// distant crown, so a leaf keeps the same size in the world on every tree.
  static const int denseA = 0;
  static const int denseB = 1;
  static const int loose = 2;
  static const int bough = 3;
  static const int middle = 4;
  static const int far = 5;
  static const int bark = 6;
  static const int birchBark = 7;

  /// Length of one leaf in world units, on every tree and shrub.
  static const double leafLength = 0.085;

  /// Half the width of a card whose leaves come out at [leafLength].
  static double cardHalf(int cell) => switch (cell) {
    middle => leafLength / (_leafPixelsMiddle / _cell) / 2,
    far => leafLength / (_leafPixelsFar / _cell) / 2,
    _ => leafLength / (_leafPixelsNear / _cell) / 2,
  };

  // Average painted leaf length in each kind of cell, in pixels.
  static const double _leafPixelsNear = 31;
  static const double _leafPixelsMiddle = 19;
  static const double _leafPixelsFar = 12;
  static final Float64List _outline = Float64List.fromList([
    for (var i = 0; i <= 64; i += 1)
      math.pow(math.sin(math.pi * math.pow(i / 64, 0.68)), 0.8).toDouble(),
  ]);

  // The renderer frees native buffers when it closes. Keep only Dart pixels.
  late final Uint8List _pixels = _paintPixels();

  /// The cell's corners in texture coordinates: left, bottom, right, top.
  (double, double, double, double) cell(int index) {
    final u = (index % 2) * 0.5;
    final v = (index ~/ 2) / 4;
    return (u, v, u + 0.5, v + 1 / 4);
  }

  three.DataTexture createTexture() =>
      three.DataTexture(
          three.Uint8Array.fromList(_pixels),
          _width,
          _height,
          three.RGBAFormat,
          three.UnsignedByteType,
        )
        ..wrapS = three.ClampToEdgeWrapping
        ..wrapT = three.ClampToEdgeWrapping
        ..magFilter = three.LinearFilter
        ..minFilter = three.LinearMipmapLinearFilter
        ..generateMipmaps = true
        ..needsUpdate = true;

  Uint8List _paintPixels() {
    final out = Uint8List(_width * _height * 4);
    // Empty texels keep a mid tone, so filtering leaves no bright or black
    // fringe around the cut-out edge.
    for (var i = 0; i < out.length; i += 4) {
      out[i] = 62;
      out[i + 1] = 70;
      out[i + 2] = 56;
    }
    _paintSpray(out, denseA, math.Random(0x1EAF), count: 760, leaf: 30);
    _paintSpray(out, denseB, math.Random(0xBEEF), count: 640, leaf: 33);
    _paintSpray(out, loose, math.Random(0xF00D), count: 230, leaf: 30);
    _paintBough(out, bough, math.Random(0xC0FE));
    _paintSpray(out, middle, math.Random(0x3A11), count: 1800, leaf: 19);
    _paintSpray(out, far, math.Random(0xFA12), count: 4300, leaf: 12);
    _paintBark(out, bark, math.Random(0xBA4C), birch: false);
    _paintBark(out, birchBark, math.Random(0xB14C), birch: true);
    return out;
  }

  void _paintSpray(
    Uint8List out,
    int cell,
    math.Random random, {
    required int count,
    required double leaf,
  }) {
    final originX = (cell % 2) * _cell;
    final originY = (cell ~/ 2) * _cell;
    const middle = _cell / 2;
    // A spray is a few clumps of leaves along forking twigs, never a disc:
    // each clump is lobed, and they overlap unevenly.
    final clumps = <(double, double, double, double)>[];
    final count0 = 4 + random.nextInt(3);
    final spin = random.nextDouble() * math.pi * 2;
    for (var c = 0; c < count0; c += 1) {
      final a = spin + c / count0 * math.pi * 2 + (random.nextDouble() - 0.5);
      final out = c == 0 ? 0.0 : middle * (0.22 + random.nextDouble() * 0.26);
      clumps.add((
        middle + math.cos(a) * out,
        middle + math.sin(a) * out,
        middle * (0.2 + random.nextDouble() * 0.16),
        random.nextDouble() * math.pi * 2,
      ));
    }
    for (var i = 0; i < count; i += 1) {
      // Painted back to front: the first leaves lie deepest in shadow.
      final t = i / count;
      final (cx, cy, reach, phase) = clumps[random.nextInt(clumps.length)];
      final angle = random.nextDouble() * math.pi * 2;
      final lobe =
          0.62 +
          0.38 * math.sin(angle * 3 + phase) * math.sin(angle * 2 - phase);
      final radius =
          math.pow(random.nextDouble(), 0.7) * reach * (0.7 + lobe * 0.5);
      final x = cx + math.cos(angle) * radius;
      final y = cy + math.sin(angle) * radius;
      final dx = x - middle;
      final dy = y - middle;
      if (dx * dx + dy * dy > middle * middle * 0.8) {
        continue;
      }
      // Leaves point outward from their clump, loosely.
      final heading = angle + (random.nextDouble() - 0.5) * 1.9;
      final length = leaf * (0.7 + random.nextDouble() * 0.55);
      final shade = (0.1 + 0.9 * t * t) * (0.78 + random.nextDouble() * 0.22);
      _paintLeaf(
        out,
        originX,
        originY,
        x,
        y,
        heading,
        length,
        length * (0.3 + random.nextDouble() * 0.1),
        shade,
        // Some leaves lean yellow and some blue-green, within one tree.
        warm: (random.nextDouble() - 0.5) * 0.28,
      );
    }
  }

  /// Bark: vertical plates split by dark furrows, scaly and uneven, or for a
  /// birch, pale bark with dark horizontal lenticels. Tiles top to bottom.
  void _paintBark(
    Uint8List out,
    int cell,
    math.Random random, {
    required bool birch,
  }) {
    final originX = (cell % 2) * _cell;
    final originY = (cell ~/ 2) * _cell;
    final tone = Float64List(_cell * _cell)
      ..fillRange(0, _cell * _cell, birch ? 0.86 : 0.34);
    void plate(
      double x,
      double y,
      double w,
      double h,
      double value,
      double edge,
    ) {
      for (var py = (y - h / 2).floor(); py <= (y + h / 2).ceil(); py += 1) {
        for (var px = (x - w / 2).floor(); px <= (x + w / 2).ceil(); px += 1) {
          final u = (px - x) / (w / 2);
          final v = (py - y) / (h / 2);
          final d = u * u * 0.9 + v * v * v * v;
          if (d > 1) {
            continue;
          }
          final col = px % _cell < 0 ? px % _cell + _cell : px % _cell;
          final row = py % _cell < 0 ? py % _cell + _cell : py % _cell;
          // Lit on the left edge, shaded on the right, like raised bark.
          tone[row * _cell + col] =
              value * (1 + edge * (-u) * 0.25) * (1 - d * 0.18);
        }
      }
    }

    if (birch) {
      for (var i = 0; i < 220; i += 1) {
        // Lenticels: short dark dashes across the trunk.
        plate(
          random.nextDouble() * _cell,
          random.nextDouble() * _cell,
          14 + random.nextDouble() * 54,
          2 + random.nextDouble() * 4,
          0.12 + random.nextDouble() * 0.12,
          0,
        );
      }
      for (var i = 0; i < 26; i += 1) {
        plate(
          random.nextDouble() * _cell,
          random.nextDouble() * _cell,
          18 + random.nextDouble() * 30,
          10 + random.nextDouble() * 22,
          0.3 + random.nextDouble() * 0.2,
          0.4,
        );
      }
    } else {
      for (var i = 0; i < 520; i += 1) {
        plate(
          random.nextDouble() * _cell,
          random.nextDouble() * _cell,
          12 + random.nextDouble() * 22,
          40 + random.nextDouble() * 120,
          0.6 + random.nextDouble() * 0.4,
          1,
        );
      }
    }
    for (var row = 0; row < _cell; row += 1) {
      for (var col = 0; col < _cell; col += 1) {
        final i = ((originY + row) * _width + originX + col) * 4;
        final value =
            (tone[row * _cell + col] * (0.92 + random.nextDouble() * 0.16))
                .clamp(0.0, 1.0);
        out[i] = (value * 255).round();
        out[i + 1] = (value * 255).round();
        out[i + 2] = (value * 255).round();
        out[i + 3] = 255;
      }
    }
  }

  void _paintBough(Uint8List out, int cell, math.Random random) {
    final originX = (cell % 2) * _cell;
    final originY = (cell ~/ 2) * _cell;
    const middle = _cell / 2;
    // A shadowed body first: the dense inner foliage of the bough. It keeps
    // the bough solid when the needles blur together in the distance.
    for (var t = 0.0; t < 0.9; t += 0.03) {
      for (final side in const [-1.0, 1.0]) {
        final reach = middle * 0.62 * math.pow(1 - t, 0.72);
        _paintLeaf(
          out,
          originX,
          originY,
          middle,
          t * _cell * 0.96,
          math.pi / 2 - side * 1.05,
          reach,
          reach * 0.42,
          0.1 + random.nextDouble() * 0.06,
          warm: 0,
        );
      }
    }
    // Side twigs off a central stem, shorter toward the tip, thick with needles.
    for (var pass = 0; pass < 2; pass += 1) {
      for (var t = 0.02; t < 0.98; t += 0.055) {
        for (final side in const [-1.0, 1.0]) {
          final y0 = t * _cell * 0.96;
          final reach = middle * 0.86 * math.pow(1 - t, 0.72);
          final twigAngle =
              math.pi / 2 - side * (0.95 + random.nextDouble() * 0.2);
          final needles = pass == 0 ? 26 : 34;
          for (var n = 0; n < needles; n += 1) {
            final along = random.nextDouble();
            final x = middle + math.cos(twigAngle) * reach * along;
            final y = y0 + math.sin(twigAngle) * reach * along;
            final heading =
                twigAngle +
                (random.nextBool() ? 0.6 : -0.6) +
                (random.nextDouble() - 0.5) * 0.5;
            final shade = pass == 0
                ? 0.1 + random.nextDouble() * 0.14
                : 0.42 + random.nextDouble() * 0.58;
            _paintLeaf(
              out,
              originX,
              originY,
              x,
              y,
              heading,
              24 + random.nextDouble() * 14,
              4.4,
              shade,
              warm: (random.nextDouble() - 0.5) * 0.18,
            );
          }
        }
      }
    }
  }

  /// One pointed leaf from (x, y) along [heading], folded down its spine so its
  /// two halves take different tones.
  void _paintLeaf(
    Uint8List out,
    int originX,
    int originY,
    double x,
    double y,
    double heading,
    double length,
    double width,
    double shade, {
    required double warm,
  }) {
    final dx = math.cos(heading);
    final dy = math.sin(heading);
    final tipX = x + dx * length;
    final tipY = y + dy * length;
    final half = width / 2;
    final x0 = (math.min(x, tipX) - half - 1).floor().clamp(0, _cell - 1);
    final x1 = (math.max(x, tipX) + half + 1).ceil().clamp(0, _cell - 1);
    final y0 = (math.min(y, tipY) - half - 1).floor().clamp(0, _cell - 1);
    final y1 = (math.max(y, tipY) + half + 1).ceil().clamp(0, _cell - 1);
    for (var py = y0; py <= y1; py += 1) {
      for (var px = x0; px <= x1; px += 1) {
        final rx = px + 0.5 - x;
        final ry = py + 0.5 - y;
        final s = (rx * dx + ry * dy) / length;
        if (s <= 0 || s >= 1) {
          continue;
        }
        final across = -rx * dy + ry * dx;
        // Widest a third of the way along, drawn out to a point.
        final outline = half * _outline[(s * 64).round()];
        final coverage = outline - across.abs() + 0.5;
        if (coverage <= 0) {
          continue;
        }
        var tone = shade * (across > 0 ? 1.0 : 0.72) * (0.86 + 0.26 * s);
        // The spine catches a thin dark line.
        if (across.abs() < 0.9) {
          tone *= 0.72;
        }
        final i = ((originY + py) * _width + originX + px) * 4;
        final a = coverage.clamp(0.0, 1.0);
        final r = (tone * (1 + warm)).clamp(0.0, 1.0) * 255;
        final g = tone.clamp(0.0, 1.0) * 255;
        final b = (tone * (1 - warm * 1.4)).clamp(0.0, 1.0) * 255;
        out[i] = (out[i] + (r - out[i]) * a).round();
        out[i + 1] = (out[i + 1] + (g - out[i + 1]) * a).round();
        out[i + 2] = (out[i + 2] + (b - out[i + 2]) * a).round();
        out[i + 3] = math.max(out[i + 3], (a * 255).round());
      }
    }
  }
}
