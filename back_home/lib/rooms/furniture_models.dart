import 'package:flutter/material.dart';
import 'package:three_js/three_js.dart' as three;

import 'room_state.dart';

/// The 3D geometry for every catalog piece, in one place.
///
/// These used to live as private methods on the room view's State, which meant
/// the shop had no way to show what a piece actually looks like — it fell back
/// to Kenney sprites that were only loosely related to the real thing. Now both
/// the room and the shop's previews build from these functions, so a card can
/// never drift from what lands in the room.
///
/// Everything is authored around the origin with y = 0 as the floor, so a group
/// can be dropped straight onto the room floor or re-centred for a preview.
/// Each piece also has to stay inside its grid footprint (see
/// [RoomItemDefinition.width] / `depth`, one cell = 1.0), which is why the
/// vanity's stool tucks under the desk rather than sitting out in front of it.
///
/// Colours are NOT written into the geometry below — every piece paints itself
/// from a [FurniturePalette]. See `kFurniturePalettes` for the one place to
/// change how anything looks.

// =============================================================================
// >>> COLOURS: THIS IS THE PLACE TO RECOLOUR FURNITURE <<<
//
// Every piece paints from six named roles. Change a value in kFurniturePalettes
// and hot-restart — the room and the shop previews both pick it up, because
// they build from the same functions.
//
//   frame     the main body: bed base, carcass, desk top, pot
//   surface   secondary faces: doors, drawer fronts, table tops, soil
//   accent    trim and highlights: cornice, seam, lamp shade, pot rim
//   hardware  handles, feet, legs, poles, stems
//   soft      upholstery and foliage: bedding, cushions, leaves
//   glass     mirrors and bulbs
//
// Shades within a piece are derived with furnitureShade() rather than pinned to
// their own hex, so recolouring one role keeps a piece internally consistent —
// change `soft` on the bed and every bedding layer moves with it.
//
// To recolour a single item at runtime (a shop "choose a finish" feature, say),
// pass a palette to buildFurnitureVisual:
//
//   buildFurnitureVisual(kind, palette: furniturePaletteFor(kind).copyWith(
//     soft: const Color(0xFFBFD3E8),
//   ));
// =============================================================================

/// The six colour roles a piece paints from. Not every piece uses every role —
/// the comment above each entry in [kFurniturePalettes] says what it paints
/// there.
@immutable
class FurniturePalette {
  const FurniturePalette({
    required this.frame,
    required this.surface,
    required this.accent,
    required this.hardware,
    required this.soft,
    this.glass = const Color(0xFFB5BDC5),
  });

  final Color frame;
  final Color surface;
  final Color accent;
  final Color hardware;
  final Color soft;
  final Color glass;

  FurniturePalette copyWith({
    Color? frame,
    Color? surface,
    Color? accent,
    Color? hardware,
    Color? soft,
    Color? glass,
  }) {
    return FurniturePalette(
      frame: frame ?? this.frame,
      surface: surface ?? this.surface,
      accent: accent ?? this.accent,
      hardware: hardware ?? this.hardware,
      soft: soft ?? this.soft,
      glass: glass ?? this.glass,
    );
  }
}

