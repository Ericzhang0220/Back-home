import 'package:cloud_firestore/cloud_firestore.dart';

/// The signed-in person's human friends list — the Human tab's counterpart to
/// the `isFriend` flag on AI character documents, kept in its own collection so
/// the two lists stay completely separate.
///
/// Liking is one-way, exactly like the AI side: adding someone here never
/// touches their list, and never notifies them.
class HumanFriendsRepository {
  HumanFriendsRepository({required this.uid, FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final String uid;
  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _friendsRef =>
      _firestore.collection('users').doc(uid).collection('humanFriends');

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

  Future<void> addFriend(String peerUid) {
    return _friendsRef.doc(peerUid).set({
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Removes the like. The conversation in `chats/` is left alone, so the
  /// thread is still there if they are added back.
  Future<void> removeFriend(String peerUid) {
    return _friendsRef.doc(peerUid).delete();
  }
}
