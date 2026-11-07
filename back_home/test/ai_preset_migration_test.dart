// Replace persistence boundaries only; exercise the actual catalog migration.
// ignore_for_file: subtype_of_sealed_class
import 'package:back_home/chat/ai_chat_repository.dart';
import 'package:back_home/chat/ai_models.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class _Store extends Fake implements FirebaseFirestore {
  final docs = <String, Map<String, dynamic>>{};
  int commits = 0;
  bool failCommit = false;
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      _Collection(this, path);
  @override
  WriteBatch batch() => _Batch(this);
}

class _Collection extends Fake
    implements CollectionReference<Map<String, dynamic>> {
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
  ]) async => _Snapshot([
    for (final entry in store.docs.entries)
      if (entry.key.startsWith('$path/') &&
          entry.key.split('/').length == path.split('/').length + 1)
        _QueryDoc(_Document(store, entry.key), entry.value),
  ]);
}

class _Document extends Fake
    implements DocumentReference<Map<String, dynamic>> {
  _Document(this.store, this.path);
  final _Store store;
  @override
  final String path;
  @override
  String get id => path.split('/').last;
  @override
  CollectionReference<Map<String, dynamic>> collection(String name) =>
      _Collection(store, '$path/$name');
  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get([
    GetOptions? options,
  ]) async => _DocSnapshot(store.docs[path]);
}

class _DocSnapshot extends Fake
    implements DocumentSnapshot<Map<String, dynamic>> {
  _DocSnapshot(this.value);
  final Map<String, dynamic>? value;
  @override
  Map<String, dynamic>? data() => value;
}

class _QueryDoc extends Fake
    implements QueryDocumentSnapshot<Map<String, dynamic>> {
  _QueryDoc(this.reference, this.value);
  @override
  final DocumentReference<Map<String, dynamic>> reference;
  final Map<String, dynamic> value;
  @override
  String get id => reference.id;
  @override
  Map<String, dynamic> data() => value;
}

class _Snapshot extends Fake implements QuerySnapshot<Map<String, dynamic>> {
  _Snapshot(this.docs);
  @override
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
}

class _Batch extends Fake implements WriteBatch {
  _Batch(this.store);
  final _Store store;
  final _writes = <void Function()>[];
  @override
  void set<T>(DocumentReference<T> document, T data, [SetOptions? options]) {
    _writes.add(
      () => store.docs
          .putIfAbsent(document.path, () => {})
          .addAll(data as Map<String, dynamic>),
    );
  }

  @override
  void delete(DocumentReference document) {
    _writes.add(() => store.docs.remove(document.path));
  }

  @override
  Future<void> commit() async {
    if (store.failCommit) throw StateError('offline');
    for (final write in _writes) {
      write();
    }
    store.commits++;
  }
}

class _Functions extends Fake implements FirebaseFunctions {}

class _Storage extends Fake implements FirebaseStorage {}

void main() {
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
  });

  test(
    'existing accounts receive new people without resurrecting removed old ones',
    () async {
      store.docs['users/me'] = {'aiPresetCatalogVersion': 4};
      for (final preset in AiCharacter.presets.where(
        (c) => AiCharacter.introducedInCatalogVersion(c.id) < 5,
      )) {
        if (preset.id == 'noah-carter') continue;
        store.docs['users/me/aiCharacters/${preset.id}'] = {
          ...preset.toFirestore(),
          'isFriend': true,
        };
      }
      const custom = {
        'name': 'My own Ethan',
        'isCustom': true,
        'personality': 'User authored',
      };
      store.docs['users/me/aiCharacters/ethan-miller'] = Map.of(custom);
      store.docs['users/me/aiCharacters/my-custom'] = {
        'isCustom': true,
        'name': 'Mine',
      };
      store.docs['users/me/aiCharacters/olivia-parker']!['avatarUrl'] =
          'https://example.com/my-photo.png';
      await repository.seedPresetCharactersIfNeeded();
      expect(store.docs, isNot(contains('users/me/aiCharacters/noah-carter')));
      expect(store.docs['users/me/aiCharacters/ethan-miller'], custom);
      expect(store.docs['users/me/aiCharacters/my-custom']!['name'], 'Mine');
      expect(
        store.docs['users/me/aiCharacters/olivia-parker']!['isFriend'],
        isTrue,
      );
      expect(
        store.docs['users/me/aiCharacters/olivia-parker']!['avatarUrl'],
        'https://example.com/my-photo.png',
      );
      final added = AiCharacter.presets.where(
        (c) => AiCharacter.introducedInCatalogVersion(c.id) == 5,
      );
      for (final preset in added) {
        expect(
          store.docs['users/me/aiCharacters/${preset.id}']!['personality'],
          preset.personality,
        );
      }
      expect(store.docs['users/me']!['aiPresetCatalogVersion'], 5);
      await repository.seedPresetCharactersIfNeeded();
      expect(store.commits, 1);
    },
  );

  test('new accounts receive all seventy presets in one batch', () async {
    await repository.seedPresetCharactersIfNeeded();
    expect(
      store.docs.keys.where((key) => key.startsWith('users/me/aiCharacters/')),
      hasLength(70),
    );
    expect(store.docs['users/me']!['aiPresetCatalogVersion'], 5);
    expect(store.commits, 1);
  });

  test(
    'failed install remains retryable; older clients never downgrade a future catalog',
    () async {
      store.docs['users/me'] = {'aiPresetCatalogVersion': 4};
      store.failCommit = true;
      await expectLater(
        repository.seedPresetCharactersIfNeeded(),
        throwsStateError,
      );
      expect(store.docs['users/me']!['aiPresetCatalogVersion'], 4);
      expect(
        store.docs.keys.where((key) => key.contains('/aiCharacters/')),
        isEmpty,
      );
      store.failCommit = false;
      await repository.seedPresetCharactersIfNeeded();
      expect(
        store.docs.keys.where((key) => key.contains('/aiCharacters/')),
        hasLength(20),
      );
      store.docs['users/me']!['aiPresetCatalogVersion'] = 6;
      await repository.seedPresetCharactersIfNeeded();
      expect(store.docs['users/me']!['aiPresetCatalogVersion'], 6);
      expect(store.commits, 1);
    },
  );
}