/// Every piece's default colours. Edit here.
const Map<RoomItemVisualKind, FurniturePalette> kFurniturePalettes = {
  // frame: bed base · surface: headboard · soft: sheets, duvet and pillows
  RoomItemVisualKind.bed: FurniturePalette(
    frame: Color(0xFFD1C8BD),
    surface: Color(0xFFC6C1B8),
    accent: Color(0xFFE2DBD0),
    hardware: Color(0xFF6E5B4C),
    soft: Color(0xFFCFC7BD),
  ),
  // frame: carcass · surface: drawer fronts · accent: top slab · hardware: legs
  // and pulls
  RoomItemVisualKind.nightstand: FurniturePalette(
    frame: Color(0xFF8A6957),
    surface: Color(0xFFA1806C),
    accent: Color(0xFFC8B8A5),
    hardware: Color(0xFF3A2E28),
    soft: Color(0xFFC59F92),
  ),
  // frame: carcass · surface: doors · accent: cornice · hardware: plinth and
  // handles
  RoomItemVisualKind.wardrobe: FurniturePalette(
    frame: Color(0xFFBCA992),
    surface: Color(0xFFC9B7A0),
    accent: Color(0xFFC9B7A0),
    hardware: Color(0xFF3A2E28),
    soft: Color(0xFFC59F92),
  ),
  // frame: desk top and mirror posts · surface: drawer · accent: legs ·
  // soft: stool cushion · glass: mirror
  RoomItemVisualKind.vanity: FurniturePalette(
    frame: Color(0xFF6A4B3E),
    surface: Color(0xFF7E5B4A),
    accent: Color(0xFFC7B7A6),
    hardware: Color(0xFF3A2E28),
    soft: Color(0xFFC59F92),
    glass: Color(0xFFB5BDC5),
  ),
  // frame: pouf body · accent: seam · soft: cushion · hardware: feet
  RoomItemVisualKind.ottoman: FurniturePalette(
    frame: Color(0xFF8A7A68),
    surface: Color(0xFF9B8B77),
    accent: Color(0xFF75664F),
    hardware: Color(0xFF4A382E),
    soft: Color(0xFFC59F92),
  ),
  // accent: cone shade · hardware: base and pole · glass: bulb
  RoomItemVisualKind.floorLamp: FurniturePalette(
    frame: Color(0xFF262321),
    surface: Color(0xFF2E2B28),
    accent: Color(0xFFD7B693),
    hardware: Color(0xFF22211F),
    soft: Color(0xFFE7CBA8),
    glass: Color(0xFFF6E2C0),
  ),
  // frame: pot · accent: pot rim · surface: soil · hardware: stems ·
  // soft: fronds
  RoomItemVisualKind.plant: FurniturePalette(
    frame: Color(0xFFB77E58),
    surface: Color(0xFF3F3229),
    accent: Color(0xFFC98F66),
    hardware: Color(0xFF5E7350),
    soft: Color(0xFF748F63),
  ),
};

FurniturePalette furniturePaletteFor(RoomItemVisualKind kind) =>
    kFurniturePalettes[kind]!;

/// Lightens (positive) or darkens (negative) a colour, for the shades within a
/// piece. Keeps recolouring to one value per role instead of one per mesh.
Color furnitureShade(Color color, double amount) {
  final target = amount >= 0 ? Colors.white : Colors.black;
  return Color.lerp(color, target, amount.abs().clamp(0.0, 1.0))!;
}

int furnitureHex(Color color) => color.toARGB32() & 0x00ffffff;

three.MeshPhongMaterial _material(Color color) =>
    three.MeshPhongMaterial.fromMap({'color': furnitureHex(color)});

three.Mesh furnitureBox({
  required double width,
  required double height,
  required double depth,
  required Color color,
  double x = 0,
  double y = 0,
  double z = 0,
  bool castShadow = true,
  bool receiveShadow = true,
}) {
  return three.Mesh(three.BoxGeometry(width, height, depth), _material(color))
    ..position.setValues(x, y, z)
    ..castShadow = castShadow
    ..receiveShadow = receiveShadow;
}

/// Turned parts: legs, poles, pots, and — with different top/bottom radii —
/// tapered shades and planters.
three.Mesh furnitureCylinder({
  required double radiusTop,
  required double radiusBottom,
  required double height,
  required Color color,
  double x = 0,
  double y = 0,
  double z = 0,
  double tiltX = 0,
  double tiltZ = 0,
  int segments = 18,
}) {
  final mesh =
      three.Mesh(
          three.CylinderGeometry(radiusTop, radiusBottom, height, segments),
          _material(color),
        )
        ..position.setValues(x, y, z)
        ..castShadow = true
        ..receiveShadow = true;
  mesh.rotation.x = tiltX;
  mesh.rotation.z = tiltZ;
  return mesh;
}

/// Soft rounded mass — cushions and foliage. Scaled per axis so a sphere can
/// read as a squashed pad or a long leaf.
three.Mesh furnitureBlob({
  required double radius,
  required Color color,
  double x = 0,
  double y = 0,
  double z = 0,
  double scaleX = 1,
  double scaleY = 1,
  double scaleZ = 1,
  double tiltZ = 0,
}) {
  final mesh =
      three.Mesh(three.SphereGeometry(radius, 16, 12), _material(color))
        ..position.setValues(x, y, z)
        ..castShadow = true
        ..receiveShadow = true;
  mesh.scale.setValues(scaleX, scaleY, scaleZ);
  mesh.rotation.z = tiltZ;
  return mesh;
}

