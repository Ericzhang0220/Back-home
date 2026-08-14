import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

/// Live profile counters derived from the data the app already stores, so the
/// profile stat pills reflect real activity instead of placeholder numbers.
class ProfileStats {
  ProfileStats(this.uid);

  final String uid;

  /// Likes earned: every like on a hall post this user wrote, plus one for
  /// each person they have added.
  ///
  /// This only ever grows. Unfriending does not give a like back — the sole
  /// way the number falls is spending in the room shop.
  Stream<int> likesReceived() {
    return _sum(_postLikes(), _friendLikes());
  }

  Stream<int> _postLikes() {
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

  /// One per person ever added — the ledger keeps a document for each, and
  /// never drops one.
  Stream<int> _friendLikes() {
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('friendLikeAwards')
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  /// Adds two counter streams, emitting a fresh total whenever either moves.
  /// Each side counts as zero until it has reported, so the pill shows a
  /// partial total rather than nothing while the second query loads.
  static Stream<int> _sum(Stream<int> first, Stream<int> second) {
    var a = 0;
    var b = 0;
    late StreamSubscription<int> firstSub;
    late StreamSubscription<int> secondSub;
    late StreamController<int> controller;

    controller = StreamController<int>(
      onListen: () {
        firstSub = first.listen(
          (value) {
            a = value;
            controller.add(a + b);
          },
          onError: controller.addError,
        );
        secondSub = second.listen(
          (value) {
            b = value;
            controller.add(a + b);
          },
          onError: controller.addError,
        );
      },
      onCancel: () async {
        await firstSub.cancel();
        await secondSub.cancel();
      },
    );
    return controller.stream;
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
