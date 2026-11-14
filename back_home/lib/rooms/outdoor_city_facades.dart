part of 'outdoor_landscape.dart';

/// Building surface treatments painted into the facade atlas.
enum _FacadeStyle {
  /// Dark curtain wall: thin mullions, tenants lit in horizontal runs.
  curtain,

  /// Masonry with punched windows.
  punched,

  /// Tall narrow windows between pilasters, for the older deco towers.
  deco,

  /// Continuous ribbon windows, whole floors of cool office light.
  ribbon,
}

/// Procedurally painted window textures. Thousands of tiny windows would be
/// far too many vertices as geometry, so each building face is one quad that
/// shows a random patch of this atlas: a day map (what the wall looks like)
/// and a night map (only the light it gives off).
class _FacadeAtlas {
  _FacadeAtlas._() {
    _paint();
  }

  /// Painted once and kept, so toggling scenery doesn't repaint or reallocate.
  static final _FacadeAtlas instance = _FacadeAtlas._();

  static const int width = 2048;
  static const int height = 1200;
  static const int columns = 64;
  static const int floors = 120;
  static const int cellWidth = 7;
  static const int cellHeight = 10;
  static const int styleWidth = columns * cellWidth;
  static const int signStripX = 1800;
  static const int signRowHeight = 72;

  /// Rooftop signs; invented names, one row of the atlas each.
  static const signs = ['HOTEL', 'LUMEN', 'GRAND', 'MEDIA', 'NOVA', 'PLAZA'];
  static const signColors = [
    _Rgb.hex(0xF4F1E6),
    _Rgb.hex(0x7C6BFF),
    _Rgb.hex(0xFF8A3D),
    _Rgb.hex(0xE8EEF4),
    _Rgb.hex(0xFF4F9A),
    _Rgb.hex(0xFF4A3D),
  ];

  final Uint8List _night = Uint8List(width * height * 4);
  final Uint8List _day = Uint8List((width ~/ 2) * (height ~/ 2) * 4);

  /// Atlas rectangle for a [cols] x [rows] patch of windows in [style].
  (double, double, double, double) patch(
    _FacadeStyle style,
    int firstColumn,
    int firstFloor,
    int cols,
    int rows,
  ) {
    final left = style.index * styleWidth + firstColumn * cellWidth;
    final bottom = firstFloor * cellHeight;
    return (
      left / width,
      bottom / height,
      (left + cols * cellWidth) / width,
      (bottom + rows * cellHeight) / height,
    );
  }

  (double, double, double, double) signPatch(int index) {
    final bottom = index * signRowHeight;
    return (
      signStripX / width,
      bottom / height,
      (signStripX + _signPixelWidth) / width,
      (bottom + signRowHeight) / height,
    );
  }

  static const int _signPixelWidth = 244;

  static int _rgba(int r, int g, int b) =>
      0xFF000000 |
      (b.clamp(0, 255) << 16) |
      (g.clamp(0, 255) << 8) |
      r.clamp(0, 255);

  static int _shade(_Rgb c, double k) => _rgba(
    (c.r * k * 255).round(),
    (c.g * k * 255).round(),
    (c.b * k * 255).round(),
  );

  void _paint() {
    final nightPixels = _night.buffer.asUint32List(
      _night.offsetInBytes,
      width * height,
    );
    // Painted at full size, then halved: the day map needs far less detail.
    final dayPixels = Uint32List(width * height);
    nightPixels.fillRange(0, nightPixels.length, 0xFF000000);
    dayPixels.fillRange(0, dayPixels.length, _rgba(90, 94, 100));
    for (final style in _FacadeStyle.values) {
      _paintStyle(style, dayPixels, nightPixels);
    }
    _paintSigns(dayPixels, nightPixels);
    _halveInto(dayPixels);
  }

