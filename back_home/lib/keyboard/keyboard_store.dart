import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../rooms/room_state.dart';
import '../rooms/shop_wallet.dart';
import '../chat/ai_chat_repository.dart';
import '../chat/ai_models.dart';
import 'custom_keyboard.dart';
import 'keyboard_catalog.dart';

/// Stores device inventory and coordinates purchases against the account wallet.
class KeyboardStore extends ChangeNotifier {
  KeyboardStore(
    this.room, {
    Future<SharedPreferences> Function()? preferences,
    Stream<List<AiCharacter>> Function(String uid)? characters,
    ShopWallet? wallet,
  }) : _preferences = preferences ?? SharedPreferences.getInstance,
       _characters = characters,
       _wallet = wallet {
    room.addListener(_roomChanged);
  }

  final RoomEditorController room;
  final ShopWallet? _wallet;
  StreamSubscription<int>? _walletSubscription;
  int? _latestCloudBalance;
  int _walletRevision = 0;
  bool _walletReady = false;
  bool _refreshingWallet = false;
  String? walletError;
  bool get usesCloudWallet => _wallet != null && _account != 'signed-out';
  bool get walletReady => !usesCloudWallet || _walletReady;
  String get _pendingKey => '${_key}_pending_debit';
  final Future<SharedPreferences> Function() _preferences;
  final Stream<List<AiCharacter>> Function(String uid)? _characters;
  StreamSubscription<List<AiCharacter>>? _characterSubscription;
  List<AiCharacter> _ownCharacters = [];
  List<AiCharacter> get ownCharacters => List.unmodifiable(_ownCharacters);
  bool charactersReady = false;
  String? characterError;
  List<CustomKeyboardProject> _projects = [];
  List<CustomKeyboardProject> get projects => List.unmodifiable(_projects);
  CustomKeyboardProject? projectById(String id) {
    for (final project in _projects) {
      if (project.id == id) return project;
    }
    return null;
  }

  KeyboardSkin? _customSkin(String id) {
    for (final project in _projects) {
      if (project.selected?.skin.id == id) return project.selected!.skin;
    }
    return null;
  }

  SharedPreferences? _prefs;
  String _account = '';
  String get accountId => _account;
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
  List<KeyboardSkin> get ownedSkins => [
    ...keyboardSkins.where((skin) => _owned.contains(skin.id)),
    for (final project in _projects)
      if (project.selected != null && _owned.contains(project.selectedId))
        project.selected!.skin,
  ];
  String _lastFurniture = '';
  KeyboardSkin get activeSkin =>
      _customSkin(activeId) ?? keyboardSkinById(activeId);
  String get _key => 'chet_keyboard_v1_$_account';
  Future<void> _pendingSave = Future<void>.value();
  Completer<void>? _purchaseComplete;

