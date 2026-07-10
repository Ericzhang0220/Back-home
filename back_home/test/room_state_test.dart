import 'package:back_home/rooms/room_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