/// Builds a piece. Pass [palette] to recolour it; omit for the catalog default.
three.Group buildFurnitureVisual(
  RoomItemVisualKind kind, {
  FurniturePalette? palette,
}) {
  final colors = palette ?? furniturePaletteFor(kind);
  switch (kind) {
    case RoomItemVisualKind.bed:
      return _buildBed(colors);
    case RoomItemVisualKind.nightstand:
      return _buildNightstand(colors);
    case RoomItemVisualKind.wardrobe:
      return _buildWardrobe(colors);
    case RoomItemVisualKind.vanity:
      return _buildVanity(colors);
    case RoomItemVisualKind.ottoman:
      return _buildOttoman(colors);
    case RoomItemVisualKind.floorLamp:
      return _buildFloorLamp(colors);
    case RoomItemVisualKind.plant:
      return _buildPlant(colors);
  }
}

three.Group buildFurnitureVisualFor(
  RoomItemDefinition definition, {
  FurniturePalette? palette,
}) => buildFurnitureVisual(definition.visualKind, palette: palette);

/// Low frame, stacked duvet layers, headboard and two pillows.
three.Group _buildBed(FurniturePalette colors) {
  final group = three.Group();

  group.add(
    furnitureBox(
      width: 2.7,
      height: 0.42,
      depth: 3.6,
      color: colors.frame,
      y: 0.22,
    ),
  );
  group.add(
    furnitureBox(
      width: 2.76,
      height: 1.02,
      depth: 0.18,
      color: colors.surface,
      y: 0.72,
      z: -1.68,
    ),
  );
  // Sheet, duvet, then folded throw — each a step lighter than the last.
  group.add(
    furnitureBox(
      width: 2.56,
      height: 0.18,
      depth: 3.0,
      color: furnitureShade(colors.soft, -0.06),
      y: 0.54,
    ),
  );
  group.add(
    furnitureBox(
      width: 2.54,
      height: 0.2,
      depth: 3.0,
      color: colors.soft,
      y: 0.78,
    ),
  );
  group.add(
    furnitureBox(
      width: 2.34,
      height: 0.16,
      depth: 2.82,
      color: furnitureShade(colors.soft, 0.07),
      y: 0.91,
    ),
  );
  for (final x in const [-0.48, 0.48]) {
    group.add(
      furnitureBox(
        width: 0.86,
        height: 0.18,
        depth: 0.58,
        color: colors.accent,
        y: 1.05,
        x: x,
        z: -1.18,
      ),
    );
  }

  return group;
}

/// Two-drawer bedside table on tapered legs. Was a body box with a lid on top,
/// which read as a crate at preview size.
three.Group _buildNightstand(FurniturePalette colors) {
  final group = three.Group();

  for (final x in const [-0.31, 0.31]) {
    for (final z in const [-0.31, 0.31]) {
      group.add(
        furnitureCylinder(
          radiusTop: 0.028,
          radiusBottom: 0.022,
          height: 0.18,
          color: furnitureShade(colors.hardware, 0.12),
          x: x,
          y: 0.09,
          z: z,
          segments: 10,
        ),
      );
    }
  }

  group.add(
    furnitureBox(
      width: 0.78,
      height: 0.5,
      depth: 0.72,
      color: colors.frame,
      y: 0.43,
    ),
  );

  // Drawer fronts sit proud of the carcass so the shadow line reads.
  for (final y in const [0.31, 0.55]) {
    group.add(
      furnitureBox(
        width: 0.7,
        height: 0.2,
        depth: 0.04,
        color: colors.surface,
        y: y,
        z: 0.37,
      ),
    );
    group.add(
      furnitureBox(
        width: 0.24,
        height: 0.03,
        depth: 0.04,
        color: colors.hardware,
        y: y,
        z: 0.4,
      ),
    );
  }

  group.add(
    furnitureBox(
      width: 0.86,
      height: 0.06,
      depth: 0.8,
      color: colors.accent,
      y: 0.71,
    ),
  );

  return group;
}

/// Two-door wardrobe with a plinth, recessed door panels and a cornice. Was a
/// slab with two dark stripes glued to the front.
three.Group _buildWardrobe(FurniturePalette colors) {
  final group = three.Group();

  group.add(
    furnitureBox(
      width: 1.62,
      height: 0.1,
      depth: 0.7,
      color: furnitureShade(colors.hardware, 0.1),
      y: 0.05,
    ),
  );
  group.add(
    furnitureBox(
      width: 1.72,
      height: 2.55,
      depth: 0.78,
      color: colors.frame,
      y: 1.38,
    ),
  );

  for (final x in const [-0.43, 0.43]) {
    group.add(
      furnitureBox(
        width: 0.8,
        height: 2.4,
        depth: 0.05,
        color: colors.surface,
        x: x,
        y: 1.38,
        z: 0.4,
      ),
    );
    // Recessed panel: a slightly darker, slightly smaller face inside the door.
    group.add(
      furnitureBox(
        width: 0.58,
        height: 1.94,
        depth: 0.02,
        color: furnitureShade(colors.surface, -0.08),
        x: x,
        y: 1.38,
        z: 0.43,
      ),
    );
    group.add(
      furnitureBox(
        width: 0.035,
        height: 0.3,
        depth: 0.035,
        color: colors.hardware,
        x: x > 0 ? 0.09 : -0.09,
        y: 1.38,
        z: 0.44,
      ),
    );
  }

  group.add(
    furnitureBox(
      width: 1.84,
      height: 0.12,
      depth: 0.88,
      color: colors.accent,
      y: 2.71,
    ),
  );

  return group;
}