  void _paintStyle(_FacadeStyle style, Uint32List dayPx, Uint32List nightPx) {
    final random = math.Random(0xFACADE + style.index * 31);
    final seed = style.index * 17.0;
    final originX = style.index * styleWidth;
    final (maxRun, baseChance) = switch (style) {
      _FacadeStyle.curtain => (11, 0.42),
      _FacadeStyle.punched => (4, 0.5),
      _FacadeStyle.deco => (2, 0.34),
      _FacadeStyle.ribbon => (26, 0.62),
    };
    // Window rectangle within a 7x10 cell.
    final (wx, wy, ww, wh) = switch (style) {
      _FacadeStyle.curtain => (0, 2, 6, 7),
      _FacadeStyle.punched => (1, 3, 5, 5),
      _FacadeStyle.deco => (2, 1, 3, 8),
      _FacadeStyle.ribbon => (0, 4, 7, 4),
    };
    for (var floor = 0; floor < floors; floor += 1) {
      var column = 0;
      // Offices tend to be lit a floor at a time.
      final floorOn = random.nextDouble();
      while (column < columns) {
        final run = 1 + random.nextInt(maxRun);
        // Lit windows clump into tenants instead of an even speckle.
        final clump = _valueNoise(floor / 6.5 + seed, column / 9 + seed * 3);
        var chance = baseChance * (0.12 + 2.1 * clump * clump);
        if (style == _FacadeStyle.ribbon) {
          chance *= floorOn < 0.55 ? 1.5 : 0.18;
        }
        final _Rgb? light;
        if (random.nextDouble() >= chance) {
          light = null;
        } else {
          final pick = random.nextDouble();
          light = switch (style) {
            _FacadeStyle.ribbon =>
              pick < 0.8 ? const _Rgb.hex(0xE6F0FF) : const _Rgb.hex(0xFFEAC4),
            _ =>
              pick < 0.58
                  ? const _Rgb.hex(0xFFC061)
                  : pick < 0.82
                  ? const _Rgb.hex(0xFFE4AE)
                  : pick < 0.94
                  ? const _Rgb.hex(0xDDE8FF)
                  : const _Rgb.hex(0xFF7A2A),
          };
        }
        for (var i = 0; i < run && column < columns; i += 1) {
          final lit = light != null && random.nextDouble() > 0.14;
          _paintCell(
            style,
            originX + column * cellWidth,
            floor * cellHeight,
            wx,
            wy,
            ww,
            wh,
            lit ? light : null,
            random,
            floor,
            column,
            dayPx,
            nightPx,
          );
          column += 1;
        }
      }
    }
  }

  void _paintCell(
    _FacadeStyle style,
    int cx,
    int cy,
    int wx,
    int wy,
    int ww,
    int wh,
    _Rgb? light,
    math.Random random,
    int floor,
    int column,
    Uint32List dayPx,
    Uint32List nightPx,
  ) {
    // Slow variation, like cloud reflected across a wall of glass.
    final sheen = _valueNoise(column / 11 + 3, floor / 14 + style.index * 9.0);
    final jitter = random.nextDouble();
    final _Rgb wall;
    final _Rgb glass;
    switch (style) {
      case _FacadeStyle.curtain:
        wall = const _Rgb.hex(0x9AA3AD);
        glass = _Rgb.lerp(
          const _Rgb.hex(0x47678A),
          const _Rgb.hex(0x8FB2CF),
          sheen * 0.8 + jitter * 0.2,
        );
      case _FacadeStyle.punched:
        wall = _Rgb.lerp(
          const _Rgb.hex(0xC6BFB2),
          const _Rgb.hex(0xD6CFC3),
          jitter,
        );
        glass = const _Rgb.hex(0x35424F);
      case _FacadeStyle.deco:
        wall = const _Rgb.hex(0xC2BAA8);
        glass = const _Rgb.hex(0x3E4C5A);
      case _FacadeStyle.ribbon:
        wall = const _Rgb.hex(0xD9DBDD);
        glass = _Rgb.lerp(
          const _Rgb.hex(0x2F4C68),
          const _Rgb.hex(0x5E83A3),
          sheen,
        );
    }
    final wallPx = _shade(wall, 0.97 + jitter * 0.03);
    final glassPx = _shade(glass, 1);
    // Blinds: some windows only glow in their lower part.
    final litRows = jitter < 0.18 ? (wh * 0.6).ceil() : wh;
    final brightness = 0.55 + random.nextDouble() * 0.45;
    for (var y = 0; y < cellHeight; y += 1) {
      final rowStart = (cy + y) * width + cx;
      final inRow = y >= wy && y < wy + wh;
      for (var x = 0; x < cellWidth; x += 1) {
        final inWindow = inRow && x >= wx && x < wx + ww;
        dayPx[rowStart + x] = inWindow ? glassPx : wallPx;
        if (inWindow && light != null && y - wy < litRows) {
          // Ceilings are lit brighter than the floor beneath them.
          final k = brightness * (0.78 + 0.22 * (y - wy) / wh);
          nightPx[rowStart + x] = _shade(light, k);
        }
      }
    }
  }

