import 'dart:math' as math;

import 'package:back_home/rooms/isometric_room_view.dart';
import 'package:back_home/rooms/room_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('landscape room FOV avoids an ultra-wide distorted view', () {
    final verticalFov = roomVerticalFovForAspect(64, 16 / 9);
    final horizontalFov =
        2 *
        math.atan(math.tan(verticalFov * math.pi / 360) * 16 / 9) *
        180 /
        math.pi;

    expect(verticalFov, lessThan(64));
    expect(horizontalFov, closeTo(82, 0.001));
    expect(roomVerticalFovForAspect(64, 9 / 16), 64);
  });

  test('live sky time retains sub-minute clock precision', () {
    expect(
      skyTimeOfDayForDateTime(DateTime(2026, 1, 1, 6)),
      closeTo(0.25, 1e-9),
    );
    expect(
      skyTimeOfDayForDateTime(DateTime(2026, 1, 1, 18)),
      closeTo(0.75, 1e-9),
    );
    expect(
      skyTimeOfDayForDateTime(DateTime(2026, 1, 1, 12, 0, 30)),
      greaterThan(0.5),
    );
  });

  test('sun and moon follow opposite sunrise-to-sunset arcs', () {
    final sunrise = skyCelestialArc(0.25);
    final noon = skyCelestialArc(0.5);
    final sunset = skyCelestialArc(0.75);
    final midnightMoon = skyCelestialArc(0, moon: true);

    expect(sunrise.horizontal, closeTo(1, 1e-9));
    expect(sunrise.altitude, closeTo(0, 1e-9));
    expect(noon.horizontal, closeTo(0, 1e-9));
    expect(noon.altitude, closeTo(1, 1e-9));
    expect(sunset.horizontal, closeTo(-1, 1e-9));
    expect(sunset.altitude, closeTo(0, 1e-9));
    expect(midnightMoon.altitude, closeTo(1, 1e-9));
  });

  test('buyAndAddItem spends likes, adds inventory, and places the item', () {
    final controller = RoomEditorController();

    final result = controller.buyAndAddItem('fern-tree');

    expect(result.isSuccess, isTrue);
    expect(controller.likesBalance, 204);
    expect(controller.ownedCount('fern-tree'), 1);
    expect(controller.placedCount('fern-tree'), 1);
    expect(controller.selectedItemId, isNotNull);
  });

  test('movePlacedItem accepts freeform positions', () {
    final controller = RoomEditorController();

    final result = controller.movePlacedItem(
      'item-1',
      const GridPoint(3.25, 3.75),
    );

    expect(result.isSuccess, isTrue);
    expect(
      controller.placedItemById('item-1')?.origin,
      const GridPoint(3.25, 3.75),
    );
  });

  test('rotatePlacedItem supports small degree increments', () {
    final controller = RoomEditorController();

    final result = controller.rotatePlacedItem('item-1', deltaDegrees: 5);
    final item = controller.placedItemById('item-1');

    expect(result.isSuccess, isTrue);
    expect(item?.rotationDegrees, 5);
  });

  test('edit sessions only update the room when applied', () {
    final controller = RoomEditorController();
    final draft = RoomEditorController.editing(controller);

    draft.movePlacedItem('item-1', const GridPoint(0, 8));

    expect(controller.placedItemById('item-1')?.origin, const GridPoint(3, 3));

    controller.applyEditSession(draft);

    expect(controller.placedItemById('item-1')?.origin, const GridPoint(0, 8));
  });

  test('editing placement can start at a freeform preferred position', () {
    final controller = RoomEditorController();
    controller.purchaseItem('fern-tree');
    final draft = RoomEditorController.editing(controller);

    final result = draft.addOwnedItemForEditing(
      'fern-tree',
      preferredOrigin: const GridPoint(3, 3),
    );

    expect(result.isSuccess, isTrue);
    expect(result.instanceId, isNotNull);
    expect(
      draft.placedItemById(result.instanceId!)?.origin,
      const GridPoint(3, 3),
    );
    expect(draft.hasValidLayout, isTrue);
  });
}
