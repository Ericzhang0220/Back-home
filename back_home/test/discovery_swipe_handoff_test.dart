import 'dart:async';

import 'package:back_home/screens/chat_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Card extends StatefulWidget {
  _Card(this.id, this.starts) : super(key: ValueKey(id));
  final String id;
  final Map<String, int> starts;

  @override
  State<_Card> createState() => _CardState();
}

class _CardState extends State<_Card> {
  @override
  void initState() {
    super.initState();
    widget.starts.update(widget.id, (count) => count + 1, ifAbsent: () => 1);
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: switch (widget.id) {
      'a' => Colors.red,
      'b' => Colors.blue,
      _ => Colors.green,
    },
    child: Center(child: Text(widget.id)),
  );
}

void main() {
  for (final delayed in [false, true]) {
    testWidgets('swipe enters its preview without remounting or flashing back '
        '(delayed selection: $delayed)', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final selection = ValueNotifier(0);
      addTearDown(selection.dispose);
      final starts = <String, int>{};
      const ids = ['a', 'b', 'c'];
      var commits = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder<int>(
              valueListenable: selection,
              builder: (_, index, _) => SwipeableDiscoveryDeck(
                cardKey: ids[index],
                frontCard: _Card(ids[index], starts),
                previousCard: index == 0 ? null : _Card(ids[index - 1], starts),
                nextCard: index == ids.length - 1
                    ? null
                    : _Card(ids[index + 1], starts),
                enabled: true,
                onSwiped: (direction) {
                  commits++;
                  if (delayed) {
                    Timer(const Duration(milliseconds: 80), () {
                      selection.value += direction;
                    });
                  } else {
                    selection.value += direction;
                  }
                },
              ),
            ),
          ),
        ),
      );
      final previewState = tester.state(find.byKey(const ValueKey('b')));
      await tester.dragFrom(const Offset(200, 350), const Offset(-240, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 240));
      expect(commits, 1);

      if (delayed) {
        // The old card must remain offscreen while the parent commits the ID.
        expect(
          tester.getRect(find.byKey(const ValueKey('a'))).right,
          lessThan(0),
        );
        expect(
          tester.getRect(find.byKey(const ValueKey('b'))),
          const Rect.fromLTWH(0, 0, 400, 700),
        );
        await tester.pump(const Duration(milliseconds: 80));
      }
      await tester.pumpAndSettle();
      expect(selection.value, 1);
      expect(tester.state(find.byKey(const ValueKey('b'))), same(previewState));
      expect(starts['b'], 1);
      expect(
        tester.getRect(find.byKey(const ValueKey('b'))),
        const Rect.fromLTWH(0, 0, 400, 700),
      );

      await tester.dragFrom(const Offset(200, 350), const Offset(240, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 240));
      if (delayed) await tester.pump(const Duration(milliseconds: 80));
      await tester.pumpAndSettle();
      expect(selection.value, 0);
      expect(commits, 2);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets(
    'the start and end bounce back without wrapping to another person',
    (tester) async {
      var commits = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SwipeableDiscoveryDeck(
              cardKey: 'only',
              frontCard: _Card('only', {}),
              previousCard: null,
              nextCard: null,
              onSwiped: (_) => commits++,
              enabled: true,
            ),
          ),
        ),
      );
      final card = find.byKey(const ValueKey('only'));
      final initial = tester.getRect(card);
      for (final dx in [-240.0, 240.0]) {
        await tester.drag(card, Offset(dx, 0));
        await tester.pumpAndSettle();
        expect(tester.getRect(card), initial);
        expect(commits, 0);
      }
      expect(tester.takeException(), isNull);
    },
  );
}
