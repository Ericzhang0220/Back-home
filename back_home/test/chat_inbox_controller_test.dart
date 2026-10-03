import 'dart:async';

import 'package:back_home/chat/chat_inbox_controller.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

class _Watch {
  _Watch(this.thread);
  final InboxThread thread;
  final values = StreamController<int>.broadcast(sync: true);
}

class _Source implements ChatInboxSource {
  final ai = StreamController<List<InboxThread>>.broadcast(sync: true);
  final human = StreamController<List<InboxThread>>.broadcast(sync: true);
  final watches = <_Watch>[];
  final reads = <(String, DateTime)>[];
  bool failRead = false;

  @override
  Stream<List<InboxThread>> watchAiThreads() => ai.stream;
  @override
  Stream<List<InboxThread>> watchHumanThreads() => human.stream;
  @override
  Stream<int> watchUnreadCount(InboxThread thread) {
    final watch = _Watch(thread);
    watches.add(watch);
    return watch.values.stream;
  }

  @override
  Future<void> markRead(String key, DateTime through) async {
    if (failRead) throw StateError('offline');
    reads.add((key, through));
  }

  _Watch latest(String key) =>
      watches.lastWhere((watch) => watch.thread.key == key);
  Future<void> close() async {
    await ai.close();
    await human.close();
    for (final watch in watches) {
      await watch.values.close();
    }
  }
}

void main() {
  final cursor = DateTime.utc(2026, 10, 3, 2);
  Map<String, dynamic> message(String sender, DateTime at, {bool ai = true}) =>
      {
        if (ai) 'role': sender else 'senderUid': sender,
        'text': 'Hello',
        'createdAt': Timestamp.fromDate(at),
      };

  test('unread includes only incoming messages after the displayed reply', () {
    final next = cursor.add(const Duration(seconds: 1));
    expect(
      isUnreadIncomingMessage(
        message('assistant', next),
        uid: 'me',
        isAi: true,
        readThrough: cursor,
      ),
      isTrue,
    );
    expect(
      isUnreadIncomingMessage(
        message('user', next),
        uid: 'me',
        isAi: true,
        readThrough: cursor,
      ),
      isFalse,
    );
    expect(
      isUnreadIncomingMessage(
        message('assistant', cursor),
        uid: 'me',
        isAi: true,
        readThrough: cursor,
      ),
      isFalse,
    );
    expect(
      isUnreadIncomingMessage(
        message('peer', next, ai: false),
        uid: 'me',
        isAi: false,
        readThrough: cursor,
      ),
      isTrue,
    );
    expect(
      isUnreadIncomingMessage(
        message('me', next, ai: false),
        uid: 'me',
        isAi: false,
        readThrough: cursor,
      ),
      isFalse,
    );
    expect(
      isUnreadIncomingMessage(
        {'text': 'Hello', 'role': 'assistant'},
        uid: 'me',
        isAi: true,
      ),
      isFalse,
    );
  });

  test(
    'AI and human counts stay live across preview updates and read cursors',
    () async {
      final source = _Source();
      final inbox = ChatInboxController(uid: 'me', source: source);
      addTearDown(() async {
        inbox.dispose();
        await source.close();
      });
      source.ai.add([
        const InboxThread(id: 'lily', peerId: 'lily', isAi: true),
      ]);
      source.human.add([
        const InboxThread(id: 'me_peer', peerId: 'peer', isAi: false),
      ]);
      source.latest('ai:lily').values.add(2);
      source.latest('human:me_peer').values.add(3);
      expect(inbox.aiCounts, {'lily': 2});
      expect(inbox.humanCounts, {'peer': 3});
      final watches = source.watches.length;
      // A changed lastMessage/updatedAt must not orphan the unread listener.
      source.ai.add([
        const InboxThread(id: 'lily', peerId: 'lily', isAi: true),
      ]);
      source.latest('ai:lily').values.add(4);
      expect(inbox.aiTotal, 4);
      expect(source.watches.length, watches);
      await inbox.markRead('ai:lily', cursor);
      source.ai.add([
        InboxThread(
          id: 'lily',
          peerId: 'lily',
          isAi: true,
          readThrough: cursor,
        ),
      ]);
      source.latest('ai:lily').values.add(1); // A newer unseen reply remains.
      expect(inbox.aiTotal, 1);
      expect(inbox.humanTotal, 3);
      source.human.add([]);
      expect(inbox.humanTotal, 0);
      expect(inbox.aiTotal, 1);
    },
  );

  test('read acknowledgements are monotonic and retry after failure', () async {
    final source = _Source();
    final inbox = ChatInboxController(uid: 'me', source: source);
    addTearDown(() async {
      inbox.dispose();
      await source.close();
    });
    await inbox.markRead('ai:lily', cursor);
    await inbox.markRead(
      'ai:lily',
      cursor.subtract(const Duration(seconds: 1)),
    );
    expect(source.reads.length, 1);
    final newer = cursor.add(const Duration(seconds: 5));
    source.ai.add([
      InboxThread(id: 'lily', peerId: 'lily', isAi: true, readThrough: newer),
    ]);
    await inbox.markRead('ai:lily', cursor.add(const Duration(seconds: 1)));
    expect(source.reads.length, 1);
    source.failRead = true;
    final newest = newer.add(const Duration(seconds: 1));
    await expectLater(inbox.markRead('ai:lily', newest), throwsStateError);
    source.failRead = false;
    await inbox.markRead('ai:lily', newest);
    expect(source.reads.last, ('ai:lily', newest));
  });
}
