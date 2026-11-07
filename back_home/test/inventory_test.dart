import 'package:back_home/keyboard/keyboard_catalog.dart';
import 'package:back_home/keyboard/keyboard_store.dart';
import 'package:back_home/rooms/room_state.dart';
import 'package:back_home/screens/inventory_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'furniture ownership, placement and wallet reload per account',
    () async {
      final room = RoomEditorController();
      final store = KeyboardStore(room);
      addTearDown(store.dispose);
      addTearDown(room.dispose);
      await store.loadForAccount('a');
      expect(room.buyAndAddItem('fern-tree').isSuccess, isTrue);
      final placement = room.placedItems.firstWhere(
        (item) => item.definitionId == 'fern-tree',
      );
      final balance = room.likesBalance;
      await store.loadForAccount(
        'b',
      ); // Waits for pending saves before switching.
      expect(room.ownedCount('fern-tree'), 0);
      await store.loadForAccount('a');
      expect(room.ownedCount('fern-tree'), 1);
      expect(room.likesBalance, balance);
      expect(
        room.placedItems
            .firstWhere((item) => item.definitionId == 'fern-tree')
            .instanceId,
        placement.instanceId,
      );
    },
  );

  testWidgets(
    'inventory applies owned keyboards for free and groups furniture',
    (tester) async {
      final room = RoomEditorController();
      final store = KeyboardStore(room);
      addTearDown(store.dispose);
      addTearDown(room.dispose);
      await store.loadForAccount('a');
      final skin = keyboardSkins.first;
      expect(await store.buyOrApply(skin, KeyboardUseScope.aiOnly), isNull);
      final balance = room.likesBalance;
      await tester.pumpWidget(MaterialApp(home: InventoryScreen(store: store)));
      await tester.pumpAndSettle();
      expect(
        tester.widgetList<Switch>(find.byType(Switch)).where((s) => s.value),
        hasLength(1),
      );
      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      expect(store.enabled, isFalse);
      expect(
        tester.widgetList<Switch>(find.byType(Switch)).every((s) => !s.value),
        isTrue,
      );
      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('All app pages'));
      await tester.pumpAndSettle();
      expect(store.scope, KeyboardUseScope.allPages);
      expect(room.likesBalance, balance);
      expect(store.enabled, isTrue);
      // Enabling the other owned keyboard transfers the single active state.
      await tester.tap(find.byType(Switch).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('AI chats only'));
      await tester.pumpAndSettle();
      expect(
        tester.widgetList<Switch>(find.byType(Switch)).where((s) => s.value),
        hasLength(1),
      );
      expect(tester.widget<Switch>(find.byType(Switch).first).value, isFalse);
      expect(room.likesBalance, balance);
      await tester.tap(find.text('Furniture'));
      await tester.pumpAndSettle();
      expect(find.text('Furniture category'), findsOneWidget);
      expect(find.text('Owned 1 · In room 1'), findsWidgets);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
