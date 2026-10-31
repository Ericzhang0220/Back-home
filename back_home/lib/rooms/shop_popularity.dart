import 'dart:convert';
import 'dart:math';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Real recorded purchases only; starter inventory is never a sale. Failed
/// uploads stay in an account-scoped outbox and replay with the same event ID.
class ShopPopularity {
  static Future<void> _serial = Future.value();

  String? get _uid =>
      Firebase.apps.isEmpty ? null : FirebaseAuth.instance.currentUser?.uid;
  String _key(String uid) => 'furniture-sales-outbox-v1-$uid';

  Future<Map<String, int>?> load() async {
    final uid = _uid;
    if (uid == null) return null;
    try {
      await _serialized(() => _flush(uid));
      final result = await FirebaseFunctions.instance
          .httpsCallable('furniturePopularity')
          .call();
      if (_uid != uid) return null;
      final data = Map<String, dynamic>.from(result.data as Map);
      return {
        for (final entry in data.entries)
          if (entry.value is num) entry.key: (entry.value as num).toInt(),
      };
    } catch (_) {
      return null;
    }
  }

  Future<void> recordPurchase(String id) {
    final uid = _uid;
    if (uid == null) return Future.value();
    return _serialized(() async {
      final prefs = await SharedPreferences.getInstance();
      final queue = prefs.getStringList(_key(uid)) ?? [];
      final nonce = List.generate(16, (_) => Random.secure().nextInt(256));
      final event = base64UrlEncode(nonce).replaceAll('=', '');
      queue.add(jsonEncode({'itemId': id, 'eventId': event}));
      if (!await prefs.setStringList(_key(uid), queue)) return;
      try {
        await _flush(uid);
      } catch (_) {
        /* Retry on next shop open. */
      }
    });
  }

  static Future<void> _serialized(Future<void> Function() action) {
    final next = _serial.then((_) => action());
    _serial = next.catchError((Object _) {});
    return next;
  }

  Future<void> _flush(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    final queue = prefs.getStringList(_key(uid)) ?? [];
    while (queue.isNotEmpty && _uid == uid) {
      final event = jsonDecode(queue.first) as Map<String, dynamic>;
      await FirebaseFunctions.instance
          .httpsCallable('recordFurniturePurchase')
          .call(event);
      queue.removeAt(0);
      await prefs.setStringList(_key(uid), queue);
    }
  }
}
