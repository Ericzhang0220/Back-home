import 'package:back_home/widgets/chat_message_actions.dart';
import 'package:back_home/widgets/visible_chat_read_receipt.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('long press copies the complete message including newlines', (
    tester,
  ) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = call.arguments['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    const text = 'Hello Lily\n你好，今天怎么样？ 😊';
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: CopyableMessage(
              text: text,
              child: Padding(padding: EdgeInsets.all(20), child: Text(text)),
            ),
          ),
        ),
      ),
    );
    await tester.longPress(find.text(text));
    await tester.pumpAndSettle();
    expect(find.text('Copy'), findsOneWidget);
    expect(find.byType(CupertinoTextSelectionToolbar), findsOneWidget);
    expect(find.byType(PopupMenuItem<String>), findsNothing);
    await tester.tap(find.text('Copy'));
    await tester.pumpAndSettle();
    expect(copied, text);
    expect(find.text('Copy'), findsNothing);
    // The same bubble can open another menu after the first one was removed.
    await tester.longPress(find.text(text));
    await tester.pumpAndSettle();
    expect(find.text('Copy'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.text('Copy'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('unread badge hides zero and displays 99+ for large counts', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Row(
          children: [
            UnreadBadge(count: 0, child: Icon(Icons.person)),
            UnreadBadge(count: 5, child: Icon(Icons.person)),
            UnreadBadge(count: 123, child: Icon(Icons.person)),
          ],
        ),
      ),
    );
    expect(find.text('0'), findsNothing);
    expect(find.text('5'), findsOneWidget);
    expect(find.text('99+'), findsOneWidget);
  });

  testWidgets('read receipts wait for an active visible foreground chat', (
    tester,
  ) async {
    final seen = <DateTime>[];
    final first = DateTime.utc(2026, 10, 3, 2);
    Widget screen(bool active, DateTime at) => MaterialApp(
      home: Scaffold(
        body: VisibleChatReadReceipt(
          enabled: active,
          through: at,
          onRead: (value) async {
            seen.add(value);
          },
          child: const Center(child: Text('AI reply')),
        ),
      ),
    );
    await tester.pumpWidget(screen(false, first));
    expect(seen, isEmpty);
    await tester.pumpWidget(screen(true, first));
    await tester.pump();
    expect(seen, [first]);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    final next = first.add(const Duration(seconds: 1));
    await tester.pumpWidget(screen(true, next));
    expect(seen, [first]);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(seen, [first, next]);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('covered chat stays unread until its route is visible again', (
    tester,
  ) async {
    final seen = <DateTime>[];
    final at = ValueNotifier(DateTime.utc(2026, 10, 3));
    addTearDown(at.dispose);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: Scaffold(
          body: ValueListenableBuilder<DateTime>(
            valueListenable: at,
            builder: (context, time, _) => VisibleChatReadReceipt(
              through: time,
              onRead: (value) async {
                seen.add(value);
              },
              child: const Text('Reply'),
            ),
          ),
        ),
      ),
    );
    expect(seen.length, 1);
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Other screen')),
      ),
    );
    await tester.pumpAndSettle();
    final next = at.value.add(const Duration(seconds: 1));
    at.value = next;
    await tester.pump();
    expect(seen.length, 1);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(seen, [at.value.subtract(const Duration(seconds: 1)), next]);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('clipped messages stay unread until scrolled into view', (
    tester,
  ) async {
    final seen = <DateTime>[];
    final at = DateTime.utc(2026, 10, 3);
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              height: 120,
              child: SingleChildScrollView(
                controller: controller,
                child: Column(
                  children: [
                    const SizedBox(height: 240),
                    VisibleChatReadReceipt(
                      through: at,
                      onRead: (value) async {
                        seen.add(value);
                      },
                      child: const SizedBox(height: 40, child: Text('Reply')),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(seen, isEmpty);
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(seen, [at]);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
