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

  // ---------------------------------------------------------------- characters

  Stream<List<AiCharacter>> watchCharacters() {
    return _charactersRef.orderBy('createdAt').snapshots().map((snapshot) {
      return snapshot.docs.map(AiCharacter.fromDoc).toList();
    });
  }

  /// Writes the built-in companions the first time an account opens the AI
  /// tab. Skipped as soon as any character exists, so deleting or renaming an
  /// individual preset sticks rather than being restored on the next launch.
  Future<void> seedPresetCharactersIfNeeded() async {
    final existing = await _charactersRef.limit(1).get();
    if (existing.docs.isNotEmpty) {
      return;
    }

    final batch = _firestore.batch();
    for (var index = 0; index < AiCharacter.presets.length; index++) {
      final preset = AiCharacter.presets[index];
      batch.set(_charactersRef.doc(preset.id), {
        ...preset.toFirestore(),
        // Preserves the authored order, since serverTimestamp would collapse
        // to a single batch-commit instant for every preset.
        'createdAt': Timestamp.fromMillisecondsSinceEpoch(index),
      });
    }
    await batch.commit();
  }

  Future<AiCharacter> createCharacter({
    required String name,
    required String personality,
  }) async {
    final doc = _charactersRef.doc();
    final character = AiCharacter(
      id: doc.id,
      name: name,
      personality: personality,
      preview: 'Custom companion ready to chat.',
      colorValue: AiCharacter.customColorValue,
      iconCodePoint: AiCharacter.customIconCodePoint,
      isCustom: true,
    );

    await doc.set({
      ...character.toFirestore(),
      'createdAt': FieldValue.serverTimestamp(),
    });

    return character;
  }

  Future<void> deleteCharacter(String characterId) async {
    await _charactersRef.doc(characterId).delete();
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
    final isUntitled = _readString(snapshot.data()?['title']).isEmpty ||
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
