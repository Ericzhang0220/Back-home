import 'package:cloud_firestore/cloud_firestore.dart';

/// Live profile counters derived from the data the app already stores, so the
/// profile stat pills reflect real activity instead of placeholder numbers.
class ProfileStats {
  ProfileStats(this.uid);

  final String uid;

  /// Total likes across every hall post this user has authored.
  Stream<int> likesReceived() {
    return FirebaseFirestore.instance
        .collection('posts')
        .where('authorUid', isEqualTo: uid)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs.fold<int>(
            0,
            (total, doc) =>
                total + ((doc.data()['likes'] as num?)?.toInt() ?? 0),
          ),
        );
  }

  /// Number of one-to-one conversations this user is part of.
  Stream<int> friendsCount() {
    return FirebaseFirestore.instance
        .collection('chats')
        .where('participantUids', arrayContains: uid)
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  /// Number of distinct days the user has logged a mood check-in.
  Stream<int> activeDays() {
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('moodEntries')
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }
}
