import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:three_js/three_js.dart' as three;

import 'package:back_home/rooms/furniture_models.dart';
import 'package:back_home/rooms/room_state.dart';

/// Geometry checks for the catalog pieces. These are hard to eyeball — a piece
/// that floats, sinks into the floor, or spills outside its grid cell looks
/// merely "a bit off" in a 200px preview but collides with its neighbours in the
/// room — so the invariants are asserted instead.
void main() {
  final controller = RoomEditorController();

  ({double width, double height, double depth, double floor}) measure(
    three.Object3D model,
  ) {
    final bounds = three.BoundingBox().setFromObject(model);
    return (
      width: bounds.max.x - bounds.min.x,
      height: bounds.max.y - bounds.min.y,
      depth: bounds.max.z - bounds.min.z,
      floor: bounds.min.y,
    );
  }

  test('every visual kind has a palette', () {
    for (final kind in RoomItemVisualKind.values) {
      expect(
        kFurniturePalettes.containsKey(kind),
        isTrue,
        reason: '$kind has no entry in kFurniturePalettes',
      );
    }
  });

  test('every catalog piece rests on the floor', () {
    for (final definition in controller.catalog) {
      final size = measure(buildFurnitureVisualFor(definition));
      expect(
        size.floor,
        closeTo(0, 0.02),
        reason: '${definition.title} does not sit on y = 0',
      );
      expect(
        size.height,
        greaterThan(0.2),
        reason: '${definition.title} has no meaningful height',
      );
    }
  });

  test('every catalog piece fits inside its grid footprint', () {
    for (final definition in controller.catalog) {
      final size = measure(buildFurnitureVisualFor(definition));
      final footprint = definition.footprintForRotation(0);
      final maxWidth = footprint.width * RoomEditorController.cellSize;
      final maxDepth = footprint.depth * RoomEditorController.cellSize;

      expect(
        size.width,
        lessThanOrEqualTo(maxWidth),
        reason:
            '${definition.title} is ${size.width.toStringAsFixed(2)} wide but '
            'its footprint allows $maxWidth',
      );
      expect(
        size.depth,
        lessThanOrEqualTo(maxDepth),
        reason:
            '${definition.title} is ${size.depth.toStringAsFixed(2)} deep but '
            'its footprint allows $maxDepth',
      );
    }
  });

  test('recolouring a piece changes its materials, not its shape', () {
    final defaultBed = measure(buildFurnitureVisual(RoomItemVisualKind.bed));
    final recoloured = measure(
      buildFurnitureVisual(
        RoomItemVisualKind.bed,
        palette: furniturePaletteFor(
          RoomItemVisualKind.bed,
        ).copyWith(soft: const Color(0xFF3355AA)),
      ),
    );

    expect(recoloured.width, closeTo(defaultBed.width, 0.001));
    expect(recoloured.height, closeTo(defaultBed.height, 0.001));
    expect(recoloured.depth, closeTo(defaultBed.depth, 0.001));
  });
}
