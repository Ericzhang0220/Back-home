import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';

import 'ai_models.dart';

/// Firestore + Cloud Functions data layer behind the AI and Tutor chat tabs.
///
/// The client only ever writes the user's own turns. Assistant turns are
/// written server-side by the `askTutor` / `chatWithCharacter` callables, so
/// a reply lands in the stream rather than being returned into local state.
class AiChatRepository {
  AiChatRepository({
    required this.uid,
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
    FirebaseStorage? storage,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _functions = functions ?? FirebaseFunctions.instance,
       _storage = storage ?? FirebaseStorage.instance;

  final String uid;
  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;
  final FirebaseStorage _storage;

  DocumentReference<Map<String, dynamic>> get _userRef =>
      _firestore.collection('users').doc(uid);

  CollectionReference<Map<String, dynamic>> get _charactersRef =>
      _userRef.collection('aiCharacters');

  CollectionReference<Map<String, dynamic>> get _tutorSessionsRef =>
      _userRef.collection('tutorSessions');

  /// Shared catalog of characters people chose to publish. Readable by every
  /// signed-in account; each document is only writable by its author.
  CollectionReference<Map<String, dynamic>> get _publicCharactersRef =>
      _firestore.collection('publicAiCharacters');

  // ---------------------------------------------------------------- characters

  Stream<List<AiCharacter>> watchCharacters() {
    return _charactersRef.orderBy('createdAt').snapshots().map((snapshot) {
      return snapshot.docs.map(AiCharacter.fromDoc).toList();
    });
  }

  /// Installs each built-in catalog version once per account.
  ///
  /// Custom characters are never changed. After the catalog is installed,
  /// removing an individual preset also continues to stick on later launches.
  Future<void> seedPresetCharactersIfNeeded() async {
    final userSnapshot = await _userRef.get();
    final installedVersion = userSnapshot.data()?['aiPresetCatalogVersion'];
    if (installedVersion == AiCharacter.presetCatalogVersion) {
      return;
    }

    final existing = await _charactersRef.get();
    final existingIds = existing.docs.map((doc) => doc.id).toSet();
    final batch = _firestore.batch();
    for (var index = 0; index < AiCharacter.presets.length; index++) {
      final preset = AiCharacter.presets[index];
      if (existingIds.contains(preset.id)) {
        // Refresh built-in fields when the catalog changes, but retain a
        // picture a person may later add to a preset and their saved-friend
        // choice.
        final refreshedFields = preset.toFirestore()..remove('isFriend');
        batch.set(
          _charactersRef.doc(preset.id),
          refreshedFields,
          SetOptions(merge: true),
        );
      } else {
        batch.set(_charactersRef.doc(preset.id), {
          ...preset.toFirestore(),
          // Preserves the authored order, since serverTimestamp would collapse
          // to a single batch-commit instant for every preset.
          'createdAt': Timestamp.fromMillisecondsSinceEpoch(index),
        });
      }
    }

    // Retire only the old built-ins, leaving all user-authored characters and
    // their data untouched. Existing conversation documents remain available
    // in Firestore, rather than being deleted as part of a catalog refresh.
    for (final legacy in existing.docs) {
      if (AiCharacter.legacyPresetIds.contains(legacy.id) &&
          legacy.data()['isCustom'] != true) {
        batch.delete(legacy.reference);
      }
    }

    batch.set(_userRef, {
      'aiPresetCatalogVersion': AiCharacter.presetCatalogVersion,
    }, SetOptions(merge: true));
    await batch.commit();
  }

  Future<AiCharacter> createCharacter({
    required String name,
    required String personality,
    bool isPublic = false,
  }) async {
    final doc = _charactersRef.doc();
    final character = AiCharacter(
      id: doc.id,
      name: name,
      personality: personality,
      introduction: 'Hi, I’m $name. I’m here whenever you would like to talk.',
      preview: 'Custom companion ready to chat.',
      colorValue: AiCharacter.customColorValue,
      iconCodePoint: AiCharacter.customIconCodePoint,
      isCustom: true,
      isFriend: true,
      isPublic: isPublic,
      authorUid: uid,
    );

    await doc.set({
      ...character.toFirestore(),
      'createdAt': FieldValue.serverTimestamp(),
    });

    // A private character never leaves the author's own subcollection, which
    // no other account can read.
    if (isPublic) {
      await _publicCharactersRef.doc(doc.id).set({
        ...character.toPublicTemplate(authorUid: uid),
        'createdAt': FieldValue.serverTimestamp(),
      });
    }

    return character;
  }

  /// Everything other people have shared. The caller filters out its own
  /// entries and anything already copied into its collection.
  Stream<List<AiCharacter>> watchPublicCharacters() {
    return _publicCharactersRef.snapshots().map((snapshot) {
      return snapshot.docs.map(AiCharacter.fromDoc).toList();
    }).handleError((Object _) {});
  }

  /// Copies a shared character into this account, keeping the template's id so
  /// the catalog entry and the local copy stay matched up.
  ///
  /// Pass `asFriend: false` to take the copy without saving them to the
  /// friends list — needed before chatting, because the reply function reads
  /// the character from the caller's own collection.
  Future<void> adoptPublicCharacter(
    AiCharacter template, {
    bool asFriend = true,
  }) {
    return _charactersRef.doc(template.id).set({
      ...template.toFirestore(),
      // Someone else authored it, so it is not "custom" here — that flag marks
      // the characters this account made and can edit.
      'isCustom': false,
      'isFriend': asFriend,
      'isPublic': true,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteCharacter(String characterId) async {
    await _charactersRef.doc(characterId).delete();
    // Withdraw the shared copy too, if this account published one. Fails
    // harmlessly for characters it did not author.
    try {
      await _publicCharactersRef.doc(characterId).delete();
    } catch (_) {}
  }

  /// Live view of a single character, so a screen already scoped to one
  /// companion can follow its friend state without watching the whole list.
  /// Emits null once the character no longer exists.
  Stream<AiCharacter?> watchCharacter(String characterId) {
    return _charactersRef.doc(characterId).snapshots().map((doc) {
      final data = doc.data();
      return data == null
          ? null
          : AiCharacter.fromData(id: doc.id, data: data);
    });
  }

  /// Saves a discovered built-in character to the person's AI friends list.
  Future<void> addCharacterAsFriend(String characterId) {
    return _charactersRef.doc(characterId).set({
      'isFriend': true,
    }, SetOptions(merge: true));
  }

  /// Drops a built-in character back out of the friends list. The conversation
  /// itself is left alone, so re-adding them picks the thread back up.
  Future<void> removeCharacterAsFriend(String characterId) {
    return _charactersRef.doc(characterId).set({
      'isFriend': false,
    }, SetOptions(merge: true));
  }

  /// Uploads a picked avatar and stores its download URL on the character.
  Future<void> updateCharacterAvatar({
    required String characterId,
    required Uint8List bytes,
    required String contentType,
  }) async {
    final ref = _storage.ref('ai_avatars/$uid/$characterId');
    await ref.putData(bytes, SettableMetadata(contentType: contentType));
    final url = await ref.getDownloadURL();

    await _charactersRef.doc(characterId).set({
      'avatarUrl': url,
    }, SetOptions(merge: true));
  }

  // -------------------------------------------------------------- ai character

  CollectionReference<Map<String, dynamic>> _characterMessagesRef(
    String characterId,
  ) {
    return _userRef
        .collection('aiChats')
        .doc(characterId)
        .collection('messages');
  }

  Stream<List<AiMessage>> watchCharacterMessages(String characterId) {
    return _characterMessagesRef(
      characterId,
    ).orderBy('createdAt').snapshots().map(_toMessages);
  }

  /// Streams the per-character conversation previews shown on the AI tab,
  /// keyed by character id.
  Stream<Map<String, AiChatPreview>> watchCharacterPreviews() {
    return _userRef.collection('aiChats').snapshots().map((snapshot) {
      return {
        for (final doc in snapshot.docs)
          doc.id: AiChatPreview(
            lastMessage: _readString(doc.data()['lastMessage']),
            updatedAt: (doc.data()['updatedAt'] as Timestamp?)?.toDate(),
          ),
      };
    });
  }

  /// Appends the user's turn, then asks the backend for a reply. The reply is
  /// written server-side, so callers just await completion and let the stream
  /// deliver the text.
  Future<void> sendToCharacter({
    required String characterId,
    required String text,
  }) async {
    await _characterMessagesRef(characterId).add({
      'role': 'user',
      'text': text,
      'createdAt': FieldValue.serverTimestamp(),
    });

    await _callFunction('chatWithCharacter', {'characterId': characterId});
  }

  // --------------------------------------------------------------------- tutor

  CollectionReference<Map<String, dynamic>> _tutorMessagesRef(
    String sessionId,
  ) {
    return _tutorSessionsRef.doc(sessionId).collection('messages');
  }

  Stream<List<TutorSession>> watchTutorSessions() {
    return _tutorSessionsRef
        .orderBy('updatedAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(TutorSession.fromDoc).toList());
  }

  Stream<List<AiMessage>> watchTutorMessages(String sessionId) {
    return _tutorMessagesRef(
      sessionId,
    ).orderBy('createdAt').snapshots().map(_toMessages);
  }

  Future<String> createTutorSession({String? title}) async {
    final doc = _tutorSessionsRef.doc();
    await doc.set({
      'title': title ?? 'New question',
      'subtitle': 'Ask anything you want help thinking through',
      'lastMessage': '',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return doc.id;
  }

  Future<void> deleteTutorSession(String sessionId) async {
    final messages = await _tutorMessagesRef(sessionId).get();
    final batch = _firestore.batch();
    for (final doc in messages.docs) {
      batch.delete(doc.reference);
    }
    batch.delete(_tutorSessionsRef.doc(sessionId));
    await batch.commit();
  }

  Future<void> sendToTutor({
    required String sessionId,
    required String text,
  }) async {
    final sessionRef = _tutorSessionsRef.doc(sessionId);

    await _tutorMessagesRef(sessionId).add({
      'role': 'user',
      'text': text,
      'createdAt': FieldValue.serverTimestamp(),
    });

    // The first real question becomes the session's title, so the history
    // drawer shows something meaningful instead of "New question".
    final snapshot = await sessionRef.get();
    final isUntitled =
        _readString(snapshot.data()?['title']).isEmpty ||
        _readString(snapshot.data()?['title']).startsWith('New question');

    await sessionRef.set({
      if (isUntitled) 'title': _titleFrom(text),
      'subtitle': text,
      'lastMessage': text,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await _callFunction('askTutor', {'sessionId': sessionId});
  }

  // ------------------------------------------------------------------ internals

  Future<void> _callFunction(String name, Map<String, dynamic> payload) async {
    try {
      await _functions.httpsCallable(name).call<dynamic>(payload);
    } on FirebaseFunctionsException catch (error) {
      throw AiChatException(error.message ?? 'The AI could not reply.');
    } catch (_) {
      throw const AiChatException(
        'Could not reach the AI. Check your connection and try again.',
      );
    }
  }

  static List<AiMessage> _toMessages(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    return snapshot.docs
        .map(AiMessage.fromDoc)
        .where((message) => message.text.isNotEmpty)
        .toList();
  }

  static String _titleFrom(String text) {
    final normalized = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.length <= 40) {
      return normalized;
    }
    return '${normalized.substring(0, 37)}...';
  }

  static String _readString(Object? value) {
    return value is String ? value.trim() : '';
  }
}

class AiChatException implements Exception {
  const AiChatException(this.message);

  final String message;

  @override
  String toString() => message;
}