  Future<void> loadForAccount(String uid) async {
    final generation = ++_generation;
    ready = false;
    _walletReady = false;
    walletError = null;
    _latestCloudBalance = null;
    _walletRevision = 0;
    unawaited(_walletSubscription?.cancel());
    _walletSubscription = null;
    charactersReady = false;
    characterError = null;
    _ownCharacters = [];
    unawaited(_characterSubscription?.cancel());
    _characterSubscription = null;
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
      _projects = [
        for (final item in (data['customProjects'] as List? ?? []))
          CustomKeyboardProject.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
      ];
      final valid = {
        ...keyboardSkins.map((s) => s.id),
        for (final project in _projects)
          if (project.selected != null) project.selected!.skin.id,
      };
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
      room.restoreInventory(data['furniture'] as Map<String, dynamic>?);
      _lastFurniture = jsonEncode(room.inventoryRecord);
      room.restoreLikesBalance(usesCloudWallet ? 0 : _legacyBalance(balance));
      _lastBalance = room.likesBalance;
      ready = true;
      final characterStream =
          _characters?.call(uid) ??
          (uid != 'signed-out' && Firebase.apps.isNotEmpty
              ? AiChatRepository(uid: uid).watchCharacters()
              : Stream<List<AiCharacter>>.value([]));
      _characterSubscription = characterStream.listen(
        (characters) {
          if (_disposed || generation != _generation) return;
          _ownCharacters = characters.where((c) => c.canEditBy(uid)).toList();
          charactersReady = true;
          characterError = null;
          notifyListeners();
        },
        onError: (Object error) {
          if (_disposed || generation != _generation) return;
          charactersReady = true;
          characterError =
              'Could not load your AI characters. Please try again.';
          notifyListeners();
        },
      );
    } catch (_) {
      if (_disposed || generation != _generation) return;
      // No purchases can be charged without a working persistent inventory.
      ready = false;
    }
    if (!_disposed && generation == _generation) notifyListeners();
    if (!_disposed && generation == _generation && ready && usesCloudWallet) {
      await refreshWallet();
    }
  }

  int _legacyBalance(Object? value) =>
      value is int && value >= 0 && value <= 9007199254740991 ? value : 238;

  Future<void> refreshWallet() async {
    if (!ready || !usesCloudWallet || busy || _refreshingWallet) return;
    _walletReady = false;
    final generation = _generation;
    final account = _account;
    final prefs = _prefs!;
    final wallet = _wallet!;
    final key = _key;
    final pendingKey = _pendingKey;
    bool isCurrent() => !_disposed && generation == _generation;
    _refreshingWallet = true;
    walletError = null;
    notifyListeners();
    try {
      final raw = prefs.getString(key);
      final local = raw == null
          ? <String, dynamic>{}
          : jsonDecode(raw) as Map<String, dynamic>;
      final revision = _walletRevision;
      var balance = await wallet.initialize(
        account,
        _legacyBalance(local['likes']),
      );
      if (!isCurrent()) return;
      final pendingRaw = prefs.getString(pendingKey);
      if (pendingRaw != null) {
        final pending = jsonDecode(pendingRaw) as Map<String, dynamic>;
        final result = await wallet.debit(
          account,
          pending['id'] as String,
          pending['cost'] as int,
        );
        if (!isCurrent()) return;
        balance = result.likes;
        if (result.charged) {
          final record = pending['record'] as Map<String, dynamic>;
          await _writeRecord(prefs, key, record);
          if (!isCurrent()) return;
          _restorePurchaseRecord(record);
        }
        await _removePending(prefs, pendingKey);
        if (!isCurrent()) return;
      } else if (local.containsKey('likes')) {
        local.remove('likes');
        await _writeRecord(prefs, key, local);
        if (!isCurrent()) return;
      }
      _walletReady = true;
      _applyCloudBalance(
        _walletRevision == revision
            ? balance
            : (_latestCloudBalance ?? balance),
      );
      _walletSubscription ??= wallet
          .watch(account)
          .listen(
            (balance) {
              if (!isCurrent()) return;
              _walletRevision++;
              _latestCloudBalance = balance;
              if (!busy && _walletReady) _applyCloudBalance(balance);
            },
            onError: (Object _) {
              if (!isCurrent()) return;
              _walletSubscription = null;
              walletError = 'Could not sync your Likes balance. Tap Retry.';
              _walletReady = false;
              notifyListeners();
            },
            cancelOnError: true,
          );
    } catch (_) {
      if (!isCurrent()) return;
      _walletReady = false;
      walletError = 'Could not load your Likes balance. Tap Retry.';
    } finally {
      _refreshingWallet = false;
      if (isCurrent()) {
        notifyListeners();
      } else if (!_disposed && ready && usesCloudWallet) {
        unawaited(refreshWallet());
      }
    }
  }

  void _applyCloudBalance(int value) {
    _lastBalance = value;
    room.restoreLikesBalance(value);
  }

  void _restorePurchaseRecord(Map<String, dynamic> record) {
    _projects = [
      for (final item in record['customProjects'] as List)
        CustomKeyboardProject.fromJson(Map<String, dynamic>.from(item as Map)),
    ];
    _owned = Set<String>.from(record['owned'] as List);
    activeId = record['active'] as String;
    scope = KeyboardUseScope.values.byName(record['scope'] as String);
    enabled = record['enabled'] as bool;
    final furniture = record['furniture'] as Map<String, dynamic>;
    _lastFurniture = jsonEncode(furniture);
    room.restoreInventory(furniture);
  }

  Future<void> _writeRecord(
    SharedPreferences prefs,
    String key,
    Map<String, dynamic> record,
  ) async {
    if (!await prefs.setString(key, jsonEncode(record))) {
      throw StateError('Could not save shop data.');
    }
  }

  Future<void> _removePending(SharedPreferences prefs, String key) async {
    if (!await prefs.remove(key)) {
      throw StateError('Could not clear saved debit.');
    }
  }

  Future<String?> _commitCloudDebit(int cost) async {
    final prefs = _prefs!;
    final pendingKey = _pendingKey;
    final key = _key;
    final record = _record();
    final random = Random.secure();
    final id = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    var recorded = false;
    try {
      // Save the intended inventory before authorizing the cloud debit.
      // Retrying the same receipt after an interruption cannot charge twice.
      await _pendingSave;
      await _writeRecord(prefs, pendingKey, {
        'id': id,
        'cost': cost,
        'record': record,
      });
      recorded = true;
      final revision = _walletRevision;
      final result = await _wallet!.debit(_account, id, cost);
      if (_walletRevision == revision) _latestCloudBalance = result.likes;
      if (result.charged) await _writeRecord(prefs, key, record);
      await _removePending(prefs, pendingKey);
      return result.charged ? null : 'Not enough Likes for this purchase.';
    } catch (_) {
      if (recorded) {
        _walletReady = false;
        walletError = 'A purchase needs to finish syncing. Tap Retry.';
      }
      rethrow;
    }
  }

  Map<String, dynamic> _record() => {
    'customProjects': _projects.map((project) => project.toJson()).toList(),
    'owned': _owned.toList()..sort(),
    'active': activeId,
    'scope': scope.name,
    'enabled': enabled,
    if (!usesCloudWallet) 'likes': room.likesBalance,
    'furniture': room.inventoryRecord,
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
    if (!ready || busy || (usesCloudWallet && !_walletReady)) return;
    final furniture = jsonEncode(room.inventoryRecord);
    if (_lastBalance == room.likesBalance && _lastFurniture == furniture) {
      return;
    }
    _lastFurniture = furniture;
    _lastBalance = room.likesBalance;
    unawaited(_save().catchError((Object _) {}));
  }

  Future<String?> buyOrApply(
    KeyboardSkin skin,
    KeyboardUseScope? useScope,
  ) async {
    if (!keyboardSkins.any((item) => identical(item, skin)) &&
        !identical(_customSkin(skin.id), skin)) {
      return 'Unknown keyboard.';
    }
    final cost = _owned.contains(skin.id) ? 0 : skin.price;
    return _customMutation(() {
      _owned.add(skin.id);
      if (useScope != null) {
        activeId = skin.id;
        scope = useScope;
        enabled = true;
      }
    }, cost: cost);
  }

  Future<RoomActionResult> purchaseFurniture(RoomItemDefinition item) async {
    final error = await _customMutation(() {
      room.addPurchasedItem(item.id);
    }, cost: item.price);
    return error == null
        ? RoomActionResult.success('${item.title} added to your inventory.')
        : RoomActionResult.failure(error);
  }

  /// Commits a purchase and restores the previous inventory on failure.
  Future<String?> _customMutation(
    void Function() change, {
    int cost = 0,
  }) async {
    if (!ready || busy) return 'The shop is still loading. Please try again.';
    if (usesCloudWallet && !_walletReady) {
      return walletError ?? 'Likes are still syncing. Please try again.';
    }
    if (room.likesBalance < cost) return 'Not enough Likes for this purchase.';
    final oldRecord = _record();
    final oldBalance = room.likesBalance;
    _purchaseComplete = Completer<void>();
    busy = true;
    room.shopPurchaseLocked = true;
    var error = false;
    try {
      change();
      if (cost > 0 && !usesCloudWallet) {
        room.restoreLikesBalance(oldBalance - cost);
      }
      notifyListeners();
      if (cost > 0 && usesCloudWallet) {
        final message = await _commitCloudDebit(cost);
        if (message != null) {
          error = true;
          return message;
        }
      } else {
        await _save();
      }
      return null;
    } catch (_) {
      error = true;
      return walletError ?? 'Could not save this change. Please try again.';
    } finally {
      if (!_disposed) {
        if (error) {
          _restorePurchaseRecord(oldRecord);
          room.restoreLikesBalance(oldBalance);
        }
        final balance = _latestCloudBalance;
        if (usesCloudWallet && _walletReady && balance != null) {
          _applyCloudBalance(balance);
        }
        _lastBalance = room.likesBalance;
        _lastFurniture = jsonEncode(room.inventoryRecord);
      }
      busy = false;
      room.shopPurchaseLocked = false;
      _purchaseComplete?.complete();
      _purchaseComplete = null;
      if (!_disposed) notifyListeners();
    }
  }

  Future<String?> purchaseCustomKeyboard(String characterId) async {
    if (!ready || busy) return 'The shop is still loading. Please try again.';
    final matches = _ownCharacters.where((c) => c.id == characterId);
    if (matches.isEmpty) return 'Choose an AI character you created first.';
    if (room.likesBalance < customKeyboardPrice) {
      return 'Not enough Likes for a custom keyboard.';
    }
    final character = matches.first;
    return _customMutation(() {
      var id = 'custom-${DateTime.now().microsecondsSinceEpoch}';
      while (_projects.any((project) => project.id == id)) {
        id = '$id-new';
      }
      _projects.add(CustomKeyboardProject.forCharacter(id, character));
    }, cost: customKeyboardPrice);
  }

  Future<String?> generateKeyboard(String projectId, String style) async {
    if (!ready || busy) return 'The shop is still loading. Please try again.';
    final project = projectById(projectId);
    if (project == null) return 'Keyboard purchase not found.';
    if (project.selectedId != null) {
      return 'This keyboard has already been saved.';
    }
    if (project.remaining <= 0) {
      return 'All three generations are ready. Choose a keyboard to save.';
    }
    if (style.trim().isEmpty) return 'Describe the style you want first.';
    if (style.trim().length > 500) {
      return 'Keep your style description under 500 characters.';
    }
    return _customMutation(() {
      final result = generateCustomKeyboard(project, style);
      _projects[_projects.indexOf(project)] = project.withResult(result);
    });
  }

  Future<String?> saveCustomKeyboard(
    String projectId,
    String resultId,
    KeyboardUseScope? useScope,
  ) async {
    if (!ready || busy) return 'The shop is still loading. Please try again.';
    final project = projectById(projectId);
    if (project == null || !project.results.any((r) => r.skin.id == resultId)) {
      return 'Choose one of your generated keyboards first.';
    }
    if (project.selectedId != null) {
      return 'This keyboard has already been saved.';
    }
    return _customMutation(() {
      _projects[_projects.indexOf(project)] = project.select(resultId);
      _owned.add(resultId);
      if (useScope != null) {
        activeId = resultId;
        scope = useScope;
        enabled = true;
      }
    });
  }

  Future<void> useSystemKeyboard() async {
    if (!ready || busy || !walletReady) return;
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
    unawaited(_walletSubscription?.cancel());
    unawaited(_characterSubscription?.cancel());
    ++_generation;
    room.removeListener(_roomChanged);
    super.dispose();
  }
}
