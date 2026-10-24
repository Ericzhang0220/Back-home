// SDK references are substituted only to open the real conversation route.
// ignore_for_file: subtype_of_sealed_class
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:back_home/chat/ai_character_photo.dart';
import 'package:back_home/chat/ai_chat_repository.dart';
import 'package:back_home/chat/ai_models.dart';
import 'package:back_home/chat/character_share.dart';
import 'package:back_home/chat/chat_background_store.dart';
import 'package:back_home/screens/chat_screen.dart';
import 'package:back_home/widgets/character_portrait.dart';
import 'package:back_home/widgets/chat_background.dart';
import 'package:back_home/widgets/fullscreen_photo_viewer.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Firestore implements FirebaseFirestore {
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

class _Repository extends AiChatRepository {
  _Repository(this.character)
    : super(
        uid: 'me',
        firestore: _Firestore(),
        functions: _Functions(),
        storage: _Storage(),
      );
  AiCharacter character;
  final changes = StreamController<AiCharacter?>.broadcast();
  int messageSubscriptions = 0;
  List<AiMessage> messages = const [];
  int shares = 0;
  int sharedReplies = 0;
  bool failShare = false;
  String? requestId;
  String? sharedNote;
  Completer<void>? friendUpdate;
  bool failFriendUpdate = false;
  final friendWrites = <bool>[];
  @override
  Future<void> addCharacterAsFriend(String id) => _changeFriend(true);
  @override
  Future<void> removeCharacterAsFriend(String id) => _changeFriend(false);
  Future<void> _changeFriend(bool value) async {
    friendWrites.add(value);
    if (failFriendUpdate) throw const AiChatException('Friend update failed');
    character = AiCharacter.fromData(
      id: character.id,
      data: {...character.toFirestore(), 'isFriend': value},
    );
    changes.add(character);
    await friendUpdate?.future;
  }

  @override
  Future<List<CharacterShareRecipient>> loadShareRecipients(
    String sourceId,
  ) async => [
    CharacterShareRecipient(
      id: AiCharacter.presets.last.id,
      name: 'AI recipient',
      isAi: true,
      character: AiCharacter.presets.last,
    ),
    const CharacterShareRecipient(
      id: 'friend',
      name: 'Human recipient',
      isAi: false,
    ),
  ];
  @override
  String newShareRequestId() => 'request';
  @override
  Future<void> shareCharacter({
    required String characterId,
    required CharacterShareRecipient recipient,
    required String requestId,
    String note = '',
  }) async {
    shares++;
    this.requestId = requestId;
    sharedNote = note;
    if (failShare) throw const AiChatException('Try again');
  }

  @override
  Future<void> replyToSharedCharacter(String id) async {
    sharedReplies++;
  }

  @override
  Stream<AiCharacter?> watchCharacter(String characterId) => changes.stream;
  @override
  Stream<List<AiMessage>> watchCharacterMessages(String characterId) {
    messageSubscriptions++;
    return Stream.value(messages);
  }

  @override
  Future<void> updateCharacterDetails({
    required String characterId,
    required String name,
    required String personality,
  }) async {
    character = AiCharacter.fromData(
      id: characterId,
      data: {
        ...character.toFirestore(),
        'name': name,
        'personality': personality,
      },
    );
    changes.add(character);
  }
}

class _Backgrounds extends ChatBackgroundStore {
  ChatBackgroundChoice? value;
  int saves = 0;
  Uint8List? photo;
  @override
  Future<ChatBackgroundChoice> load({
    required String uid,
    required bool isAi,
    required String peerId,
  }) async =>
      value ??
      ChatBackgroundChoice(
        isAi ? ChatBackgroundMode.portrait : ChatBackgroundMode.plain,
      );
  @override
  Future<ChatBackgroundChoice> save({
    required String uid,
    required bool isAi,
    required String peerId,
    required ChatBackgroundMode mode,
    Uint8List? photo,
  }) async {
    saves++;
    this.photo = photo;
    return value = ChatBackgroundChoice(mode);
  }
}

