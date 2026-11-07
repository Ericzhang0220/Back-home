part of 'outdoor_landscape.dart';

/// Painted sprays of leaves that tree crowns are built from: hundreds of small
/// folded leaves per card, so a crown shows real leaves for the vertex cost of
/// a few faceted blocks. Colour comes from the card's vertices; the texture
/// only shades it, dark for the leaves underneath and bright for the top ones.
class _LeafAtlas {
  _LeafAtlas._();

  static final _LeafAtlas instance = _LeafAtlas._();

  static const int _size = 1024;
  static const int _cell = _size ~/ 2;

  /// Two dense sprays, one loose outline spray, one conifer bough.
  static const int denseA = 0;
  static const int denseB = 1;
  static const int loose = 2;
  static const int bough = 3;

  late final three.DataTexture texture = _build();

  /// The cell's corners in texture coordinates: left, bottom, right, top.
  (double, double, double, double) cell(int index) {
    final u = (index % 2) * 0.5;
    final v = (index ~/ 2) * 0.5;
    return (u, v, u + 0.5, v + 0.5);
  }

  three.DataTexture _build() {
    final bytes = three.Uint8Array(_size * _size * 4);
    final out = bytes.toDartList();
    // Empty texels keep a mid tone, so filtering leaves no bright or black
    // fringe around the cut-out edge.
    for (var i = 0; i < out.length; i += 4) {
      out[i] = 62;
      out[i + 1] = 70;
      out[i + 2] = 56;
    }
    _paintSpray(out, denseA, math.Random(0x1EAF), count: 320, leaf: 54);
    _paintSpray(out, denseB, math.Random(0xBEEF), count: 280, leaf: 62);
    _paintSpray(out, loose, math.Random(0xF00D), count: 95, leaf: 46);
    _paintBough(out, bough, math.Random(0xC0FE));
    return three.DataTexture(
        bytes,
        _size,
        _size,
        three.RGBAFormat,
        three.UnsignedByteType,
      )
      ..wrapS = three.ClampToEdgeWrapping
      ..wrapT = three.ClampToEdgeWrapping
      ..magFilter = three.LinearFilter
      ..minFilter = three.LinearMipmapLinearFilter
      ..generateMipmaps = true
      ..needsUpdate = true;
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
    for (var i = 0; i < count; i += 1) {
      // Painted back to front: the first leaves lie deepest in shadow.
      final t = i / count;
      final radius = math.pow(random.nextDouble(), 0.62) * middle * 0.8;
      final angle = random.nextDouble() * math.pi * 2;
      final x = middle + math.cos(angle) * radius;
      final y = middle + math.sin(angle) * radius;
      // Leaves point outward, loosely, like a spray from a twig.
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

  void _paintBough(Uint8List out, int cell, math.Random random) {
    final originX = (cell % 2) * _cell;
    final originY = (cell ~/ 2) * _cell;
    const middle = _cell / 2;
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
        final outline =
            half * math.pow(math.sin(math.pi * math.pow(s, 0.68)), 0.8);
        final coverage = outline - across.abs() + 0.5;
        if (coverage <= 0) {
          continue;
        }
        var tone = shade * (across > 0 ? 1.0 : 0.72) * (0.86 + 0.26 * s);
        // The spine catches a thin dark line.
        if (across.abs() < 0.9) {
          tone *= 0.72;
        }
        final i = ((originY + py) * _size + originX + px) * 4;
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
