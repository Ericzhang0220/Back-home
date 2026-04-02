import 'package:flutter/material.dart';

import 'room_state.dart';

class RoomSpriteSpec {
  const RoomSpriteSpec({
    required this.baseName,
    required this.widthUnits,
    required this.aspectRatio,
    required this.anchorY,
  });

  final String baseName;
  final double widthUnits;
  final double aspectRatio;
  final double anchorY;
}

RoomSpriteSpec roomSpriteSpecFor(RoomItemVisualKind kind) {
  switch (kind) {
    case RoomItemVisualKind.bed:
      return const RoomSpriteSpec(
        baseName: 'bedDouble',
        widthUnits: 6.6,
        aspectRatio: 174 / 216,
        anchorY: 0.84,
      );
    case RoomItemVisualKind.nightstand:
      return const RoomSpriteSpec(
        baseName: 'sideTableDrawers',
        widthUnits: 2.25,
        aspectRatio: 95 / 78,
        anchorY: 0.89,
      );
    case RoomItemVisualKind.wardrobe:
      return const RoomSpriteSpec(
        baseName: 'bookcaseClosedWide',
        widthUnits: 3.25,
        aspectRatio: 160 / 109,
        anchorY: 0.92,
      );
    case RoomItemVisualKind.vanity:
      return const RoomSpriteSpec(
        baseName: 'desk',
        widthUnits: 3.55,
        aspectRatio: 122 / 117,
        anchorY: 0.9,
      );
    case RoomItemVisualKind.ottoman:
      return const RoomSpriteSpec(
        baseName: 'stoolBarSquare',
        widthUnits: 1.08,
        aspectRatio: 63 / 31,
        anchorY: 0.9,
      );
    case RoomItemVisualKind.floorLamp:
      return const RoomSpriteSpec(
        baseName: 'lampRoundFloor',
        widthUnits: 0.82,
        aspectRatio: 105 / 25,
        anchorY: 0.95,
      );
    case RoomItemVisualKind.plant:
      return const RoomSpriteSpec(
        baseName: 'plantSmall3',
        widthUnits: 0.72,
        aspectRatio: 20 / 14,
        anchorY: 0.92,
      );
  }
}

String roomSpriteAssetForKind(RoomItemVisualKind kind, int quarterTurns) {
  final suffix = switch (quarterTurns % 4) {
    0 => 'NW',
    1 => 'SW',
    2 => 'SE',
    _ => 'NE',
  };
  final spec = roomSpriteSpecFor(kind);
  return 'assets/kenney_furniture-kit/Isometric/${spec.baseName}_$suffix.png';
}

String roomSpriteAssetForDefinition(
  RoomItemDefinition definition, {
  int quarterTurns = 0,
}) {
  return roomSpriteAssetForKind(definition.visualKind, quarterTurns);
}

class RoomSpriteThumbnail extends StatelessWidget {
  const RoomSpriteThumbnail({
    super.key,
    required this.definition,
    this.quarterTurns = 0,
    this.size = 72,
  });

  final RoomItemDefinition definition;
  final int quarterTurns;
  final double size;

  @override
  Widget build(BuildContext context) {
    final spec = roomSpriteSpecFor(definition.visualKind);
    final spriteWidth = size * 0.92;
    final spriteHeight = spriteWidth * spec.aspectRatio;

    return SizedBox(
      width: size,
      height: size,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Image.asset(
          roomSpriteAssetForDefinition(definition, quarterTurns: quarterTurns),
          width: spriteWidth,
          height: spriteHeight,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            return Icon(definition.icon, color: const Color(0xFF3D2B22));
          },
        ),
      ),
    );
  }
}