void main() {
  final custom = AiCharacter.fromData(
    id: 'custom',
    data: {
      'name': 'Eric',
      'personality': 'Kind and curious',
      'isCustom': true,
      'authorUid': 'me',
    },
  );
  final photo = AiCharacterPhoto(
    bytes: base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==',
    ),
    contentType: 'image/png',
  );
  late _Repository repository;
  late _Backgrounds backgrounds;
  late ValueNotifier<MediaQueryData> media;

  Future<void> open(
    WidgetTester tester, {
    AiCharacter? character,
    Future<AiCharacterPhoto?> Function()? picker,
    List<AiMessage> messages = const [],
  }) async {
    repository = _Repository(character ?? custom);
    repository.messages = messages;
    backgrounds = _Backgrounds();
    media = ValueNotifier(
      const MediaQueryData(
        size: Size(390, 844),
        padding: EdgeInsets.only(top: 47, bottom: 34),
        viewPadding: EdgeInsets.only(top: 47, bottom: 34),
      ),
    );
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await repository.changes.close();
      media.dispose();
      await tester.binding.setSurfaceSize(null);
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.iOS),
        builder: (context, child) => ValueListenableBuilder(
          valueListenable: media,
          builder: (_, value, _) => MediaQuery(data: value, child: child!),
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => openAiCharacterConversation(
                context,
                character: repository.character,
                repository: repository,
                backgroundStore: backgrounds,
                pickBackgroundPhoto: picker ?? () async => photo,
                onEditPhoto: () async {},
              ),
              child: const Text('Open chat'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open chat'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'own character is edited from its profile without a duplicate toolbar icon',
    (tester) async {
      await open(tester);
      expect(find.byIcon(Icons.info_outline_rounded), findsNothing);
      expect(find.byTooltip('Edit character'), findsNothing);
      expect(find.byTooltip('Chat background'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Keep this draft');
      await tester.tap(find.text(repository.character.name));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit character'));
      await tester.pumpAndSettle();
      expect(find.text('Edit AI character'), findsOneWidget);
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.first, 'Nova');
      await tester.enterText(fields.last, 'Talkative and thoughtful');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      Navigator.of(tester.element(find.text('Edit character'))).pop();
      await tester.pumpAndSettle();
      expect(find.text('Nova'), findsOneWidget);
      expect(repository.character.personality, 'Talkative and thoughtful');
      expect(find.text('Keep this draft'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('profile opened after an avatar change uses the latest photo', (
    tester,
  ) async {
    await open(tester);
    const newPhoto = 'https://example.invalid/updated-avatar.png';
    repository.character = AiCharacter.fromData(
      id: custom.id,
      data: {...custom.toFirestore(), 'avatarUrl': newPhoto},
    );
    repository.changes.add(repository.character);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<CharacterPortrait>(find.byType(CharacterPortrait).first)
          .photoUrl,
      newPhoto,
    );
    await tester.tap(find.text('Eric'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<CharacterPortrait>(find.byType(CharacterPortrait).last)
          .photoUrl,
      newPhoto,
    );
    await tester.tap(find.byType(CharacterPortrait).last);
    await tester.pumpAndSettle();
    expect(find.byType(FullscreenPhotoViewer), findsOneWidget);
    final viewer = tester.widget<FullscreenPhotoViewer>(
      find.byType(FullscreenPhotoViewer),
    );
    expect((viewer.image as NetworkImage).url, newPhoto);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'preset profile remains accessible from name; photo still opens fullscreen',
    (tester) async {
      await open(tester, character: AiCharacter.presets.first);
      expect(find.byTooltip('Edit character'), findsNothing);
      expect(find.byTooltip('Share character'), findsOneWidget);
      expect(find.byIcon(Icons.favorite_rounded), findsNothing);
      expect(find.byIcon(Icons.favorite_border_rounded), findsNothing);
      expect(find.byIcon(Icons.info_outline_rounded), findsNothing);
      expect(
        tester.widget<ChatBackground>(find.byType(ChatBackground)).choice.mode,
        ChatBackgroundMode.portrait,
      );
      await tester.tap(find.text(repository.character.name));
      await tester.pumpAndSettle();
      expect(find.text('AI ID'), findsOneWidget);
      expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);
      final profilePhoto = find.byType(CharacterPortrait).last;
      final name = find.text(repository.character.name).last;
      expect(
        tester.getTopLeft(profilePhoto).dx,
        lessThan(tester.getTopLeft(name).dx),
      );
      expect(
        tester
            .widget<Text>(find.text(repository.character.personality))
            .textAlign,
        TextAlign.left,
      );
      await tester.tap(find.byType(CharacterPortrait).last);
      await tester.pumpAndSettle();
      expect(find.byType(FullscreenPhotoViewer), findsOneWidget);
      await tester.drag(find.byType(InteractiveViewer), const Offset(0, 160));
      await tester.pumpAndSettle();
      expect(find.byType(FullscreenPhotoViewer), findsNothing);
      expect(find.text('AI ID'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'background choices preserve the draft and do not reload the conversation',
    (tester) async {
      await open(tester, character: AiCharacter.presets.first);
      await tester.enterText(find.byType(TextField), 'Draft');
      await tester.tap(find.byTooltip('Chat background'));
      await tester.pumpAndSettle();
      expect(find.text('Plain background'), findsNothing);
      expect(find.text('Character photo'), findsOneWidget);
      expect(find.text('Choose from Photos'), findsOneWidget);
      await tester.tap(find.text('Character photo'));
      await tester.pumpAndSettle();
      expect(backgrounds.value!.mode, ChatBackgroundMode.portrait);
      await tester.tap(find.byTooltip('Chat background'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose from Photos'));
      await tester.pumpAndSettle();
      expect(backgrounds.value!.mode, ChatBackgroundMode.photo);
      expect(backgrounds.photo, photo.bytes);
      expect(repository.messageSubscriptions, 1);
      expect(find.text('Draft'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('canceling the photo picker keeps the existing background', (
    tester,
  ) async {
    await open(tester, picker: () async => null);
    await tester.tap(find.byTooltip('Chat background'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose from Photos'));
    await tester.pumpAndSettle();
    expect(backgrounds.saves, 0);
    expect(
      tester.widget<ChatBackground>(find.byType(ChatBackground)).choice.mode,
      ChatBackgroundMode.portrait,
    );
  });

  testWidgets('share to a human retries without losing selection or note', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.byTooltip('Share character'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('People'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Human recipient'));
    await tester.pumpAndSettle();
    expect(find.text('Send to'), findsOneWidget);
    expect(find.text('Add a message (optional)'), findsOneWidget);
    expect(find.text('What do you think of this character?'), findsNothing);
    await tester.enterText(find.byType(TextField).last, 'Meet Ava');
    repository.failShare = true;
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('Meet Ava'), findsOneWidget);
    repository.failShare = false;
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    expect(repository.shares, 2);
    expect(repository.requestId, 'request');
    expect(repository.sharedNote, 'Meet Ava');
    expect(repository.sharedReplies, 0);
    expect(
      find.text('Character card sent to Human recipient.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'sharing to AI opens recipient conversation and requests one reply',
    (tester) async {
      await open(tester);
      await tester.tap(find.byTooltip('Share character'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('AI recipient'));
      await tester.pumpAndSettle();
      expect(find.text('Send to'), findsOneWidget);
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();
      expect(repository.shares, 1);
      expect(repository.sharedReplies, 1);
      expect(repository.sharedNote, '');
      expect(find.text(AiCharacter.presets.last.name), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'profile heart can toggle repeatedly while the first save is pending',
    (tester) async {
      await open(tester, character: AiCharacter.presets.first);
      await tester.tap(find.text(repository.character.name));
      await tester.pumpAndSettle();
      repository.friendUpdate = Completer<void>();
      await tester.tap(find.byTooltip('Add to AI friends'));
      await tester.pump();
      expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.favorite_rounded),
            )
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.byTooltip('Remove from AI friends'));
      await tester.pump();
      expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);
      expect(repository.friendWrites, [true]);
      repository.friendUpdate!.complete();
      await tester.pumpAndSettle();
      expect(repository.friendWrites, [true, false]);
      expect(
        tester
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.favorite_border_rounded),
            )
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.byTooltip('Add to AI friends'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Remove from AI friends'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);
      await tester.tap(find.byTooltip('Add to AI friends'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
      expect(repository.friendWrites, [true, false, true, false, true]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('latest heart choice is saved even after closing the profile', (
    tester,
  ) async {
    await open(tester, character: AiCharacter.presets.first);
    await tester.tap(find.text(repository.character.name));
    await tester.pumpAndSettle();
    repository.friendUpdate = Completer<void>();
    await tester.tap(find.byTooltip('Add to AI friends'));
    await tester.pump();
    await tester.tap(find.byTooltip('Remove from AI friends'));
    await tester.pump();
    Navigator.of(tester.element(find.byTooltip('Add to AI friends'))).pop();
    await tester.pumpAndSettle();
    repository.friendUpdate!.complete();
    await tester.pumpAndSettle();
    expect(repository.friendWrites, [true, false]);
    expect(repository.character.isFriend, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('share picker fits above the phone keyboard', (tester) async {
    await open(tester);
    await tester.tap(find.byTooltip('Share character'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('AI recipient'));
    await tester.pumpAndSettle();
    media.value = media.value.copyWith(
      viewInsets: const EdgeInsets.only(bottom: 300),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getBottomRight(find.widgetWithText(FilledButton, 'Send')).dy,
      lessThanOrEqualTo(844 - 300),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'failed heart save rolls back and allows retry in the same profile',
    (tester) async {
      await open(tester, character: AiCharacter.presets.first);
      await tester.tap(find.text(repository.character.name));
      await tester.pumpAndSettle();
      repository.failFriendUpdate = true;
      await tester.tap(find.byTooltip('Add to AI friends'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Add to AI friends'), findsOneWidget);
      expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);
      repository.failFriendUpdate = false;
      await tester.tap(find.byTooltip('Add to AI friends'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Remove from AI friends'), findsOneWidget);
      expect(repository.character.isFriend, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('forward confirmation can be canceled without sending', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.byTooltip('Share character'));
    await tester.pumpAndSettle();
    expect(find.text('Add a message (optional)'), findsNothing);
    await tester.tap(find.text('AI recipient'));
    await tester.pumpAndSettle();
    expect(find.text('Send to'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(repository.shares, 0);
    expect(find.text('Select chat'), findsOneWidget);
    expect(find.text('Send to'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shared character card renders its photo, name and AI ID', (
    tester,
  ) async {
    final character = AiCharacter.presets.first;
    await open(
      tester,
      messages: [
        AiMessage(
          id: 'card',
          isUser: true,
          text: 'How do you feel about her?',
          sharedCharacter: SharedAiCharacter(character),
        ),
      ],
    );
    expect(find.text(character.name), findsOneWidget);
    expect(find.text('AI character · ${character.publicId}'), findsOneWidget);
    expect(find.text('Tap to chat'), findsOneWidget);
    expect(find.text('How do you feel about her?'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'composer uses the former bottom gap and stays above the keyboard',
    (tester) async {
      await open(tester);
      expect(844 - tester.getBottomRight(find.byType(TextField)).dy, 24);
      final backgroundBottom = tester
          .getBottomRight(find.byType(ChatBackground))
          .dy;
      expect(backgroundBottom, 844);
      media.value = media.value.copyWith(
        padding: const EdgeInsets.only(top: 47),
        viewInsets: const EdgeInsets.only(bottom: 280),
      );
      await tester.pumpAndSettle();
      expect(tester.getBottomRight(find.byType(TextField)).dy, 844 - 280 - 14);
      expect(tester.takeException(), isNull);
    },
  );
}
