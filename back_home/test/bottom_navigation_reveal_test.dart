import 'package:back_home/widgets/bottom_navigation_reveal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'bottom text field receives taps and double taps; swipe reveals',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 850));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      var reveals = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: BottomNavigationReveal(
            enabled: true,
            allowDoubleTap: true,
            bottomGap: 34,
            onReveal: () => reveals++,
            child: Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 46),
                  child: TextField(controller: controller),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'Hello wonderful world');
      // Let the earlier focus tap expire before starting a fresh double tap.
      await tester.pump(const Duration(milliseconds: 500));
      final editable = tester.state<EditableTextState>(
        find.byType(EditableText),
      );
      expect(editable.widget.focusNode.hasFocus, isTrue);
      final caret = editable.renderEditable.getLocalRectForCaret(
        const TextPosition(offset: 9),
      );
      final point = editable.renderEditable.localToGlobal(caret.center);
      await tester.tapAt(point);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tapAt(point);
      await tester.pumpAndSettle();
      expect(reveals, 0);
      expect(controller.selection.textInside(controller.text), 'wonderful');

      await tester.dragFrom(const Offset(370, 790), const Offset(0, -100));
      await tester.pump();
      expect(reveals, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets('reveal requires an enabled upward swipe from the bottom zone', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var reveals = 0;
    Widget screen(bool enabled) => MaterialApp(
      home: BottomNavigationReveal(
        enabled: enabled,
        bottomGap: 34,
        onReveal: () => reveals++,
        child: const Scaffold(body: ColoredBox(color: Colors.white)),
      ),
    );
    await tester.pumpWidget(screen(true));
    await tester.dragFrom(const Offset(200, 790), const Offset(0, 40));
    await tester.dragFrom(const Offset(200, 790), const Offset(100, 0));
    await tester.dragFrom(const Offset(200, 500), const Offset(0, -100));
    await tester.dragFrom(const Offset(200, 840), const Offset(0, -100));
    expect(reveals, 0);
    await tester.pumpWidget(screen(false));
    await tester.dragFrom(const Offset(200, 790), const Offset(0, -100));
    expect(reveals, 0);
    await tester.pumpWidget(screen(true));
    await tester.dragFrom(const Offset(200, 790), const Offset(0, -100));
    expect(reveals, 1);
  });

  testWidgets(
    'optional double tap reveals anywhere without taking child taps',
    (tester) async {
      var reveals = 0;
      var presses = 0;
      Widget screen(bool doubleTap) => MaterialApp(
        home: BottomNavigationReveal(
          enabled: true,
          allowDoubleTap: doubleTap,
          bottomGap: 34,
          onReveal: () => reveals++,
          child: Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => presses++,
                child: const Text('Page button'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpWidget(screen(true));
      await tester.tap(find.text('Page button'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('Page button'));
      expect(reveals, 1);
      expect(presses, 2);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tapAt(const Offset(30, 200));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tapAt(const Offset(30, 200));
      expect(reveals, 1);
      await tester.pumpWidget(screen(false));
      await tester.tapAt(const Offset(30, 200));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tapAt(const Offset(30, 200));
      expect(reveals, 1);
    },
  );
}
