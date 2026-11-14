import 'dart:async';
import 'dart:convert';

import 'package:back_home/keyboard/keyboard_catalog.dart';
import 'package:back_home/keyboard/keyboard_store.dart';
import 'package:back_home/rooms/room_state.dart';
import 'package:back_home/rooms/shop_wallet.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _CloudWallet implements ShopWallet {
  final balances = <String, int>{};
  final receipts = <String>{};
  final changes = StreamController<({String uid, int likes})>.broadcast();
  bool dropReply = false;
  bool offline = false;

  @override
  Future<int> initialize(String uid, int localBalance) async {
    if (offline) throw StateError('Offline');
    return balances.putIfAbsent(uid, () => localBalance);
  }

  @override
  Stream<int> watch(String uid) => changes.stream
      .where((event) => event.uid == uid)
      .map((event) => event.likes);

  void setBalance(String uid, int likes) {
    balances[uid] = likes;
    changes.add((uid: uid, likes: likes));
  }

  @override
  Future<ShopDebitResult> debit(String uid, String id, int cost) async {
    if (offline) throw StateError('Offline');
    final receipt = '$uid/$id';
    if (receipts.contains(receipt)) {
      return (likes: balances[uid]!, charged: true);
    }
    final balance = balances[uid]!;
    if (balance < cost) return (likes: balance, charged: false);
    receipts.add(receipt);
    setBalance(uid, balance - cost);
    if (dropReply) throw StateError('Reply lost after commit');
    return (likes: balance - cost, charged: true);
  }
}

void main() {
  late _CloudWallet cloud;
  late RoomEditorController room;
  late KeyboardStore store;
  const key = 'chet_keyboard_v1_vk3-test';

  setUp(() {
    SharedPreferences.setMockInitialValues({
      key: jsonEncode({'likes': 58}),
    });
    cloud = _CloudWallet();
    room = RoomEditorController();
    store = KeyboardStore(room, wallet: cloud);
  });
  tearDown(() async {
    store.dispose();
    room.dispose();
    await cloud.changes.close();
  });

  test('migrates the legacy balance once and follows admin edits', () async {
    await store.loadForAccount('vk3-test');
    expect(cloud.balances['vk3-test'], 58);
    expect(room.likesBalance, 58);
    final prefs = await SharedPreferences.getInstance();
    expect(jsonDecode(prefs.getString(key)!), isNot(contains('likes')));
    cloud.setBalance('vk3-test', 5000);
    await Future<void>.delayed(Duration.zero);
    expect(room.likesBalance, 5000);
    await store.loadForAccount('other');
    expect(room.likesBalance, 238);
    await store.loadForAccount('vk3-test');
    expect(room.likesBalance, 5000);
  });

  test('furniture and keyboards debit the same cloud balance', () async {
    cloud.balances['vk3-test'] = 5000;
    await store.loadForAccount('vk3-test');
    final item = room.catalog.first;
    final owned = room.ownedCount(item.id);
    final keyboard = keyboardSkins.first;
    expect((await store.purchaseFurniture(item)).isSuccess, isTrue);
    expect(await store.buyOrApply(keyboard, KeyboardUseScope.aiOnly), isNull);
    expect(room.ownedCount(item.id), owned + 1);
    expect(cloud.balances['vk3-test'], 5000 - item.price - keyboard.price);
    expect(room.likesBalance, cloud.balances['vk3-test']);
    final draft = RoomEditorController.editing(room);
    cloud.setBalance('vk3-test', 6000);
    await Future<void>.delayed(Duration.zero);
    room.applyEditSession(draft);
    draft.dispose();
    expect(room.likesBalance, 6000);
  });

  test(
    'lost confirmation is recovered after restart without another debit',
    () async {
      cloud.balances['vk3-test'] = 5000;
      await store.loadForAccount('vk3-test');
      final item = room.catalog.first;
      final owned = room.ownedCount(item.id);
      cloud.dropReply = true;
      expect((await store.purchaseFurniture(item)).isSuccess, isFalse);
      expect(room.ownedCount(item.id), owned);
      expect(store.walletReady, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('${key}_pending_debit'), isNotNull);
      store.dispose();
      room.dispose();
      room = RoomEditorController();
      store = KeyboardStore(room, wallet: cloud);
      cloud.dropReply = false;
      await store.loadForAccount('vk3-test');
      expect(cloud.receipts.length, 1);
      expect(room.likesBalance, 5000 - item.price);
      expect(room.ownedCount(item.id), owned + 1);
      expect(prefs.getString('${key}_pending_debit'), isNull);
    },
  );

  test(
    'offline wallet preserves migration balance and blocks purchases',
    () async {
      cloud.offline = true;
      await store.loadForAccount('vk3-test');
      expect(store.walletReady, isFalse);
      final item = room.catalog.first;
      expect((await store.purchaseFurniture(item)).isSuccess, isFalse);
      expect(cloud.receipts, isEmpty);
      cloud.offline = false;
      await store.refreshWallet();
      expect(room.likesBalance, 58);
    },
  );
}
