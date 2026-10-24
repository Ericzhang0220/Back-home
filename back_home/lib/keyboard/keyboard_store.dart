import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../rooms/room_state.dart';
import 'keyboard_catalog.dart';

/// Local Likes purchases, sharing the room's existing wallet. One saved record
/// contains the keyboard inventory, application scope, and the wallet balance.
class KeyboardStore extends ChangeNotifier {
  KeyboardStore(this.room, {Future<SharedPreferences> Function()? preferences})
    : _preferences = preferences ?? SharedPreferences.getInstance {
    room.addListener(_roomChanged);
  }

  final RoomEditorController room;
  final Future<SharedPreferences> Function() _preferences;
  SharedPreferences? _prefs;
  String _account = '';
  int _generation = 0;
  int _lastBalance = 238;
  bool _disposed = false;
  bool ready = false;
  bool busy = false;
  bool enabled = true;
  String activeId = 'mia-anderson';
  KeyboardUseScope scope = KeyboardUseScope.aiOnly;
  Set<String> _owned = {'mia-anderson'};
  Set<String> get owned => Set.unmodifiable(_owned);
  KeyboardSkin get activeSkin => keyboardSkinById(activeId);
  String get _key => 'chet_keyboard_v1_$_account';
  Future<void> _pendingSave = Future<void>.value();
  Completer<void>? _purchaseComplete;

  Future<void> loadForAccount(String uid) async {
    final generation = ++_generation;
    ready = false;
    notifyListeners();
    await _purchaseComplete?.future;
    await _pendingSave;
    try {
      final prefs = await _preferences();
      if (_disposed || generation != _generation) return;
      _account = uid;
      _prefs = prefs;
      final raw = prefs.getString(_key);
      final data = raw == null
          ? <String, dynamic>{}
          : jsonDecode(raw) as Map<String, dynamic>;
      final valid = keyboardSkins.map((s) => s.id).toSet();
      _owned = {
        'mia-anderson',
        ...((data['owned'] as List?)?.whereType<String>() ?? []).where(
          valid.contains,
        ),
      };
      activeId = _owned.contains(data['active'])
          ? data['active'] as String
          : 'mia-anderson';
      scope = data['scope'] == 'allPages'
          ? KeyboardUseScope.allPages
          : KeyboardUseScope.aiOnly;
      enabled = data['enabled'] != false;
      final balance = data['likes'];
      room.restoreLikesBalance(balance is int && balance >= 0 ? balance : 238);
      _lastBalance = room.likesBalance;
      ready = true;
    } catch (_) {
      if (_disposed || generation != _generation) return;
      // No purchases can be charged without a working persistent inventory.
      ready = false;
    }
    if (!_disposed && generation == _generation) notifyListeners();
  }

  Map<String, dynamic> _record() => {
    'owned': _owned.toList()..sort(),
    'active': activeId,
    'scope': scope.name,
    'enabled': enabled,
    'likes': room.likesBalance,
  };

  Future<void> _save() {
    final key = _key;
    final encoded = jsonEncode(_record());
    final prefs = _prefs;
    final save = _pendingSave.then((_) async {
      if (prefs == null || !await prefs.setString(key, encoded)) {
        throw StateError('Could not save keyboard purchase.');
      }
    });
    // Keep the queue usable after a storage error; callers still receive it.
    _pendingSave = save.catchError((Object _) {});
    return save;
  }

  void _roomChanged() {
    if (!ready || busy || _lastBalance == room.likesBalance) return;
    _lastBalance = room.likesBalance;
    unawaited(_save().catchError((Object _) {}));
  }

  Future<String?> buyOrApply(
    KeyboardSkin skin,
    KeyboardUseScope useScope,
  ) async {
    if (!keyboardSkins.any((item) => identical(item, skin))) {
      return 'Unknown keyboard.';
    }
    if (!ready || busy) return 'The shop is still loading. Please try again.';
    final cost = _owned.contains(skin.id) ? 0 : skin.price;
    if (room.likesBalance < cost) return 'Not enough Likes for this keyboard.';
    final oldOwned = Set<String>.of(_owned);
    final oldActive = activeId;
    final oldScope = scope;
    final oldEnabled = enabled;
    _purchaseComplete = Completer<void>();
    busy = true;
    room.shopPurchaseLocked = true;
    _owned.add(skin.id);
    activeId = skin.id;
    scope = useScope;
    enabled = true;
    room.restoreLikesBalance(room.likesBalance - cost);
    notifyListeners();
    try {
      await _save();
      return null;
    } catch (_) {
      _owned = oldOwned;
      activeId = oldActive;
      scope = oldScope;
      enabled = oldEnabled;
      if (!_disposed) room.restoreLikesBalance(room.likesBalance + cost);
      return 'Could not save. Your Likes were returned. Please try again.';
    } finally {
      busy = false;
      room.shopPurchaseLocked = false;
      _lastBalance = room.likesBalance;
      _purchaseComplete?.complete();
      _purchaseComplete = null;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> useSystemKeyboard() async {
    if (!ready || busy) return;
    _purchaseComplete = Completer<void>();
    busy = true;
    final previous = enabled;
    enabled = false;
    notifyListeners();
    try {
      await _save();
    } catch (_) {
      enabled = previous;
      if (!_disposed) notifyListeners();
      rethrow;
    } finally {
      busy = false;
      _purchaseComplete?.complete();
      _purchaseComplete = null;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    room.removeListener(_roomChanged);
    super.dispose();
  }
}
