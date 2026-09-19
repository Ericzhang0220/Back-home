import 'package:cloud_firestore/cloud_firestore.dart';

/// What a notification is about. Friend requests are not here — they live in
/// their own collection because they carry an accept/reject lifecycle, and the
/// notifications screen merges the two.
enum AppNotificationType {
  /// Someone liked a post or comment of yours.
  like,

  /// New comments arrived on a post of yours, counted per post.
  comment,

  /// A conduct warning. Written server-side only.
  warning,

  /// A general announcement. Written server-side only.
  system,

  /// A Hall poster that did not pass moderation. Written server-side only.
  postRejected;

  static AppNotificationType? fromName(Object? raw) {
    for (final value in AppNotificationType.values) {
      if (value.name == raw) {
        return value;
      }
    }
    return null;
  }
}

class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    this.createdAt,
    this.actorUid,
    this.actorName,
    this.postId,
    this.topic,
    this.count = 1,
    this.title,
    this.body,
    this.readAt,
  });

  final String id;
  final AppNotificationType type;
  final DateTime? createdAt;

  /// Who caused it, for likes and comments.
  final String? actorUid;
  final String? actorName;

  final String? postId;

  /// The post's topic, used for the "in [topic]" wording.
  final String? topic;

  /// How many comments have arrived on the post since this was last cleared.
  final int count;

  /// Server-authored copy, used by warnings, system updates, and moderation.
  final String? title;
  final String? body;
  final DateTime? readAt;

  bool get isRead => readAt != null;

  static AppNotification? fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final type = AppNotificationType.fromName(data['type']);
    if (type == null) {
      // An unknown type is a newer client's notification; skip it rather than
      // rendering an empty row.
      return null;
    }

    final rawCount = data['count'];
    return AppNotification(
      id: doc.id,
      type: type,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      actorUid: _readString(data['actorUid']),
      actorName: _readString(data['actorName']),
      postId: _readString(data['postId']),
      topic: _readString(data['topic']),
      count: rawCount is int && rawCount > 0 ? rawCount : 1,
      title: _readString(data['title']),
      body: _readString(data['body']),
      readAt: (data['readAt'] as Timestamp?)?.toDate(),
    );
  }

  static String? _readString(Object? value) {
    if (value is! String || value.trim().isEmpty) {
      return null;
    }
    return value.trim();
  }
}

/// Reads this account's notification inbox, and posts likes and comments into
/// other people's.
///
/// Warnings, system updates, and moderation results are deliberately not
/// writable from here: they are authored server-side, where the Admin SDK
/// bypasses the rules that stop a client from forging them.
class NotificationsRepository {
  NotificationsRepository({required this.uid, FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  /// The signed-in account. Owner of the inbox that is read, and the actor
  /// behind anything written into someone else's.
  final String uid;
  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _refFor(String owner) =>
      _firestore.collection('users').doc(owner).collection('notifications');

  Stream<List<AppNotification>> watchNotifications() {
    return _refFor(uid)
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(AppNotification.fromDoc)
              .whereType<AppNotification>()
              .toList(),
        )
        .handleError((Object _) {});
  }

  Stream<int> watchUnreadCount() {
    return _refFor(uid).snapshots().map(
      (snapshot) => snapshot.docs.where((doc) {
        final data = doc.data();
        return data['readAt'] == null &&
            AppNotificationType.fromName(data['type']) != null;
      }).length,
    );
  }

  Future<void> markRead(String notificationId) {
    return _refFor(
      uid,
    ).doc(notificationId).update({'readAt': FieldValue.serverTimestamp()});
  }

  Future<void> markAllRead() async {
    final snapshot = await _refFor(uid).get();
    final unread = snapshot.docs
        .where((doc) => doc.data()['readAt'] == null)
        .toList(growable: false);
    await _writeInChunks(unread, (batch, doc) {
      batch.update(doc.reference, {'readAt': FieldValue.serverTimestamp()});
    });
  }

  Future<void> deleteRead() async {
    final snapshot = await _refFor(uid).get();
    final read = snapshot.docs
        .where((doc) => doc.data()['readAt'] != null)
        .toList(growable: false);
    await _writeInChunks(read, (batch, doc) {
      batch.delete(doc.reference);
    });
  }

  /// Records a like. Keyed by post, optional comment, and liker, so liking
  /// twice never stacks up two rows.
  Future<void> notifyLiked({
    required String recipientUid,
    required String postId,
    String? commentId,
    String? topic,
    required String actorName,
  }) {
    if (recipientUid == uid) {
      // No point telling someone they liked their own post.
      return Future<void>.value();
    }
    return _refFor(recipientUid).doc(_likeId(postId, commentId)).set({
      'type': AppNotificationType.like.name,
      'actorUid': uid,
      'actorName': actorName,
      'postId': postId,
      'commentId': ?commentId,
      'topic': ?topic,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Takes the like notification back when a like is undone.
  Future<void> clearLike({
    required String recipientUid,
    required String postId,
    String? commentId,
  }) {
    if (recipientUid == uid) {
      return Future<void>.value();
    }
    return _refFor(recipientUid).doc(_likeId(postId, commentId)).delete();
  }

  /// Counts a new comment against its post, so the inbox can say "3 new
  /// comments in Room setup" instead of listing three near-identical rows.
  Future<void> notifyCommented({
    required String recipientUid,
    required String postId,
    String? topic,
    required String actorName,
  }) {
    if (recipientUid == uid) {
      return Future<void>.value();
    }
    return _refFor(recipientUid).doc('comment_$postId').set({
      'type': AppNotificationType.comment.name,
      'actorUid': uid,
      'actorName': actorName,
      'postId': postId,
      'topic': ?topic,
      'count': FieldValue.increment(1),
      'createdAt': FieldValue.serverTimestamp(),
      // A new reply makes an aggregated notification unread again.
      'readAt': FieldValue.delete(),
    }, SetOptions(merge: true));
  }

  Future<void> _writeInChunks(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    void Function(
      WriteBatch batch,
      QueryDocumentSnapshot<Map<String, dynamic>> doc,
    )
    write,
  ) async {
    const chunkSize = 400;
    for (var start = 0; start < docs.length; start += chunkSize) {
      final batch = _firestore.batch();
      final end = (start + chunkSize).clamp(0, docs.length);
      for (var index = start; index < end; index++) {
        write(batch, docs[index]);
      }
      await batch.commit();
    }
  }

  String _likeId(String postId, String? commentId) {
    return commentId == null
        ? 'like_${postId}_$uid'
        : 'like_${postId}_${commentId}_$uid';
  }
}