  // --- Signs -------------------------------------------------------------------

  static const Map<String, List<int>> _font = {
    'A': [0x0E, 0x11, 0x11, 0x1F, 0x11, 0x11, 0x11],
    'D': [0x1E, 0x11, 0x11, 0x11, 0x11, 0x11, 0x1E],
    'E': [0x1F, 0x10, 0x10, 0x1E, 0x10, 0x10, 0x1F],
    'G': [0x0E, 0x11, 0x10, 0x17, 0x11, 0x11, 0x0F],
    'H': [0x11, 0x11, 0x11, 0x1F, 0x11, 0x11, 0x11],
    'I': [0x0E, 0x04, 0x04, 0x04, 0x04, 0x04, 0x0E],
    'L': [0x10, 0x10, 0x10, 0x10, 0x10, 0x10, 0x1F],
    'M': [0x11, 0x1B, 0x15, 0x15, 0x11, 0x11, 0x11],
    'N': [0x11, 0x19, 0x15, 0x13, 0x11, 0x11, 0x11],
    'O': [0x0E, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0E],
    'P': [0x1E, 0x11, 0x11, 0x1E, 0x10, 0x10, 0x10],
    'R': [0x1E, 0x11, 0x11, 0x1E, 0x14, 0x12, 0x11],
    'T': [0x1F, 0x04, 0x04, 0x04, 0x04, 0x04, 0x04],
    'U': [0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0E],
    'V': [0x11, 0x11, 0x11, 0x11, 0x11, 0x0A, 0x04],
    'Z': [0x1F, 0x01, 0x02, 0x04, 0x08, 0x10, 0x1F],
  };

