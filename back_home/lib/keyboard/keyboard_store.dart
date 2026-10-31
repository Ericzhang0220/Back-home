import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../rooms/room_state.dart';
import '../chat/ai_chat_repository.dart';
import '../chat/ai_models.dart';
import 'custom_keyboard.dart';
import 'keyboard_catalog.dart';

/// Local Likes purchases, sharing the room's existing wallet. One saved record
/// contains the keyboard inventory, application scope, and the wallet balance.
class KeyboardStore extends ChangeNotifier {
  KeyboardStore(
    this.room, {
    Future<SharedPreferences> Function()? preferences,
    Stream<List<AiCharacter>> Function(String uid)? characters,
  }) : _preferences = preferences ?? SharedPreferences.getInstance,
       _characters = characters {
    room.addListener(_roomChanged);
  }

  final RoomEditorController room;
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
  KeyboardSkin get activeSkin =>
      _customSkin(activeId) ?? keyboardSkinById(activeId);
  String get _key => 'chet_keyboard_v1_$_account';
  Future<void> _pendingSave = Future<void>.value();
  Completer<void>? _purchaseComplete;

  Future<void> loadForAccount(String uid) async {
    final generation = ++_generation;
    ready = false;
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
      room.restoreLikesBalance(balance is int && balance >= 0 ? balance : 238);
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
  }

  Map<String, dynamic> _record() => {
    'customProjects': _projects.map((project) => project.toJson()).toList(),
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
    if (!keyboardSkins.any((item) => identical(item, skin)) &&
        !identical(_customSkin(skin.id), skin)) {
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

  /// Buying, consuming an attempt, and saving selection each commit atomically
  /// with the local wallet. Failed writes restore the entire previous state.
  Future<String?> _customMutation(void Function() change) async {
    if (!ready || busy) return 'The shop is still loading. Please try again.';
    final oldProjects = List<CustomKeyboardProject>.of(_projects);
    final oldOwned = Set<String>.of(_owned);
    final oldActive = activeId;
    final oldScope = scope;
    final oldEnabled = enabled;
    final oldBalance = room.likesBalance;
    _purchaseComplete = Completer<void>();
    busy = true;
    room.shopPurchaseLocked = true;
    try {
      change();
      notifyListeners();
      await _save();
      return null;
    } catch (_) {
      _projects = oldProjects;
      _owned = oldOwned;
      activeId = oldActive;
      scope = oldScope;
      enabled = oldEnabled;
      if (!_disposed) room.restoreLikesBalance(oldBalance);
      return 'Could not save this change. Your balance and generation allowance were restored. Please try again.';
    } finally {
      busy = false;
      room.shopPurchaseLocked = false;
      _lastBalance = room.likesBalance;
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
      room.restoreLikesBalance(room.likesBalance - customKeyboardPrice);
    });
  }

  Future<String?> generateKeyboard(String projectId, String style) async {
    if (!ready || busy) return 'The shop is still loading. Please try again.';
    final project = projectById(projectId);
    if (project == null) return 'Keyboard purchase not found.';
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
    KeyboardUseScope useScope,
  ) async {
    if (!ready || busy) return 'The shop is still loading. Please try again.';
    final project = projectById(projectId);
    if (project == null || !project.results.any((r) => r.skin.id == resultId)) {
      return 'Choose one of your generated keyboards first.';
    }
    return _customMutation(() {
      if (project.selectedId != null) _owned.remove(project.selectedId);
      _projects[_projects.indexOf(project)] = project.select(resultId);
      _owned.add(resultId);
      activeId = resultId;
      scope = useScope;
      enabled = true;
    });
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
    unawaited(_characterSubscription?.cancel());
    ++_generation;
    room.removeListener(_roomChanged);
    super.dispose();
  }
}
