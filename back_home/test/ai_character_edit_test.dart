// Firestore references are substituted at the persistence boundary only.
// ignore_for_file: subtype_of_sealed_class
import 'package:back_home/chat/ai_chat_repository.dart';
import 'package:back_home/chat/ai_models.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class _Store implements FirebaseFirestore {
  final docs = <String, Map<String, dynamic>>{};
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      _Collection(path);
  @override
  Future<T> runTransaction<T>(
    TransactionHandler<T> handler, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) async {
    final transaction = _Transaction(this);
    final result = await handler(transaction);
    for (final entry in transaction.writes.entries) {
      docs.putIfAbsent(entry.key, () => {}).addAll(entry.value);
    }
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Collection implements CollectionReference<Map<String, dynamic>> {
  _Collection(this.path);
  @override
  final String path;
  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) =>
      _Document('${this.path}/$path');
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Document implements DocumentReference<Map<String, dynamic>> {
  _Document(this.path);
  @override
  final String path;
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      _Collection('${this.path}/$path');
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

class _Transaction implements Transaction {
  _Transaction(this.store);
  final _Store store;
  final writes = <String, Map<String, dynamic>>{};
  @override
  Future<DocumentSnapshot<T>> get<T extends Object?>(
    DocumentReference<T> ref,
  ) async => _Snapshot<T>(store.docs[ref.path] as T?);
  @override
  Transaction update(
    DocumentReference<Object?> ref,
    Map<Object, Object?> data,
  ) {
    if (!store.docs.containsKey(ref.path)) throw StateError('missing');
    writes[ref.path] = Map<String, dynamic>.from(data);
    return this;
  }

  @override
  Transaction set<T>(DocumentReference<T> ref, T data, [SetOptions? options]) {
    expect(options?.merge, isTrue);
    writes[ref.path] = data as Map<String, dynamic>;
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
  const path = 'users/me/aiCharacters/custom';
  late _Store store;
  late AiChatRepository repository;
  setUp(() {
    store = _Store();
    repository = AiChatRepository(
      uid: 'me',
      firestore: store,
      functions: _Functions(),
      storage: _Storage(),
    );
    store.docs[path] = {
      'name': 'Original',
      'personality': 'Quiet',
      'isCustom': true,
      'isFriend': true,
      'authorUid': 'me',
      'avatarUrl': 'photo.png',
      'gender': 'female',
      'createdAt': 'unchanged',
    };
  });
  Future<void> save() => repository.updateCharacterDetails(
    characterId: 'custom',
    name: '  Luna  ',
    personality: '  Kind and loves coding  ',
  );

  test(
    'editing preserves identity, photo, friendship and conversation',
    () async {
      const message = 'users/me/aiChats/custom/messages/first';
      store.docs[message] = {'text': 'Existing conversation'};
      final oldId = AiCharacter.fromData(
        id: 'custom',
        data: store.docs[path]!,
      ).publicId;
      await save();
      final edited = AiCharacter.fromData(
        id: 'custom',
        data: store.docs[path]!,
      );
      expect(edited.name, 'Luna');
      expect(edited.personality, 'Kind and loves coding');
      expect(edited.publicId, oldId);
      expect(edited.discoveryTags, contains('code'));
      expect(edited.avatarUrl, 'photo.png');
      expect(edited.isFriend, isTrue);
      expect(edited.gender, 'female');
      expect(edited.introduction, contains('Luna'));
      expect(store.docs[path]!['createdAt'], 'unchanged');
      expect(store.docs[message]!['text'], 'Existing conversation');
      expect(store.docs.keys, hasLength(2));
    },
  );
  test('published template receives the same edit', () async {
    store.docs[path]!['isPublic'] = true;
    store.docs['publicAiCharacters/custom'] = {
      'authorUid': 'me',
      'createdAt': 'original',
    };
    await save();
    expect(store.docs['publicAiCharacters/custom']!['name'], 'Luna');
    expect(
      store.docs['publicAiCharacters/custom']!['personality'],
      'Kind and loves coding',
    );
    expect(store.docs['publicAiCharacters/custom']!['createdAt'], 'original');
  });
  test('presets and another author cannot be edited', () async {
    store.docs[path]!['isCustom'] = false;
    await expectLater(save(), throwsStateError);
    store.docs[path]!
      ..['isCustom'] = true
      ..['authorUid'] = 'someone-else';
    await expectLater(save(), throwsStateError);
    expect(store.docs[path]!['name'], 'Original');
  });
  test('legacy authored characters remain editable', () async {
    store.docs[path]!.remove('authorUid');
    await save();
    expect(store.docs[path]!['name'], 'Luna');
  });
  test('deleted character is not recreated by a stale editor', () async {
    store.docs.remove(path);
    await expectLater(save(), throwsStateError);
    expect(store.docs, isEmpty);
  });
}
