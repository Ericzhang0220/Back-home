import 'package:cloud_firestore/cloud_firestore.dart';

typedef ShopDebitResult = ({int likes, bool charged});

abstract interface class ShopWallet {
  Future<int> initialize(String uid, int localBalance);
  Stream<int> watch(String uid);
  Future<ShopDebitResult> debit(String uid, String id, int cost);
}

class FirestoreShopWallet implements ShopWallet {
  FirestoreShopWallet(this.firestore);
  final FirebaseFirestore firestore;

  DocumentReference<Map<String, dynamic>> _wallet(String uid) =>
      firestore.collection('users').doc(uid).collection('shop').doc('wallet');

  int _balance(DocumentSnapshot<Map<String, dynamic>> snapshot) {
    final value = snapshot.data()?['likes'];
    if (value is! int || value < 0) {
      throw StateError('Invalid shop wallet.');
    }
    return value;
  }

  @override
  Future<int> initialize(String uid, int localBalance) {
    final wallet = _wallet(uid);
    return firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(wallet);
      if (snapshot.exists) return _balance(snapshot);
      transaction.set(wallet, {'likes': localBalance});
      return localBalance;
    });
  }

  @override
  Stream<int> watch(String uid) => _wallet(uid)
      .snapshots(includeMetadataChanges: true)
      .where(
        (snapshot) =>
            snapshot.exists &&
            !snapshot.metadata.isFromCache &&
            !snapshot.metadata.hasPendingWrites,
      )
      .map(_balance);

  @override
  Future<ShopDebitResult> debit(String uid, String id, int cost) {
    final wallet = _wallet(uid);
    final receipt = wallet.collection('debits').doc(id);
    return firestore.runTransaction((transaction) async {
      final previous = await transaction.get(receipt);
      final balance = _balance(await transaction.get(wallet));
      if (previous.exists) {
        if (previous.data()?['cost'] != cost) {
          throw StateError('Shop debit does not match the saved purchase.');
        }
        return (likes: balance, charged: true);
      }
      if (balance < cost) return (likes: balance, charged: false);
      final remaining = balance - cost;
      transaction.update(wallet, {'likes': remaining, 'lastDebitId': id});
      transaction.set(receipt, {'cost': cost});
      return (likes: remaining, charged: true);
    });
  }
}