/// Desk, framed mirror and the stool its description has always promised. The
/// stool tucks under the desk so the piece stays inside its 2x1 footprint.
three.Group _buildVanity(FurniturePalette colors) {
  final group = three.Group();

  group.add(
    furnitureBox(
      width: 1.9,
      height: 0.09,
      depth: 0.7,
      color: colors.frame,
      y: 0.76,
    ),
  );

  for (final x in const [-0.85, 0.85]) {
    for (final z in const [-0.28, 0.28]) {
      group.add(
        furnitureCylinder(
          radiusTop: 0.042,
          radiusBottom: 0.03,
          height: 0.72,
          color: colors.accent,
          x: x,
          y: 0.36,
          z: z,
          segments: 10,
        ),
      );
    }
  }

  // Apron at the back, shallow drawer at the front.
  group.add(
    furnitureBox(
      width: 1.7,
      height: 0.12,
      depth: 0.05,
      color: furnitureShade(colors.frame, -0.1),
      y: 0.65,
      z: -0.3,
    ),
  );
  group.add(
    furnitureBox(
      width: 0.66,
      height: 0.16,
      depth: 0.06,
      color: colors.surface,
      y: 0.64,
      z: 0.33,
    ),
  );
  group.add(
    furnitureBox(
      width: 0.22,
      height: 0.028,
      depth: 0.035,
      color: colors.hardware,
      y: 0.64,
      z: 0.37,
    ),
  );

  // Mirror on two posts.
  for (final x in const [-0.42, 0.42]) {
    group.add(
      furnitureBox(
        width: 0.05,
        height: 0.42,
        depth: 0.05,
        color: colors.frame,
        x: x,
        y: 1.01,
        z: -0.26,
      ),
    );
  }
  group.add(
    furnitureBox(
      width: 0.94,
      height: 0.74,
      depth: 0.05,
      color: colors.surface,
      y: 1.57,
      z: -0.26,
    ),
  );
  group.add(
    furnitureBox(
      width: 0.8,
      height: 0.6,
      depth: 0.02,
      color: colors.glass,
      y: 1.57,
      z: -0.23,
    ),
  );

  // Stool, pushed in under the desk.
  for (final x in const [-0.13, 0.13]) {
    for (final z in const [-0.01, 0.25]) {
      group.add(
        furnitureCylinder(
          radiusTop: 0.024,
          radiusBottom: 0.018,
          height: 0.42,
          color: colors.accent,
          x: x,
          y: 0.21,
          z: z,
          segments: 8,
        ),
      );
    }
  }
  group.add(
    furnitureCylinder(
      radiusTop: 0.21,
      radiusBottom: 0.2,
      height: 0.07,
      color: colors.soft,
      y: 0.45,
      z: 0.12,
    ),
  );
  group.add(
    furnitureBlob(
      radius: 0.2,
      color: furnitureShade(colors.soft, 0.08),
      y: 0.49,
      z: 0.12,
      scaleY: 0.34,
    ),
  );

  return group;
}

/// Round upholstered pouf: feet, a tapered body, a seam and a domed cushion.
/// Was two stacked boxes.
three.Group _buildOttoman(FurniturePalette colors) {
  final group = three.Group();

  for (final x in const [-0.2, 0.2]) {
    for (final z in const [-0.2, 0.2]) {
      group.add(
        furnitureCylinder(
          radiusTop: 0.032,
          radiusBottom: 0.026,
          height: 0.09,
          color: colors.hardware,
          x: x,
          y: 0.045,
          z: z,
          segments: 8,
        ),
      );
    }
  }

  group.add(
    furnitureCylinder(
      radiusTop: 0.34,
      radiusBottom: 0.3,
      height: 0.3,
      color: colors.frame,
      y: 0.24,
    ),
  );
  group.add(
    furnitureCylinder(
      radiusTop: 0.345,
      radiusBottom: 0.345,
      height: 0.04,
      color: colors.accent,
      y: 0.37,
    ),
  );
  group.add(
    furnitureCylinder(
      radiusTop: 0.34,
      radiusBottom: 0.345,
      height: 0.12,
      color: colors.soft,
      y: 0.45,
    ),
  );
  group.add(
    furnitureBlob(
      radius: 0.33,
      color: furnitureShade(colors.soft, 0.08),
      y: 0.5,
      scaleY: 0.36,
    ),
  );

  return group;
}

