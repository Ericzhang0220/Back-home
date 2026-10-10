import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';

import 'ai_models.dart';
import 'ai_character_catalog.dart';
import 'ai_character_photo.dart';
import 'ai_discovery_recommender.dart';

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
    required AiCharacterPhoto photo,
    String gender = 'unspecified',
    List<String> tags = const [],
    bool isPublic = false,
  }) async {
    if (photo.bytes.isEmpty ||
        photo.bytes.length > AiCharacterPhoto.maxBytes ||
        !photo.contentType.startsWith('image/')) {
      throw ArgumentError('A character photo is required (maximum 10 MB).');
    }
    final doc = _charactersRef.doc();
    final avatarRef = _storage.ref('ai_avatars/$uid/${doc.id}');
    // Upload first: a failed upload must never leave a photo-less character.
    try {
      await avatarRef.putData(
        photo.bytes,
        SettableMetadata(contentType: photo.contentType),
      );
      final avatarUrl = await avatarRef.getDownloadURL();
      final character = AiCharacter(
        id: doc.id,
        name: name,
        personality: personality,
        introduction:
            'Hi, I’m $name. I’m here whenever you would like to talk.',
        preview: 'Custom companion ready to chat.',
        colorValue: AiCharacter.customColorValue,
        iconCodePoint: AiCharacter.customIconCodePoint,
        isCustom: true,
        isFriend: true,
        isPublic: isPublic,
        authorUid: uid,
        avatarUrl: avatarUrl,
        genderValue: gender,
        preferenceTags: tags,
      );

      final batch = _firestore.batch();
      batch.set(doc, {
        ...character.toFirestore(),
        'createdAt': FieldValue.serverTimestamp(),
      });

      // A private character never leaves the author's own subcollection, which
      // no other account can read.
      if (isPublic) {
        batch.set(_publicCharactersRef.doc(doc.id), {
          ...character.toPublicTemplate(authorUid: uid),
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
      return character;
    } catch (_) {
      // Only this new, uncommitted upload is cleaned up. Keep the dialog's
      // selected bytes so the person can retry without opening Photos again.
      try {
        await avatarRef.delete();
      } catch (_) {}
      rethrow;
    }
  }

  /// Everything other people have shared. The caller filters out its own
  /// entries and anything already copied into its collection.
  Stream<List<AiCharacter>> watchPublicCharacters() {
    return _publicCharactersRef
        .snapshots()
        .map((snapshot) {
          return snapshot.docs.map(AiCharacter.fromDoc).toList();
        })
        .handleError((Object _) {});
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
    final batch = _firestore.batch();
    batch.set(_charactersRef.doc(template.id), {
      ...template.toFirestore(),
      // Someone else authored it, so it is not "custom" here — that flag marks
      // the characters this account made and can edit.
      'isCustom': false,
      'isFriend': asFriend,
      'isPublic': true,
      'createdAt': FieldValue.serverTimestamp(),
    });
    if (asFriend) {
      batch.set(_userRef.collection('aiChats').doc(template.id), {
        'isFavorite': true,
      }, SetOptions(merge: true));
    }
    return batch.commit();
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
      return data == null ? null : AiCharacter.fromData(id: doc.id, data: data);
    });
  }

  /// Saves a discovered built-in character to the person's AI friends list.
  Future<void> addCharacterAsFriend(String characterId) {
    final batch = _firestore.batch();
    batch.set(_charactersRef.doc(characterId), {
      'isFriend': true,
    }, SetOptions(merge: true));
    batch.set(_userRef.collection('aiChats').doc(characterId), {
      'isFavorite': true,
    }, SetOptions(merge: true));
    return batch.commit();
  }

  /// Drops a built-in character back out of the friends list. The conversation
  /// itself is left alone, so re-adding them picks the thread back up.
  Future<void> removeCharacterAsFriend(String characterId) {
    final batch = _firestore.batch();
    batch.set(_charactersRef.doc(characterId), {
      'isFriend': false,
    }, SetOptions(merge: true));
    batch.set(_userRef.collection('aiChats').doc(characterId), {
      'isFavorite': false,
    }, SetOptions(merge: true));
    return batch.commit();
  }

  /// Edits this account's authored character and its published template together.
  Future<void> updateCharacterDetails({
    required String characterId,
    required String name,
    required String personality,
  }) async {
    final cleanName = name.trim();
    final cleanPersonality = personality.trim();
    if (cleanName.isEmpty ||
        cleanName.length > 60 ||
        cleanPersonality.isEmpty ||
        cleanPersonality.length > 400) {
      throw ArgumentError(
        'Enter a name and personality within the character limits.',
      );
    }
    final ref = _charactersRef.doc(characterId);
    await _firestore.runTransaction<void>((transaction) async {
      final snapshot = await transaction.get(ref);
      final data = snapshot.data();
      if (data == null) throw StateError('This character no longer exists.');
      final character = AiCharacter.fromData(id: characterId, data: data);
      if (!character.canEditBy(uid)) {
        throw StateError('Only characters you created can be edited.');
      }
      final fields = <String, dynamic>{
        'name': cleanName,
        'personality': cleanPersonality,
        'tags': aiTagsFromPersonality(cleanPersonality),
        if (cleanName != character.name)
          'introduction':
              'Hi, I’m $cleanName. I’m here whenever you would like to talk.',
      };
      transaction.update(ref, fields);
      if (character.isPublic && character.authorUid == uid) {
        transaction.set(
          _publicCharactersRef.doc(characterId),
          {...character.toPublicTemplate(authorUid: uid), ...fields},
          SetOptions(merge: true),
        );
      }
    });
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

    final character = await _charactersRef.doc(characterId).get();
    final batch = _firestore.batch();
    batch.set(character.reference, {'avatarUrl': url}, SetOptions(merge: true));
    if (character.data()?['isPublic'] == true &&
        character.data()?['authorUid'] == uid) {
      batch.set(_publicCharactersRef.doc(characterId), {
        'avatarUrl': url,
      }, SetOptions(merge: true));
    }
    await batch.commit();
  }

  // -------------------------------------------------------------- ai character

  final Map<String, Future<int>> _interactionInitializers = {};
  Stream<Map<String, AiCharacterInteraction>>? _discoveryInteractions;

  /// Private, per-account signals. Old threads are counted once before the
  /// incremental counter is installed; assistant replies never count.
  Stream<Map<String, AiCharacterInteraction>> watchDiscoveryInteractions() {
    return _discoveryInteractions ??= _userRef
        .collection('aiChats')
        .snapshots()
        .asyncMap((snapshot) async {
          final entries = await Future.wait(
            snapshot.docs.map((doc) async {
              final data = doc.data();
              final count = data['userMessageCount'] is int
                  ? data['userMessageCount'] as int
                  : await _ensureInteractionCount(doc.id);
              return MapEntry(
                doc.id,
                AiCharacterInteraction(
                  userMessageCount: count < 0 ? 0 : count,
                  isFavorite: data['isFavorite'] == true,
                  isChatHidden: AiChatPreview.fromData(data).isHidden,
                ),
              );
            }),
          );
          return Map.fromEntries(entries);
        });
  }

  Future<int> _ensureInteractionCount(String characterId) {
    return _interactionInitializers.putIfAbsent(characterId, () async {
      try {
        final chatRef = _userRef.collection('aiChats').doc(characterId);
        final existing = await chatRef.get();
        if (existing.data()?['userMessageCount'] is int) {
          return existing.data()!['userMessageCount'] as int;
        }
        final history = await _characterMessagesRef(
          characterId,
        ).where('role', isEqualTo: 'user').count().get();
        return await _firestore.runTransaction<int>((transaction) async {
          final current = await transaction.get(chatRef);
          final count = current.data()?['userMessageCount'];
          if (count is int) return count;
          final historicalCount = history.count ?? 0;
          transaction.set(chatRef, {
            'userMessageCount': historicalCount,
          }, SetOptions(merge: true));
          return historicalCount;
        });
      } catch (_) {
        _interactionInitializers.remove(characterId);
        rethrow;
      }
    });
  }

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

  /// Discovery cards only render the two latest turns. Keep adjacent cards
  /// ready without subscribing to each character's complete chat history.
  Stream<List<AiMessage>> watchCharacterPreviewMessages(String characterId) {
    return _characterMessagesRef(characterId)
        .orderBy('createdAt', descending: true)
        .limit(2)
        .snapshots()
        .map((snapshot) => _toMessages(snapshot).reversed.toList());
  }

  /// Streams the per-character conversation previews shown on the AI tab,
  /// keyed by character id.
  Stream<Map<String, AiChatPreview>> watchCharacterPreviews() {
    return _userRef.collection('aiChats').snapshots().map((snapshot) {
      return {
        for (final doc in snapshot.docs)
          doc.id: AiChatPreview.fromData(doc.data()),
      };
    });
  }

  /// Clears the conversation without changing the character or its heart.
  /// Keep the parent so discovery preferences and friendship remain intact.
  Future<void> deleteCharacterChat(String characterId) async {
    final chatRef = _userRef.collection('aiChats').doc(characterId);
    final before = await chatRef.get();
    final messages = await _characterMessagesRef(characterId).get();
    final timestamps = [
      before.data()?['updatedAt'],
      ...messages.docs.map((doc) => doc.data()['createdAt']),
    ].whereType<Timestamp>().toList()..sort((a, b) => a.compareTo(b));
    // An empty chat uses an epoch cursor, so the phone's clock cannot hide
    // its first incoming reply after deletion.
    final cutoff = timestamps.isEmpty ? Timestamp(0, 0) : timestamps.last;
    // Capture only existing messages, so a reply arriving during deletion
    // isn't accidentally swept into an unbounded deletion loop.
    for (var offset = 0; offset < messages.docs.length; offset += 400) {
      final batch = _firestore.batch();
      for (final doc in messages.docs.skip(offset).take(400)) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }
    await _firestore.runTransaction((transaction) async {
      final current = await transaction.get(chatRef);
      final data = current.data() ?? {};
      final activity = data['updatedAt'] as Timestamp?;
      final readThrough = data['readThrough'] as Timestamp?;
      final hasNewMessage = activity != null && activity.compareTo(cutoff) > 0;
      transaction.set(chatRef, {
        'isHidden': true,
        'deletedAt': cutoff,
        'readThrough': readThrough != null && readThrough.compareTo(cutoff) > 0
            ? readThrough
            : cutoff,
        // Preserve a new message that arrived while older history was cleared.
        if (!hasNewMessage) 'lastMessage': FieldValue.delete(),
        if (!hasNewMessage) 'updatedAt': FieldValue.delete(),
      }, SetOptions(merge: true));
    });
  }

  /// Appends the user's turn, then asks the backend for a reply. The reply is
  /// written server-side, so callers just await completion and let the stream
  /// deliver the text.
  Future<void> sendToCharacter({
    required String characterId,
    required String text,
  }) async {
    if (text.trim().isEmpty) return;
    await _ensureInteractionCount(characterId);
    final batch = _firestore.batch();
    batch.set(_characterMessagesRef(characterId).doc(), {
      'role': 'user',
      'text': text,
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.set(_charactersRef.doc(characterId), {
      'isFriend': true,
    }, SetOptions(merge: true));
    batch.set(_userRef.collection('aiChats').doc(characterId), {
      'characterId': characterId,
      'userMessageCount': FieldValue.increment(1),
      'isHidden': false,
      'lastMessage': text,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await batch.commit();

    await _callFunction('chatWithCharacter', {'characterId': characterId});
  }

  // --------------------------------------------------------------------- tutor

  // Reuse stream identities so ordinary UI rebuilds do not put the Tutor
  // conversation and history back into their loading states.
  late final Stream<List<TutorSession>> _tutorSessionsStream = _tutorSessionsRef
      .orderBy('updatedAt', descending: true)
      .snapshots()
      .map((snapshot) => snapshot.docs.map(TutorSession.fromDoc).toList());
  String? _watchedTutorSessionId;
  Stream<List<AiMessage>>? _tutorMessagesStream;

  CollectionReference<Map<String, dynamic>> _tutorMessagesRef(
    String sessionId,
  ) {
    return _tutorSessionsRef.doc(sessionId).collection('messages');
  }

  Stream<List<TutorSession>> watchTutorSessions() {
    return _tutorSessionsStream;
  }

  Stream<List<AiMessage>> watchTutorMessages(String sessionId) {
    if (_watchedTutorSessionId != sessionId) {
      _watchedTutorSessionId = sessionId;
      _tutorMessagesStream = _tutorMessagesRef(
        sessionId,
      ).orderBy('createdAt').snapshots().map(_toMessages);
    }
    return _tutorMessagesStream!;
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
