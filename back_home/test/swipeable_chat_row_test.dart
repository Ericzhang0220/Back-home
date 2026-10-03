import 'dart:async';

import 'package:back_home/widgets/swipeable_chat_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('right swipe reveals Delete, tap alone performs the action', (tester) async {
    var deleted = 0;
    var opened = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Align(
      alignment: Alignment.topCenter,
      child: SwipeableChatRow(
        onDelete: () async { deleted++; },
        child: ListTile(title: const Text('Lily'), onTap: () { opened++; }),
      ),
    ))));
    await tester.tap(find.text('Lily'));
    expect(opened, 1);
    await tester.drag(find.text('Lily'), const Offset(-100, 0));
    await tester.pumpAndSettle();
    expect(find.text('Delete'), findsNothing);
    await tester.drag(find.text('Lily'), const Offset(100, 0));
    await tester.pumpAndSettle();
    expect(find.text('Delete'), findsOneWidget);
    expect(deleted, 0);
    // Tapping an open row closes its action without opening the conversation.
    await tester.tap(find.text('Lily'));
    await tester.pumpAndSettle();
    expect(opened, 1);
    expect(find.text('Delete'), findsNothing);
    await tester.drag(find.text('Lily'), const Offset(100, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(deleted, 1);
    expect(find.text('Delete'), findsNothing);
  });

  testWidgets('delete runs once and recovers from a failed request', (tester) async {
    final pending = Completer<void>();
    var requests = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SwipeableChatRow(
      onDelete: () { requests++; return pending.future; },
      child: const SizedBox(height: 80, child: Text('Lily')),
    ))));
    await tester.drag(find.text('Lily'), const Offset(100, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pump();
    expect(requests, 1);
    pending.completeError(StateError('offline'));
    await tester.pumpAndSettle();
    expect(find.text('Delete'), findsNothing);
    expect(find.text('Could not delete the chat. Please try again.'), findsOneWidget);
  });
}