/// Weighted base, slim pole and an actual cone shade — the description always
/// said cone, the model was a cube.
three.Group _buildFloorLamp(FurniturePalette colors) {
  final group = three.Group();

  group.add(
    furnitureCylinder(
      radiusTop: 0.2,
      radiusBottom: 0.24,
      height: 0.05,
      color: colors.frame,
      y: 0.025,
    ),
  );
  group.add(
    furnitureCylinder(
      radiusTop: 0.08,
      radiusBottom: 0.11,
      height: 0.07,
      color: colors.surface,
      y: 0.075,
    ),
  );
  group.add(
    furnitureCylinder(
      radiusTop: 0.022,
      radiusBottom: 0.026,
      height: 1.45,
      color: colors.hardware,
      y: 0.82,
      segments: 10,
    ),
  );
  group.add(furnitureBlob(radius: 0.09, color: colors.glass, y: 1.62));
  group.add(
    furnitureCylinder(
      radiusTop: 0.17,
      radiusBottom: 0.31,
      height: 0.44,
      color: colors.accent,
      y: 1.72,
      segments: 22,
    ),
  );
  group.add(
    furnitureCylinder(
      radiusTop: 0.315,
      radiusBottom: 0.315,
      height: 0.03,
      color: colors.soft,
      y: 1.5,
      segments: 22,
    ),
  );

  return group;
}

/// Tall potted fern: tapered planter, soil, splayed stems and layered fronds.
/// Was a pot with three balls sitting in it, which read as a shrub at best —
/// and the catalog calls it a tall plant.
three.Group _buildPlant(FurniturePalette colors) {
  final group = three.Group();

  group.add(
    furnitureCylinder(
      radiusTop: 0.21,
      radiusBottom: 0.15,
      height: 0.34,
      color: colors.frame,
      y: 0.17,
    ),
  );
  group.add(
    furnitureCylinder(
      radiusTop: 0.225,
      radiusBottom: 0.22,
      height: 0.06,
      color: colors.accent,
      y: 0.34,
    ),
  );
  group.add(
    furnitureCylinder(
      radiusTop: 0.19,
      radiusBottom: 0.19,
      height: 0.03,
      color: colors.surface,
      y: 0.35,
    ),
  );

  // Stems fan outward from the pot; each carries a frond at its tip.
  const stems = [
    (tiltX: 0.0, tiltZ: 0.34, height: 0.62, x: 0.13, z: 0.02),
    (tiltX: 0.0, tiltZ: -0.4, height: 0.72, x: -0.15, z: -0.04),
    (tiltX: 0.26, tiltZ: 0.06, height: 0.86, x: 0.03, z: 0.1),
    (tiltX: -0.2, tiltZ: -0.1, height: 0.98, x: -0.02, z: -0.08),
  ];

  for (final stem in stems) {
    final tipY = 0.36 + stem.height;
    group.add(
      furnitureCylinder(
        radiusTop: 0.016,
        radiusBottom: 0.026,
        height: stem.height,
        color: colors.hardware,
        x: stem.x,
        y: 0.36 + stem.height / 2,
        z: stem.z,
        tiltX: stem.tiltX,
        tiltZ: stem.tiltZ,
        segments: 8,
      ),
    );
    group.add(
      furnitureBlob(
        radius: 0.17,
        color: colors.soft,
        x: stem.x - stem.tiltZ * stem.height * 0.55,
        y: tipY,
        z: stem.z + stem.tiltX * stem.height * 0.55,
        scaleX: 1.35,
        scaleY: 0.42,
        scaleZ: 0.85,
        tiltZ: stem.tiltZ,
      ),
    );
  }

  // A lighter crown so the top doesn't read as one flat mass.
  group.add(
    furnitureBlob(
      radius: 0.16,
      color: furnitureShade(colors.soft, 0.12),
      y: 1.36,
      scaleX: 1.15,
      scaleY: 0.5,
      scaleZ: 0.9,
    ),
  );

  return group;
}
