// Firestore's sealed SDK references are substituted only at this test boundary.
// ignore_for_file: subtype_of_sealed_class

import 'package:back_home/chat/ai_chat_repository.dart';
import 'package:back_home/chat/ai_models.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_test/flutter_test.dart';

// Only the Firestore boundary is substituted: the repository performs its
// real deletion, batching and transaction logic against a small in-memory log.
class _Store implements FirebaseFirestore {
  final documents = <String, Map<String, dynamic>>{};
  final batches = <List<String>>[];
  void Function()? afterBatch;
  bool failBatch = false;

  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      _Collection(this, path);

  @override
  WriteBatch batch() => _Batch(this);

  @override
  Future<T> runTransaction<T>(
    TransactionHandler<T> handler, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) => handler(_Transaction(this));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Collection implements CollectionReference<Map<String, dynamic>> {
  _Collection(this.store, this.path);
  final _Store store;
  @override
  final String path;

  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) =>
      _Document(store, '${this.path}/$path');

  @override
  Future<QuerySnapshot<Map<String, dynamic>>> get([
    GetOptions? options,
  ]) async => _QuerySnapshot([
    for (final entry in store.documents.entries)
      if (entry.key.startsWith('$path/') &&
          !entry.key.substring(path.length + 1).contains('/'))
        _QueryDocument(_Document(store, entry.key), Map.of(entry.value)),
  ]);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Document implements DocumentReference<Map<String, dynamic>> {
  _Document(this.store, this.path);
  final _Store store;
  @override
  final String path;
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      _Collection(store, '${this.path}/$path');
  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get([
    GetOptions? options,
  ]) async => _Snapshot<Map<String, dynamic>>(store.documents[path]);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Snapshot<T extends Object?> implements DocumentSnapshot<T> {
  _Snapshot(this.value);
  final T? value;
  @override
  T? data() => value;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _QueryDocument implements QueryDocumentSnapshot<Map<String, dynamic>> {
  _QueryDocument(this.reference, this.value);
  @override
  final DocumentReference<Map<String, dynamic>> reference;
  final Map<String, dynamic> value;
  @override
  Map<String, dynamic> data() => value;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _QuerySnapshot implements QuerySnapshot<Map<String, dynamic>> {
  _QuerySnapshot(this.docs);
  @override
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Batch implements WriteBatch {
  _Batch(this.store);
  final _Store store;
  final paths = <String>[];
  @override
  void delete(DocumentReference<Object?> document) => paths.add(document.path);
  @override
  Future<void> commit() async {
    if (store.failBatch) throw StateError('offline');
    store.batches.add(List.of(paths));
    for (final path in paths) {
      store.documents.remove(path);
    }
    store.afterBatch?.call();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Transaction implements Transaction {
  _Transaction(this.store);
  final _Store store;
  @override
  Future<DocumentSnapshot<T>> get<T extends Object?>(
    DocumentReference<T> ref,
  ) async => _Snapshot<T>(store.documents[ref.path] as T?);
  @override
  Transaction set<T>(DocumentReference<T> ref, T data, [SetOptions? options]) {
    expect(options?.merge, isTrue);
    final target = store.documents.putIfAbsent(ref.path, () => {});
    for (final entry in (data as Map<String, dynamic>).entries) {
      if (entry.value is FieldValue) {
        target.remove(entry.key);
      } else {
        target[entry.key] = entry.value;
      }
    }
    return this;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Functions implements FirebaseFunctions {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Storage implements FirebaseStorage {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  const chat = 'users/me/aiChats/lily';
  const character = 'users/me/aiCharacters/lily';
  final old = Timestamp.fromDate(DateTime.utc(2026, 10, 3));
  final newer = Timestamp.fromDate(DateTime.utc(2026, 10, 3, 0, 0, 1));
  _Store seed(int count) {
    final store = _Store();
    store.documents[character] = {'name': 'Lily', 'isFriend': true};
    store.documents[chat] = {
      'isFavorite': true,
      'userMessageCount': count,
      'lastMessage': 'old reply',
      'updatedAt': old,
    };
    for (var i = 0; i < count; i++) {
      store.documents['$chat/messages/$i'] = {'text': 'old', 'createdAt': old};
    }
    return store;
  }

  AiChatRepository repository(_Store store) => AiChatRepository(
    uid: 'me',
    firestore: store,
    functions: _Functions(),
    storage: _Storage(),
  );

  test('large chat deletion preserves the friend and Like', () async {
    final store = seed(805);
    await repository(store).deleteCharacterChat('lily');
    expect(store.batches.map((batch) => batch.length), [400, 400, 5]);
    expect(
      store.documents.keys.where((path) => path.startsWith('$chat/messages/')),
      isEmpty,
    );
    expect(store.documents[character]!['isFriend'], isTrue);
    final parent = store.documents[chat]!;
    expect(parent['isFavorite'], isTrue);
    expect(parent['userMessageCount'], 805);
    expect(parent.containsKey('lastMessage'), isFalse);
    expect(AiChatPreview.fromData(parent).isHidden, isTrue);
    expect(parent['readThrough'], old);
  });

  test(
    'a new reply during deletion is preserved and restores the chat',
    () async {
      final store = seed(2);
      store.afterBatch = () {
        store.documents['$chat/messages/new'] = {
          'text': 'new reply',
          'createdAt': newer,
        };
        store.documents[chat]!.addAll({
          'lastMessage': 'new reply',
          'updatedAt': newer,
        });
      };
      await repository(store).deleteCharacterChat('lily');
      final parent = store.documents[chat]!;
      expect(store.documents.containsKey('$chat/messages/new'), isTrue);
      expect(parent['lastMessage'], 'new reply');
      expect(AiChatPreview.fromData(parent).isHidden, isFalse);
      expect(parent['readThrough'], old);
    },
  );

  test('a failed deletion leaves the chat visible and retryable', () async {
    final store = seed(2)..failBatch = true;
    await expectLater(
      repository(store).deleteCharacterChat('lily'),
      throwsStateError,
    );
    expect(AiChatPreview.fromData(store.documents[chat]!).isHidden, isFalse);
    expect(store.documents.containsKey('$chat/messages/0'), isTrue);
    store.failBatch = false;
    await repository(store).deleteCharacterChat('lily');
    expect(AiChatPreview.fromData(store.documents[chat]!).isHidden, isTrue);
  });

  test('custom characters honor an explicitly removed Like', () {
    expect(
      AiCharacter.fromData(id: 'custom', data: {'isCustom': true}).isFriend,
      isTrue,
    );
    expect(
      AiCharacter.fromData(
        id: 'custom',
        data: {'isCustom': true, 'isFriend': false},
      ).isFriend,
      isFalse,
    );
  });

  test(
    'an empty deleted chat reappears when its first reply arrives',
    () async {
      final store = seed(0);
      store.documents[chat] = {'isFavorite': true};
      await repository(store).deleteCharacterChat('lily');
      final parent = store.documents[chat]!;
      expect(AiChatPreview.fromData(parent).isHidden, isTrue);
      expect(parent['readThrough'], Timestamp(0, 0));
      parent.addAll({'lastMessage': 'first reply', 'updatedAt': newer});
      expect(AiChatPreview.fromData(parent).isHidden, isFalse);
      expect(store.documents[character]!['isFriend'], isTrue);
    },
  );
}
