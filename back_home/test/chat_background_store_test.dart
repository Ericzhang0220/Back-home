import 'dart:io';
import 'dart:typed_data';

import 'package:back_home/chat/chat_background_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory folder;
  late ChatBackgroundStore store;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    folder = await Directory.systemTemp.createTemp('chat-background-test-');
    store = ChatBackgroundStore(directory: () async => folder);
  });
  tearDown(() async => folder.delete(recursive: true));

  Future<ChatBackgroundChoice> load({
    String uid = 'me',
    bool isAi = true,
    String peer = '123456789',
  }) => store.load(uid: uid, isAi: isAi, peerId: peer);
  Future<ChatBackgroundChoice> save(
    ChatBackgroundMode mode, {
    Uint8List? bytes,
    String uid = 'me',
    bool isAi = true,
    String peer = '123456789',
  }) =>
      store.save(uid: uid, isAi: isAi, peerId: peer, mode: mode, photo: bytes);

  test('AI defaults to a portrait and human chats to plain', () async {
    expect((await load()).mode, ChatBackgroundMode.portrait);
    expect((await load(isAi: false)).mode, ChatBackgroundMode.plain);
  });

  test(
    'photo survives a new store and switching to plain removes only that image',
    () async {
      final bytes = Uint8List.fromList([1, 2, 3]);
      final choice = await save(ChatBackgroundMode.photo, bytes: bytes);
      expect(await File(choice.photoPath!).readAsBytes(), bytes);
      store = ChatBackgroundStore(directory: () async => folder);
      expect((await load()).photoPath, choice.photoPath);
      final other = await save(
        ChatBackgroundMode.photo,
        bytes: bytes,
        peer: 'other',
      );
      await save(ChatBackgroundMode.plain);
      expect((await load()).mode, ChatBackgroundMode.plain);
      expect(await File(choice.photoPath!).exists(), isFalse);
      expect(await File(other.photoPath!).exists(), isTrue);
    },
  );

  test(
    'equal AI and user IDs, other chats and accounts keep independent settings',
    () async {
      await save(ChatBackgroundMode.plain);
      await save(ChatBackgroundMode.portrait, isAi: false);
      expect((await load()).mode, ChatBackgroundMode.plain);
      expect((await load(isAi: false)).mode, ChatBackgroundMode.portrait);
      expect((await load(peer: 'other')).mode, ChatBackgroundMode.portrait);
      expect(
        (await load(uid: 'other-account')).mode,
        ChatBackgroundMode.portrait,
      );
    },
  );

  test(
    'invalid photo or failed filesystem write leaves the last choice intact',
    () async {
      final choice = await save(
        ChatBackgroundMode.photo,
        bytes: Uint8List.fromList([1, 2]),
      );
      await expectLater(
        save(ChatBackgroundMode.photo, bytes: Uint8List(0)),
        throwsArgumentError,
      );
      final blocker = File('${folder.path}/not-a-directory');
      await blocker.writeAsString('blocked');
      final failing = ChatBackgroundStore(
        directory: () async => Directory(blocker.path),
      );
      await expectLater(
        failing.save(
          uid: 'me',
          isAi: true,
          peerId: '123456789',
          mode: ChatBackgroundMode.photo,
          photo: Uint8List.fromList([3]),
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect((await load()).photoPath, choice.photoPath);
      expect(await File(choice.photoPath!).exists(), isTrue);
    },
  );

  test(
    'replacing a photo releases the old file; missing photos use the default',
    () async {
      final first = await save(
        ChatBackgroundMode.photo,
        bytes: Uint8List.fromList([1]),
      );
      final next = await save(
        ChatBackgroundMode.photo,
        bytes: Uint8List.fromList([2]),
      );
      expect(await File(first.photoPath!).exists(), isFalse);
      expect(await File(next.photoPath!).readAsBytes(), [2]);
      await File(next.photoPath!).delete();
      expect((await load()).mode, ChatBackgroundMode.portrait);
    },
  );
}
