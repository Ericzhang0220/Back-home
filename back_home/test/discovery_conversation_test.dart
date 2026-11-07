import 'dart:async';

import 'package:back_home/chat/ai_chat_repository.dart';
import 'package:back_home/chat/ai_discovery_recommender.dart';
import 'package:back_home/chat/ai_models.dart';
import 'package:back_home/chat/discovery_conversation.dart';
import 'package:back_home/screens/chat_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _DiscoveryRepository implements AiChatRepository {
  final sends = <(String, String)>[];
  final replies = <String, Completer<void>>{};

  @override
  String get uid => 'me';

  @override
  Stream<List<AiCharacter>> watchCharacters() => Stream.value([
    AiCharacter.fromData(id: 'ava', data: {'name': 'Ava'}),
    AiCharacter.fromData(id: 'mason', data: {'name': 'Mason'}),
  ]);

  @override
  Stream<List<AiCharacter>> watchPublicCharacters() => Stream.value([]);

  @override
  Stream<Map<String, AiCharacterInteraction>> watchDiscoveryInteractions() =>
      Stream.value({});

  @override
  Stream<List<AiMessage>> watchCharacterPreviewMessages(String characterId) =>
      Stream.value([]);

  @override
  Future<void> sendToCharacter({
    required String characterId,
    required String text,
  }) {
    sends.add((characterId, text));
    return (replies[characterId] = Completer<void>()).future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Messages {
  final sources = <String, StreamController<List<String>>>{};
  final starts = <String, int>{};
  final stops = <String, int>{};

  Stream<List<String>> watch(String id) => sources
      .putIfAbsent(
        id,
        () => StreamController<List<String>>.broadcast(
          sync: true,
          onListen: () => starts[id] = (starts[id] ?? 0) + 1,
          onCancel: () => stops[id] = (stops[id] ?? 0) + 1,
        ),
      )
      .stream;

  void reply(String id, String text) => sources[id]!.add([text]);

  Future<void> close() async {
    for (final stream in sources.values) {
      await stream.close();
    }
  }
}

Widget _conversation(DiscoveryConversationCache<String> cache, String id) =>
    DiscoveryConversation<String>(
      key: ValueKey(id),
      cache: cache,
      conversationId: id,
      builder: (context, messages) => ColoredBox(
        color: id == 'ava' ? Colors.orange : Colors.blue,
        child: Center(child: Text('$id:${messages.join()}')),
      ),
    );

void main() {
  testWidgets('AI discovery swipes with a draft and while a reply is pending', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 850);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetViewInsets);
    final repository = _DiscoveryRepository();
    final deck = AiDiscoveryDeck();
    final selected = ValueNotifier<String?>('ava');
    final drafts = <String, TextEditingController>{};
    addTearDown(selected.dispose);
    addTearDown(() {
      for (final draft in drafts.values) {
        draft.dispose();
      }
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ValueListenableBuilder(
              valueListenable: selected,
              builder: (_, id, _) => AiDiscoveryPage(
                repository: repository,
                recommendationDeck: deck,
                characterId: id,
                onCharacterChanged: (id) => selected.value = id,
                onToggleFriend: (_, {required isSharedTemplate}) async {},
                keyboardOpen: MediaQuery.viewInsetsOf(context).bottom > 0,
                draftFor: (id) =>
                    drafts.putIfAbsent(id, TextEditingController.new),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final field = find.byType(TextField);
    String draft() => tester.widget<TextField>(field).controller!.text;
    Future<void> swipe(double dx) async {
      await tester.dragFrom(const Offset(200, 280), Offset(dx, 0));
      await tester.pump();
      // A pending reply animates its typing indicator indefinitely.
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
    }

    await tester.enterText(field, 'Hi Ava');
    final focus = tester
        .widget<EditableText>(find.byType(EditableText))
        .focusNode;
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pump();
    expect(focus.hasFocus, isTrue);
    await swipe(-240);
    expect(selected.value, 'mason');
    expect(focus.hasFocus, isFalse);
    expect(draft(), isEmpty);
    tester.view.resetViewInsets();
    await tester.pumpAndSettle();
    await swipe(240);
    expect(selected.value, 'ava');
    expect(draft(), 'Hi Ava');

    await tester.tap(find.byTooltip('Send').hitTestable());
    await tester.pump();
    expect(repository.sends, [('ava', 'Hi Ava')]);
    expect(tester.widget<TextField>(field).enabled, isFalse);

    await swipe(-240);
    expect(selected.value, 'mason');
    expect(tester.widget<TextField>(field).enabled, isTrue);
    await tester.enterText(field, 'Hi Mason');
    await tester.tap(find.byTooltip('Send').hitTestable());
    await tester.pump();
    expect(repository.sends, [('ava', 'Hi Ava'), ('mason', 'Hi Mason')]);
    repository.replies['mason']!.complete();
    await tester.pump();
    expect(tester.widget<TextField>(field).enabled, isTrue);

    await swipe(240);
    expect(selected.value, 'ava');
    expect(tester.widget<TextField>(field).enabled, isFalse);
    repository.replies['ava']!.complete();
    await tester.pump();
    expect(tester.widget<TextField>(field).enabled, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: const TargetPlatformVariant({TargetPlatform.iOS}));

  testWidgets('both neighbours preload and off-deck listeners are released', (
    tester,
  ) async {
    final source = _Messages();
    final cache = DiscoveryConversationCache<String>(watch: source.watch);
    addTearDown(() async {
      cache.dispose();
      await source.close();
    });
    cache.preload(['ava', 'mason', 'lily']);
    source.reply('lily', 'READY BEFORE RIGHT SWIPE');
    source.reply('mason', 'READY BEFORE LEFT SWIPE');
    expect(source.starts, {'ava': 1, 'mason': 1, 'lily': 1});
    await tester.pumpWidget(MaterialApp(home: _conversation(cache, 'lily')));
    expect(find.text('lily:READY BEFORE RIGHT SWIPE'), findsOneWidget);
    cache.preload(['lily', 'noah', 'ava']);
    await tester.pump();
    expect(source.stops['mason'], 1);
    expect(source.stops['lily'], isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    cache.preload([]);
    await tester.pump();
    expect(source.stops['lily'], 1);
    expect(source.stops['ava'], 1);
    expect(source.stops['noah'], 1);
  });

  testWidgets('a new character never inherits the last character history', (
    tester,
  ) async {
    final source = _Messages();
    final cache = DiscoveryConversationCache<String>(watch: source.watch);
    addTearDown(() async {
      cache.dispose();
      await source.close();
    });
    Widget screen(String id) => MaterialApp(
      home: DiscoveryConversation<String>(
        cache: cache,
        conversationId: id,
        builder: (context, messages) => Text('$id:${messages.join()}'),
      ),
    );
    await tester.pumpWidget(screen('ava'));
    source.reply('ava', 'AVA PRIVATE HISTORY');
    await tester.pump();
    expect(find.text('ava:AVA PRIVATE HISTORY'), findsOneWidget);

    // Reuse the widget state, as switching the original StreamBuilder did.
    await tester.pumpWidget(screen('mason'));
    expect(find.textContaining('AVA PRIVATE HISTORY'), findsNothing);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('mason:'), findsOneWidget);
    source.reply('mason', 'MASON HISTORY');
    await tester.pump();
    expect(find.text('mason:MASON HISTORY'), findsOneWidget);
    await tester.pumpWidget(screen('ava'));
    expect(find.text('ava:AVA PRIVATE HISTORY'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('swiping promotes a preview with its history already loaded', (
    tester,
  ) async {
    final source = _Messages();
    final cache = DiscoveryConversationCache<String>(watch: source.watch);
    addTearDown(() async {
      cache.dispose();
      await source.close();
    });
    final front = ValueNotifier('ava');
    addTearDown(front.dispose);
    await tester.binding.setSurfaceSize(const Size(400, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<String>(
          valueListenable: front,
          builder: (context, id, _) => SwipeableDiscoveryDeck(
            cardKey: id,
            frontCard: _conversation(cache, id),
            previousCard: _conversation(cache, id == 'ava' ? 'mason' : 'ava'),
            nextCard: _conversation(cache, id == 'ava' ? 'mason' : 'ava'),
            onSwiped: (_) => front.value = id == 'ava' ? 'mason' : 'ava',
          ),
        ),
      ),
    );
    source.reply('ava', 'AVA HISTORY');
    source.reply('mason', 'MASON HISTORY');
    await tester.pump();
    expect(source.starts, {'ava': 1, 'mason': 1});
    final gesture = await tester.startGesture(const Offset(200, 350));
    await gesture.moveBy(const Offset(-30, 0));
    await gesture.moveBy(const Offset(-140, 0));
    await tester.pump();
    expect(find.text('mason:MASON HISTORY'), findsOneWidget);
    await gesture.up();
    // Inspect every animation frame, including the first frame after commit.
    for (var frame = 0; frame < 24; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.text('mason:'), findsNothing);
      expect(find.text('mason:AVA HISTORY'), findsNothing);
      expect(find.text('mason:MASON HISTORY'), findsOneWidget);
    }
    expect(front.value, 'mason');
    expect(source.starts, {'ava': 1, 'mason': 1});
    source.reply('mason', 'NEW MASON REPLY');
    await tester.pump();
    expect(find.text('mason:NEW MASON REPLY'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(source.stops, {'ava': 1, 'mason': 1});
  });

  testWidgets('a different account starts with its own message cache', (
    tester,
  ) async {
    final first = _Messages();
    final second = _Messages();
    final a = DiscoveryConversationCache<String>(watch: first.watch);
    final b = DiscoveryConversationCache<String>(watch: second.watch);
    addTearDown(() async {
      a.dispose();
      b.dispose();
      await first.close();
      await second.close();
    });
    Widget screen(DiscoveryConversationCache<String> cache) =>
        MaterialApp(home: _conversation(cache, 'ava'));
    await tester.pumpWidget(screen(a));
    first.reply('ava', 'FIRST ACCOUNT');
    await tester.pump();
    a.dispose();
    await tester.pumpWidget(screen(b));
    expect(find.textContaining('FIRST ACCOUNT'), findsNothing);
    second.reply('ava', 'SECOND ACCOUNT');
    await tester.pump();
    expect(find.text('ava:SECOND ACCOUNT'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