  void _paintSigns(Uint32List dayPx, Uint32List nightPx) {
    const scale = 8;
    const glyphWidth = 5 * scale;
    const advance = glyphWidth + 8;
    final panel = _rgba(38, 40, 44);
    final letterDay = _rgba(214, 214, 208);
    for (var index = 0; index < signs.length; index += 1) {
      final text = signs[index];
      final color = signColors[index];
      final top = index * signRowHeight;
      for (var y = 0; y < signRowHeight; y += 1) {
        final row = (top + y) * width + signStripX;
        dayPx.fillRange(row, row + _signPixelWidth, panel);
      }
      final textWidth = text.length * advance - 8;
      final startX = signStripX + (_signPixelWidth - textWidth) ~/ 2;
      final startY = top + (signRowHeight - 7 * scale) ~/ 2;
      final halo = _shade(color, 0.28);
      final core = _shade(color, 1);
      for (var pass = 0; pass < 2; pass += 1) {
        for (var i = 0; i < text.length; i += 1) {
          final glyph = _font[text[i]]!;
          final gx = startX + i * advance;
          for (var row = 0; row < 7; row += 1) {
            // Glyph rows run top-down; texture rows run bottom-up.
            final bits = glyph[6 - row];
            for (var col = 0; col < 5; col += 1) {
              if (bits & (0x10 >> col) == 0) {
                continue;
              }
              final px = gx + col * scale;
              final py = startY + row * scale;
              // First pass lays a soft halo around the strokes.
              final margin = pass == 0 ? 3 : 0;
              for (var y = py - margin; y < py + scale + margin; y += 1) {
                final rowStart = y * width;
                for (var x = px - margin; x < px + scale + margin; x += 1) {
                  nightPx[rowStart + x] = pass == 0 ? halo : core;
                  if (pass == 1) {
                    dayPx[rowStart + x] = letterDay;
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  void _halveInto(Uint32List source) {
    final halfWidth = width ~/ 2;
    final halfHeight = height ~/ 2;
    final out = _day.buffer.asUint32List(
      _day.offsetInBytes,
      halfWidth * halfHeight,
    );
    for (var y = 0; y < halfHeight; y += 1) {
      final row0 = y * 2 * width;
      final row1 = row0 + width;
      for (var x = 0; x < halfWidth; x += 1) {
        final a = source[row0 + x * 2];
        final b = source[row0 + x * 2 + 1];
        final c = source[row1 + x * 2];
        final d = source[row1 + x * 2 + 1];
        final r = ((a & 0xFF) + (b & 0xFF) + (c & 0xFF) + (d & 0xFF)) >> 2;
        final g =
            (((a >> 8) & 0xFF) +
                ((b >> 8) & 0xFF) +
                ((c >> 8) & 0xFF) +
                ((d >> 8) & 0xFF)) >>
            2;
        final bl =
            (((a >> 16) & 0xFF) +
                ((b >> 16) & 0xFF) +
                ((c >> 16) & 0xFF) +
                ((d >> 16) & 0xFF)) >>
            2;
        out[y * halfWidth + x] = 0xFF000000 | (bl << 16) | (g << 8) | r;
      }
    }
  }

  three.DataTexture _texture(Uint8List data, int w, int h) {
    return three.DataTexture(
        three.Uint8Array.fromList(data),
        w,
        h,
        three.RGBAFormat,
        three.UnsignedByteType,
      )
      ..wrapS = three.ClampToEdgeWrapping
      ..wrapT = three.ClampToEdgeWrapping
      ..magFilter = three.LinearFilter
      ..minFilter = three.LinearMipmapLinearFilter
      ..generateMipmaps = true
      ..anisotropy = 4
      ..needsUpdate = true;
  }

  three.DataTexture dayTexture() => _texture(_day, width ~/ 2, height ~/ 2);
  three.DataTexture nightTexture() => _texture(_night, width, height);
}

/// Building faces drawn with the atlas. Sun and sky are baked per vertex like
/// the rest of the scenery; the shader adds the night map on top, so lit
/// windows stay crisp and cut through the haze instead of fading with the wall.
class _FacadeMesh {
  final _positions = <double>[];
  final _normals = <double>[];
  final _uvs = <double>[];
  final _tints = <double>[];
  final _emit = <double>[];
  three.Float32BufferAttribute? _litAttribute;
  three.ShaderMaterial? _material;
  three.DataTexture? _dayTexture;
  three.DataTexture? _nightTexture;
  final three.Vector3 _fog = three.Vector3();

  int get count => _positions.length ~/ 3;

  /// Corners run bottom-left, bottom-right, top-right, top-left seen from
  /// outside the building.
  void quad(
    (double, double, double) bl,
    (double, double, double) br,
    (double, double, double) tr,
    (double, double, double) tl,
    (double, double, double, double) uv,
    _Rgb tint,
    double emit,
  ) {
    final n = _faceNormal([
      bl.$1,
      bl.$2,
      bl.$3,
      br.$1,
      br.$2,
      br.$3,
      tr.$1,
      tr.$2,
      tr.$3,
    ]);
    final (u0, v0, u1, v1) = uv;
    for (final (p, a, b) in [
      (bl, u0, v0),
      (br, u1, v0),
      (tr, u1, v1),
      (bl, u0, v0),
      (tr, u1, v1),
      (tl, u0, v1),
    ]) {
      _positions.addAll([p.$1, p.$2, p.$3]);
      _normals.addAll([n.$1, n.$2, n.$3]);
      _uvs.addAll([a, b]);
      _tints.addAll([tint.r, tint.g, tint.b]);
      _emit.add(emit);
    }
  }

  three.Mesh createMesh() {
    final lit = three.Float32BufferAttribute.fromList(
      List<double>.filled(count * 4, 1),
      4,
    );
    _litAttribute = lit;
    final geometry = three.BufferGeometry()
      ..setAttributeFromString(
        'position',
        three.Float32BufferAttribute.fromList(_positions, 3),
      )
      ..setAttributeFromString(
        'uv',
        three.Float32BufferAttribute.fromList(_uvs, 2),
      )
      ..setAttributeFromString('aLit', lit)
      ..setAttributeFromString(
        'aEmit',
        three.Float32BufferAttribute.fromList(_emit, 1),
      );
    final atlas = _FacadeAtlas.instance;
    _dayTexture = atlas.dayTexture();
    _nightTexture = atlas.nightTexture();
    final material = three.ShaderMaterial.fromMap({
      'uniforms': <String, dynamic>{
        'uDay': <String, dynamic>{'value': _dayTexture},
        'uNight': <String, dynamic>{'value': _nightTexture},
        'uGlow': <String, dynamic>{'value': 0.0},
        'uFog': <String, dynamic>{'value': _fog},
      },
      'vertexShader': '''
attribute vec4 aLit;
attribute float aEmit;
varying vec2 vUv;
varying vec4 vLit;
varying float vEmit;
void main() {
  vUv = uv;
  vLit = aLit;
  vEmit = aEmit;
  gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
}
''',
      'fragmentShader': '''
uniform sampler2D uDay;
uniform sampler2D uNight;
uniform float uGlow;
uniform vec3 uFog;
varying vec2 vUv;
varying vec4 vLit;
varying float vEmit;
void main() {
  vec3 wall = texture2D(uDay, vUv).rgb * vLit.rgb;
  vec3 color = mix(wall, uFog, vLit.a);
  vec3 lights = texture2D(uNight, vUv).rgb * uGlow * vEmit;
  gl_FragColor = vec4(color + lights * (1.0 - vLit.a * 0.35), 1.0);
}
''',
    });
    _material = material;
    return three.Mesh(geometry, material)..frustumCulled = false;
  }

  void relight(OutdoorLight light, double eyeX, double eyeY, double eyeZ) {
    final attribute = _litAttribute;
    final material = _material;
    if (attribute == null || material == null) {
      return;
    }
    final out = attribute.array.toDartList();
    final sun = _Rgb.hex(light.sun);
    final sky = _Rgb.hex(light.sky);
    final ground = _Rgb.hex(light.ground);
    final fog = _Rgb.hex(light.fog);
    // Facades fall nearly black after dark, so the windows carry the picture.
    final dim = 0.3 + 0.7 * _smoothstep(0, 0.5, light.daylight);
    final sat = light.saturation;
    for (var i = 0; i < count; i += 1) {
      final i3 = i * 3;
      final dx = _positions[i3] - eyeX;
      final dy = _positions[i3 + 1] - eyeY;
      final dz = _positions[i3 + 2] - eyeZ;
      final distance = math.sqrt(dx * dx + dy * dy + dz * dz);
      final nx = _normals[i3];
      final ny = _normals[i3 + 1];
      final nz = _normals[i3 + 2];
      final ndl = nx * light.sunX + ny * light.sunY + nz * light.sunZ;
      final diffuse = ((ndl + 0.3) / 1.3).clamp(0.0, 1.0) * light.sunStrength;
      final hemi = ny * 0.5 + 0.5;
      final ambient = light.ambientStrength;
      var r =
          (ground.r + (sky.r - ground.r) * hemi) * ambient + sun.r * diffuse;
      var g =
          (ground.g + (sky.g - ground.g) * hemi) * ambient + sun.g * diffuse;
      var b =
          (ground.b + (sky.b - ground.b) * hemi) * ambient + sun.b * diffuse;
      r *= _tints[i3] * dim;
      g *= _tints[i3 + 1] * dim;
      b *= _tints[i3 + 2] * dim;
      if (sat < 1) {
        final grey = r * 0.3 + g * 0.55 + b * 0.15;
        r = grey + (r - grey) * sat;
        g = grey + (g - grey) * sat;
        b = grey + (b - grey) * sat;
      }
      final far = math.max(0.0, distance - 9) / 46;
      final i4 = i * 4;
      out[i4] = r;
      out[i4 + 1] = g;
      out[i4 + 2] = b;
      out[i4 + 3] = (1 - math.exp(-far * far * 1.6)) * light.fogAmount;
    }
    attribute.needsUpdate = true;
    _fog.setValues(fog.r, fog.g, fog.b);
    material.uniforms['uGlow']['value'] = light.windowGlow;
  }

  void dispose() {
    _dayTexture?.dispose();
    _nightTexture?.dispose();
  }
}
