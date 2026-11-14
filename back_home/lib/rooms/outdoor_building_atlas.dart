part of 'outdoor_landscape.dart';

/// Painted surfaces for buildings, in the same hand as the leaves and bark:
/// lime-washed plaster, curved clay roof tiles, rubble stone and planks.
/// Like the leaf atlas, colour comes from the vertices and the texture only
/// shades it.
class _BuildingAtlas {
  _BuildingAtlas._();

  static final _BuildingAtlas instance = _BuildingAtlas._();

  static const int _size = 1024;
  static const int _cell = 512;

  static const int plaster = 0;
  static const int tiles = 1;
  static const int stone = 2;
  static const int wood = 3;

  /// World size of one cell's painting, per surface.
  static double span(int cell) => switch (cell) {
    tiles => 2.6,
    stone => 2.2,
    wood => 1.4,
    _ => 3.0,
  };

  // The renderer frees native buffers when it closes. Keep only Dart pixels.
  late final Uint8List _pixels = _paintPixels();

  (double, double, double, double) cell(int index) {
    final u = (index % 2) * 0.5;
    final v = (index ~/ 2) * 0.5;
    return (u, v, u + 0.5, v + 0.5);
  }

  three.DataTexture createTexture() =>
      three.DataTexture(
          three.Uint8Array.fromList(_pixels),
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

  Uint8List _paintPixels() {
    final out = Uint8List(_size * _size * 4);
    final random = math.Random(0xB01D);
    _paint(out, plaster, (x, y) {
      final mottle =
          _noise(x / 70, y / 70) * 0.6 + _noise(x / 18, y / 18) * 0.4;
      return 0.84 + (mottle - 0.5) * 0.16 + (random.nextDouble() - 0.5) * 0.05;
    });
    _paint(out, tiles, (x, y) {
      // Rows of half-round tiles, every other row shifted half a tile.
      const rowHeight = 28.0;
      const tileWidth = 24.0;
      final row = (y / rowHeight).floor();
      final inRow = (y % rowHeight) / rowHeight;
      final shifted = x + (row.isOdd ? tileWidth / 2 : 0);
      final across = (shifted % tileWidth) / tileWidth;
      final tile = (shifted / tileWidth).floor();
      final round = math.sin(across * math.pi);
      final lip = inRow > 0.84 ? 0.45 : 1.0;
      final tone = 0.78 + (_hash(tile, row) - 0.5) * 0.28;
      final moss = _noise(x / 40, y / 40) > 0.72 ? 0.82 : 1.0;
      return tone *
          (0.55 + 0.45 * round) *
          lip *
          moss *
          (0.85 + 0.15 * (1 - inRow));
    });
    _paint(out, stone, (x, y) {
      // Rubble: the nearest of jittered points picks the stone, and the gap
      // to the second nearest is the mortar.
      const grid = 46.0;
      final gx = (x / grid).floor();
      final gy = (y / grid).floor();
      var first = double.infinity;
      var second = double.infinity;
      var id = 0;
      for (var j = -1; j <= 1; j += 1) {
        for (var i = -1; i <= 1; i += 1) {
          final cx = gx + i;
          final cy = gy + j;
          final px = (cx + 0.15 + _hash(cx, cy * 7) * 0.7) * grid;
          final py =
              (cy + 0.15 + _hash(cx * 5, cy) * 0.7) * grid * 0.75 + grid * 0.12;
          final dx = x - px;
          final dy = (y - py) * 1.4;
          final d = math.sqrt(dx * dx + dy * dy);
          if (d < first) {
            second = first;
            first = d;
            id = cx * 131 + cy;
          } else if (d < second) {
            second = d;
          }
        }
      }
      final gap = second - first;
      if (gap < 5) {
        return 0.42 + _noise(x / 6, y / 6) * 0.1;
      }
      final tone = 0.7 + (_hash(id, 3) - 0.5) * 0.3;
      final edge = (gap / 22).clamp(0.0, 1.0);
      return tone * (0.78 + 0.22 * edge) + (_noise(x / 9, y / 9) - 0.5) * 0.1;
    });
    _paint(out, wood, (x, y) {
      // Vertical planks with grain and dark joints.
      const plank = 64.0;
      final within = (x % plank) / plank;
      final board = (x / plank).floor();
      final grain = _noise(x / 3 + board * 17, y / 60) - 0.5;
      final joint = within < 0.05 || within > 0.95 ? 0.5 : 1.0;
      return (0.72 + (_hash(board, 9) - 0.5) * 0.2 + grain * 0.22) * joint;
    });
    return out;
  }

  void _paint(Uint8List out, int cell, double Function(double x, double y) at) {
    final originX = (cell % 2) * _cell;
    final originY = (cell ~/ 2) * _cell;
    for (var y = 0; y < _cell; y += 1) {
      for (var x = 0; x < _cell; x += 1) {
        final value = (at(x + 0.5, y + 0.5).clamp(0.0, 1.0) * 255).round();
        final i = ((originY + y) * _size + originX + x) * 4;
        out[i] = value;
        out[i + 1] = value;
        out[i + 2] = value;
        out[i + 3] = 255;
      }
    }
  }

  static double _hash(int x, int y) {
    var h = (x * 374761393 + y * 668265263) & 0x7FFFFFFF;
    h = ((h ^ (h >> 13)) * 1274126177) & 0x7FFFFFFF;
    return ((h ^ (h >> 16)) & 0xFFFF) / 0xFFFF;
  }

  static double _noise(double x, double y) {
    final xi = x.floor();
    final yi = y.floor();
    final fx = x - xi;
    final fy = y - yi;
    final sx = fx * fx * (3 - 2 * fx);
    final sy = fy * fy * (3 - 2 * fy);
    final a = _hash(xi, yi);
    final b = _hash(xi + 1, yi);
    final c = _hash(xi, yi + 1);
    final d = _hash(xi + 1, yi + 1);
    return a + (b - a) * sx + (c - a) * sy + (a - b - c + d) * sx * sy;
  }
}
