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

int furnitureHex(Color color) => color.toARGB32() & 0x00ffffff;

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
  return three.Mesh(
      three.BoxGeometry(width, height, depth),
      three.MeshPhongMaterial.fromMap({'color': furnitureHex(color)}),
    )
    ..position.setValues(x, y, z)
    ..castShadow = castShadow
    ..receiveShadow = receiveShadow;
}

three.Mesh furnitureLeaf(double x, double y, double z, double radius) {
  return three.Mesh(
      three.SphereGeometry(radius, 14, 14),
      three.MeshPhongMaterial.fromMap({
        'color': furnitureHex(const Color(0xFF748F63)),
      }),
    )
    ..position.setValues(x, y, z)
    ..castShadow = true;
}

three.Group buildFurnitureVisual(RoomItemVisualKind kind) {
  switch (kind) {
    case RoomItemVisualKind.bed:
      return _buildBed();
    case RoomItemVisualKind.nightstand:
      return _buildNightstand();
    case RoomItemVisualKind.wardrobe:
      return _buildWardrobe();
    case RoomItemVisualKind.vanity:
      return _buildVanity();
    case RoomItemVisualKind.ottoman:
      return _buildOttoman();
    case RoomItemVisualKind.floorLamp:
      return _buildFloorLamp();
    case RoomItemVisualKind.plant:
      return _buildPlant();
  }
}

three.Group buildFurnitureVisualFor(RoomItemDefinition definition) =>
    buildFurnitureVisual(definition.visualKind);

three.Group _buildBed() {
  final group = three.Group();
  group.add(
    furnitureBox(
      width: 2.7,
      height: 0.42,
      depth: 3.6,
      color: const Color(0xFFD1C8BD),
      y: 0.22,
    ),
  );
  group.add(
    furnitureBox(
      width: 2.76,
      height: 1.02,
      depth: 0.18,
      color: const Color(0xFFC6C1B8),
      y: 0.72,
      z: -1.68,
    ),
  );
  group.add(
    furnitureBox(
      width: 2.56,
      height: 0.18,
      depth: 3.0,
      color: const Color(0xFFBFB8AF),
      y: 0.54,
    ),
  );
  group.add(
    furnitureBox(
      width: 2.54,
      height: 0.2,
      depth: 3.0,
      color: const Color(0xFFCFC7BD),
      y: 0.78,
    ),
  );
  group.add(
    furnitureBox(
      width: 2.34,
      height: 0.16,
      depth: 2.82,
      color: const Color(0xFFD9D2C7),
      y: 0.91,
    ),
  );
  group.add(
    furnitureBox(
      width: 0.86,
      height: 0.18,
      depth: 0.58,
      color: const Color(0xFFE2DBD0),
      y: 1.05,
      x: -0.48,
      z: -1.18,
    ),
  );
  group.add(
    furnitureBox(
      width: 0.86,
      height: 0.18,
      depth: 0.58,
      color: const Color(0xFFE2DBD0),
      y: 1.05,
      x: 0.48,
      z: -1.18,
    ),
  );
  return group;
}

three.Group _buildNightstand() {
  final group = three.Group();
  group.add(
    furnitureBox(
      width: 0.82,
      height: 0.72,
      depth: 0.82,
      color: const Color(0xFF8A6957),
      y: 0.36,
    ),
  );
  group.add(
    furnitureBox(
      width: 0.82,
      height: 0.08,
      depth: 0.82,
      color: const Color(0xFFC8B8A5),
      y: 0.78,
    ),
  );
  return group;
}

three.Group _buildWardrobe() {
  final group = three.Group();
  group.add(
    furnitureBox(
      width: 1.72,
      height: 2.88,
      depth: 0.78,
      color: const Color(0xFFBCA992),
      y: 1.44,
    ),
  );
  group.add(
    furnitureBox(
      width: 0.08,
      height: 2.6,
      depth: 0.8,
      color: const Color(0xFF41332E),
      x: -0.86,
      y: 1.3,
    ),
  );
  group.add(
    furnitureBox(
      width: 0.08,
      height: 2.6,
      depth: 0.8,
      color: const Color(0xFF41332E),
      x: 0.86,
      y: 1.3,
    ),
  );
  return group;
}

three.Group _buildVanity() {
  final group = three.Group();
  group.add(
    furnitureBox(
      width: 1.9,
      height: 0.14,
      depth: 0.74,
      color: const Color(0xFF6A4B3E),
      y: 0.72,
    ),
  );
  for (final x in const [-0.78, 0.78]) {
    for (final z in const [-0.26, 0.26]) {
      group.add(
        furnitureBox(
          width: 0.08,
          height: 0.72,
          depth: 0.08,
          color: const Color(0xFFC7B7A6),
          x: x,
          y: 0.36,
          z: z,
        ),
      );
    }
  }
  group.add(
    furnitureBox(
      width: 0.82,
      height: 1.0,
      depth: 0.08,
      color: const Color(0xFFB5BDC5),
      y: 1.34,
      z: -0.3,
    ),
  );
  return group;
}

three.Group _buildOttoman() {
  final group = three.Group();
  group.add(
    furnitureBox(
      width: 0.72,
      height: 0.48,
      depth: 0.72,
      color: const Color(0xFF8A7A68),
      y: 0.24,
    ),
  );
  group.add(
    furnitureBox(
      width: 0.64,
      height: 0.12,
      depth: 0.64,
      color: const Color(0xFFC59F92),
      y: 0.54,
    ),
  );
  return group;
}

three.Group _buildFloorLamp() {
  final group = three.Group();
  group.add(
    furnitureBox(
      width: 0.12,
      height: 1.48,
      depth: 0.12,
      color: const Color(0xFF22211F),
      y: 0.74,
    ),
  );
  group.add(
    furnitureBox(
      width: 0.38,
      height: 0.04,
      depth: 0.38,
      color: const Color(0xFF262321),
      y: 0.03,
    ),
  );
  group.add(
    furnitureBox(
      width: 0.56,
      height: 0.46,
      depth: 0.56,
      color: const Color(0xFFD7B693),
      y: 1.58,
    ),
  );
  return group;
}

three.Group _buildPlant() {
  final group = three.Group();
  final pot =
      three.Mesh(
          three.CylinderGeometry(0.18, 0.16, 0.28, 14),
          three.MeshPhongMaterial.fromMap({
            'color': furnitureHex(const Color(0xFFB77E58)),
          }),
        )
        ..position.setValues(0, 0.14, 0)
        ..castShadow = true;
  group.add(pot);

  group.add(furnitureLeaf(-0.12, 0.58, 0.02, 0.18));
  group.add(furnitureLeaf(0.12, 0.60, -0.02, 0.20));
  group.add(furnitureLeaf(0.00, 0.72, 0.04, 0.22));
  return group;
}
