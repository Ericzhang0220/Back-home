import 'package:cloud_firestore/cloud_firestore.dart';

/// The signed-in person's human friends list — the Human tab's counterpart to
/// the `isFriend` flag on AI character documents, kept in its own collection so
/// the two lists stay completely separate.
///
/// Saving someone is immediate on your own side and also drops a request in
/// their inbox. Accepting it saves you back, which is what makes a pair
/// mutual; rejecting simply clears the request and leaves their list alone.
class HumanFriendsRepository {
  HumanFriendsRepository({required this.uid, FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final String uid;
  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _friendsRefFor(String owner) =>
      _firestore.collection('users').doc(owner).collection('humanFriends');

  /// Pending requests waiting on [owner]'s answer, keyed by requester uid.
  CollectionReference<Map<String, dynamic>> _requestsRefFor(String owner) =>
      _firestore.collection('users').doc(owner).collection('friendRequests');

  /// A permanent record of everyone who has ever earned this account a like,
  /// one document per person. Keyed by uid, so re-adding somebody cannot earn
  /// a second one, and never deleted, so unfriending cannot take one back —
  /// likes are only ever spent in the room shop.
  CollectionReference<Map<String, dynamic>> get _likeAwardsRef =>
      _firestore.collection('users').doc(uid).collection('friendLikeAwards');

  CollectionReference<Map<String, dynamic>> get _friendsRef =>
      _friendsRefFor(uid);

  /// The uids of everyone in the list. Errors surface as an empty set so a
  /// rules hiccup degrades to "no friends yet" rather than a broken tab.
  Stream<Set<String>> watchFriendUids() {
    return _friendsRef
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => doc.id).toSet())
        .handleError((Object _) {});
  }

  /// Live friend state for one person, for screens already scoped to them.
  Stream<bool> watchIsFriend(String peerUid) {
    return _friendsRef.doc(peerUid).snapshots().map((doc) => doc.exists);
  }

  /// Saves someone and asks them back, in one atomic write so a list entry
  /// never exists without its matching request.
  Future<void> addFriend(String peerUid) {
    final batch = _firestore.batch();
    batch.set(_friendsRef.doc(peerUid), {
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.set(_requestsRefFor(peerUid).doc(uid), {
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.set(_likeAwardsRef.doc(peerUid), {
      'createdAt': FieldValue.serverTimestamp(),
    });
    return batch.commit();
  }

  /// Removes the like and withdraws the request if they have not answered yet.
  /// The conversation in `chats/` is left alone, so the thread is still there
  /// if they are added back.
  Future<void> removeFriend(String peerUid) {
    final batch = _firestore.batch();
    batch.delete(_friendsRef.doc(peerUid));
    batch.delete(_requestsRefFor(peerUid).doc(uid));
    return batch.commit();
  }

  /// Uids of the people waiting on an answer from this account.
  Stream<List<String>> watchIncomingRequestUids() {
    return _requestsRefFor(uid)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => doc.id).toList())
        .handleError((Object _) {});
  }

  /// Saves the requester back — the step that makes the pair mutual — and
  /// clears the request.
  Future<void> acceptRequest(String requesterUid) {
    final batch = _firestore.batch();
    batch.set(_friendsRef.doc(requesterUid), {
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.set(_likeAwardsRef.doc(requesterUid), {
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.delete(_requestsRefFor(uid).doc(requesterUid));
    return batch.commit();
  }

  /// Clears the request without saving them. Their own list is untouched — it
  /// is theirs, and this account was never on it.
  Future<void> rejectRequest(String requesterUid) {
    return _requestsRefFor(uid).doc(requesterUid).delete();
  }
}
