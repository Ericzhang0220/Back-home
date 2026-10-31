import 'package:back_home/keyboard/keyboard_catalog.dart';
import 'package:back_home/keyboard/keyboard_store.dart';
import 'package:back_home/rooms/room_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FailingPreferences extends Fake implements SharedPreferences {
  @override
  String? getString(String key) => null;
  @override
  Future<bool> setString(String key, String value) async => false;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('twenty unique abstract themes retain stable purchase IDs', () {
    expect(keyboardSkins, hasLength(20));
    expect(keyboardSkins.map((s) => s.id).toSet(), hasLength(20));
    expect(keyboardSkins.map((s) => s.name).toSet(), hasLength(20));
    expect(keyboardSkins.map((s) => s.base).toSet(), hasLength(20));
  });
  test(
    'purchase, wallet, scope and repeat ownership survive a reload',
    () async {
      final room = RoomEditorController();
      final store = KeyboardStore(room);
      await store.loadForAccount('a');
      final skin = keyboardSkins.first;
      expect(await store.buyOrApply(skin, KeyboardUseScope.aiOnly), isNull);
      expect(room.likesBalance, 238 - skin.price);
      expect(await store.buyOrApply(skin, KeyboardUseScope.allPages), isNull);
      expect(room.likesBalance, 238 - skin.price);
      final restoredRoom = RoomEditorController();
      final restored = KeyboardStore(restoredRoom);
      await restored.loadForAccount('a');
      expect(restored.owned, contains(skin.id));
      expect(restored.scope, KeyboardUseScope.allPages);
      expect(restored.activeId, skin.id);
      expect(restoredRoom.likesBalance, room.likesBalance);
      store.dispose();
      restored.dispose();
      room.dispose();
      restoredRoom.dispose();
    },
  );
  test(
    'insufficient Likes, unknown skins and accounts never grant ownership',
    () async {
      final room = RoomEditorController();
      final store = KeyboardStore(room);
      await store.loadForAccount('a');
      await store.buyOrApply(keyboardSkins.first, KeyboardUseScope.aiOnly);
      await store.loadForAccount('b');
      expect(store.owned, isNot(contains(keyboardSkins.first.id)));
      expect(room.likesBalance, 238);
      room.restoreLikesBalance(2);
      expect(
        await store.buyOrApply(keyboardSkins[1], KeyboardUseScope.allPages),
        isNotNull,
      );
      expect(store.owned, isNot(contains(keyboardSkins[1].id)));
      expect(room.likesBalance, 2);
      store.dispose();
      room.dispose();
    },
  );
  test(
    'a failed persistent save refunds Likes and rolls back selection',
    () async {
      final room = RoomEditorController();
      final store = KeyboardStore(
        room,
        preferences: () async => _FailingPreferences(),
      );
      await store.loadForAccount('a');
      expect(
        await store.buyOrApply(keyboardSkins.first, KeyboardUseScope.allPages),
        isNotNull,
      );
      expect(room.likesBalance, 238);
      expect(store.activeId, 'mia-anderson');
      expect(store.scope, KeyboardUseScope.aiOnly);
      expect(store.owned, isNot(contains(keyboardSkins.first.id)));
      store.dispose();
      room.dispose();
    },
  );
}
