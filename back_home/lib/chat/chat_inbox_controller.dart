import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'ai_models.dart';

class InboxThread {
  const InboxThread({
    required this.id,
    required this.peerId,
    required this.isAi,
    this.readThrough,
  });

  final String id;
  final String peerId;
  final bool isAi;
  final DateTime? readThrough;
  String get key => '${isAi ? 'ai' : 'human'}:$id';
}

abstract class ChatInboxSource {
  Stream<List<InboxThread>> watchAiThreads();
  Stream<List<InboxThread>> watchHumanThreads();
  Stream<int> watchUnreadCount(InboxThread thread);
  Future<void> markRead(String key, DateTime through);
}

/// Counts incoming messages after each conversation's last displayed reply.
/// Read cursors live on existing chat documents, so they survive app restarts
/// and sync across devices without counting the user's own outgoing messages.
class ChatInboxController extends ChangeNotifier {
  ChatInboxController({
    required String uid,
    FirebaseFirestore? firestore,
    ChatInboxSource? source,
  }) : _source =
           source ?? FirestoreChatInboxSource(uid: uid, firestore: firestore) {
    _parentSubscriptions.add(
      _source.watchAiThreads().listen(
        (threads) => _syncThreads(true, threads),
        onError: _handleError,
      ),
    );
    _parentSubscriptions.add(
      _source.watchHumanThreads().listen(
        (threads) => _syncThreads(false, threads),
        onError: _handleError,
      ),
    );
  }

  final ChatInboxSource _source;
  final _parentSubscriptions = <StreamSubscription<List<InboxThread>>>[];
  final _messageSubscriptions = <String, StreamSubscription<int>>{};
  final _threads = <String, InboxThread>{};
  final _counts = <String, int>{};
  final _acknowledged = <String, DateTime>{};
  bool _disposed = false;
  Object? lastError;

  Map<String, int> get aiCounts => _countsFor(true);
  Map<String, int> get humanCounts => _countsFor(false);
  int get aiTotal => aiCounts.values.fold(0, (total, value) => total + value);
  int get humanTotal =>
      humanCounts.values.fold(0, (total, value) => total + value);

  Map<String, int> _countsFor(bool isAi) => {
    for (final thread in _threads.values)
      if (thread.isAi == isAi) thread.peerId: _counts[thread.key] ?? 0,
  };

  void _handleError(Object error) {
    if (!_disposed) lastError = error;
  }

  void _syncThreads(bool isAi, List<InboxThread> threads) {
    if (_disposed) return;
    final keys = threads.map((thread) => thread.key).toSet();
    for (final old in _threads.values.toList()) {
      if (old.isAi == isAi && !keys.contains(old.key)) {
        _messageSubscriptions.remove(old.key)?.cancel();
        _threads.remove(old.key);
        _counts.remove(old.key);
        _acknowledged.remove(old.key);
      }
    }
    for (final thread in threads) {
      final old = _threads[thread.key];
      if (old != null && old.readThrough == thread.readThrough) continue;
      _threads[thread.key] = thread;
      _messageSubscriptions.remove(thread.key)?.cancel();
      _messageSubscriptions[thread.key] = _source
          .watchUnreadCount(thread)
          .listen((value) {
            // Ignore late results from a query superseded by a read receipt.
            if (_disposed || !identical(_threads[thread.key], thread)) return;
            if (_counts[thread.key] != value) {
              _counts[thread.key] = value;
              notifyListeners();
            }
          }, onError: _handleError);
    }
    notifyListeners();
  }

