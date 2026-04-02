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

  test('movePlacedItem rejects collisions with existing furniture', () {
    final controller = RoomEditorController();

    final result = controller.movePlacedItem('item-2', const GridPoint(1, 2));

    expect(result.isSuccess, isFalse);
    expect(result.message, contains('blocked'));
    expect(controller.placedItemById('item-2')?.origin, const GridPoint(0, 4));
  });

  test('rotatePlacedItem rotates when the footprint still fits', () {
    final controller = RoomEditorController();

    final result = controller.rotatePlacedItem('item-3');
    final item = controller.placedItemById('item-3');

    expect(result.isSuccess, isTrue);
    expect(item?.rotationQuarterTurns, 1);
  });
}