  Future<void> markRead(String key, DateTime through) async {
    if (_disposed) return;
    final local = _acknowledged[key];
    final remote = _threads[key]?.readThrough;
    final known = local == null || (remote != null && remote.isAfter(local))
        ? remote
        : local;
    if (known != null && !through.isAfter(known)) return;
    _acknowledged[key] = through;
    try {
      await _source.markRead(key, through);
    } catch (_) {
      if (_acknowledged[key] == through) _acknowledged.remove(key);
      rethrow;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    for (final subscription in _parentSubscriptions) {
      subscription.cancel();
    }
    for (final subscription in _messageSubscriptions.values) {
      subscription.cancel();
    }
    super.dispose();
  }
}

class FirestoreChatInboxSource implements ChatInboxSource {
  FirestoreChatInboxSource({required this.uid, FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final String uid;
  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _aiChats =>
      _firestore.collection('users').doc(uid).collection('aiChats');

  @override
  Stream<List<InboxThread>> watchAiThreads() => _aiChats.snapshots().map(
    (snapshot) => [
      for (final doc in snapshot.docs)
        if (!AiChatPreview.fromData(doc.data()).isHidden)
          InboxThread(
            id: doc.id,
            peerId: doc.id,
            isAi: true,
            readThrough: (doc.data()['readThrough'] as Timestamp?)?.toDate(),
          ),
    ],
  );

  @override
  Stream<List<InboxThread>> watchHumanThreads() => _firestore
      .collection('chats')
      .where('participantUids', arrayContains: uid)
      .snapshots()
      .map(
        (snapshot) => [
          for (final doc in snapshot.docs)
            if ((doc.data()['participantUids'] as List)
                .where((id) => id != uid)
                .isNotEmpty)
              InboxThread(
                id: doc.id,
                isAi: false,
                peerId:
                    (doc.data()['participantUids'] as List).firstWhere(
                          (id) => id != uid,
                        )
                        as String,
                readThrough:
                    ((doc.data()['readThrough'] as Map?)?[uid] as Timestamp?)
                        ?.toDate(),
              ),
        ],
      );

  @override
  Stream<int> watchUnreadCount(InboxThread thread) {
    final parent = thread.isAi
        ? _aiChats.doc(thread.id)
        : _firestore.collection('chats').doc(thread.id);
    Query<Map<String, dynamic>> query = parent.collection('messages');
    if (thread.readThrough != null) {
      query = query.where(
        'createdAt',
        isGreaterThan: Timestamp.fromDate(thread.readThrough!),
      );
    }
    // A single timestamp filter uses Firestore's built-in field index.
    return query.snapshots().map(
      (snapshot) => snapshot.docs
          .where(
            (doc) => isUnreadIncomingMessage(
              doc.data(),
              uid: uid,
              isAi: thread.isAi,
              readThrough: thread.readThrough,
            ),
          )
          .length,
    );
  }

  @override
  Future<void> markRead(String key, DateTime through) {
    final isAi = key.startsWith('ai:');
    final id = key.substring(isAi ? 3 : 6);
    final ref = isAi
        ? _aiChats.doc(id)
        : _firestore.collection('chats').doc(id);
    return _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      if (!snapshot.exists) return;
      final data = snapshot.data()!;
      final previous = isAi
          ? data['readThrough'] as Timestamp?
          : (data['readThrough'] as Map?)?[uid] as Timestamp?;
      final timestamp = Timestamp.fromDate(through);
      if (previous != null && timestamp.compareTo(previous) <= 0) return;
      // Update only the caller's cursor; do not touch lastMessage, activity,
      // participantUids or senderUids, or another participant's read receipt.
      transaction.update(ref, {
        FieldPath(isAi ? ['readThrough'] : ['readThrough', uid]): timestamp,
      });
    });
  }
}

bool isUnreadIncomingMessage(
  Map<String, dynamic> data, {
  required String uid,
  required bool isAi,
  DateTime? readThrough,
}) {
  final timestamp = data['createdAt'];
  if (timestamp is! Timestamp) return false;
  if (data['text'] is! String || (data['text'] as String).trim().isEmpty) {
    return false;
  }
  final incoming = isAi
      ? data['role'] == 'assistant'
      : data['senderUid'] is String &&
            (data['senderUid'] as String).isNotEmpty &&
            data['senderUid'] != uid;
  return incoming &&
      (readThrough == null || timestamp.toDate().isAfter(readThrough));
}
