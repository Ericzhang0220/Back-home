import 'package:back_home/chat/discovery_card_content.dart';
import 'package:back_home/screens/chat_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('composer stays above keyboard as a draft grows', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 850);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetViewInsets);
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: DiscoveryCardContent(
              keyboardOpen: MediaQuery.viewInsetsOf(context).bottom > 0,
              conversation: const Text('Recent reply'),
              controller: controller,
              isReplying: false,
              onSendMessage: () {},
            ),
          ),
        ),
      ),
    );

    final field = find.byType(TextField);
    final browsingTop = tester.getTopLeft(field).dy;
    await tester.enterText(field, 'A draft in progress');
    controller.selection = const TextSelection.collapsed(offset: 7);
    await tester.pump();
    final editingState = tester.state<EditableTextState>(
      find.byType(EditableText),
    );
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pump();
    expect(
      tester.state<EditableTextState>(find.byType(EditableText)),
      same(editingState),
    );
    expect(editingState.widget.focusNode.hasFocus, isTrue);
    expect(controller.selection.baseOffset, 7);
    expect(tester.getBottomLeft(field).dy, closeTo(538, 1));
    expect(tester.getTopLeft(field).dy, lessThan(browsingTop));

    await tester.enterText(field, 'First line\nSecond line\nThird line');
    await tester.pump();
    expect(tester.getBottomLeft(field).dy, closeTo(538, 1));
    expect(tester.takeException(), isNull);

    tester.view.resetViewInsets();
    await tester.pump();
    expect(
      tester.state<EditableTextState>(find.byType(EditableText)),
      same(editingState),
    );
    expect(tester.getTopLeft(field).dy, closeTo(browsingTop, 1));
    expect(controller.text, 'First line\nSecond line\nThird line');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('long conversation scrolls while editing at phone sizes', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetViewInsets);
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    for (final size in [const Size(400, 850), const Size(320, 568)]) {
      tester.view.physicalSize = size;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: DiscoveryCardContent(
                keyboardOpen: MediaQuery.viewInsetsOf(context).bottom > 0,
                conversation: Column(
                  children: [
                    for (var i = 0; i < 12; i++)
                      SizedBox(height: 80, child: Text('Reply $i')),
                  ],
                ),
                controller: controller,
                isReplying: false,
                onSendMessage: () {},
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(
        tester.getBottomLeft(find.byType(TextField)).dy,
        closeTo(size.height - 312, 1),
      );
      expect(find.text('Reply 11').hitTestable(), findsOneWidget);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('only the front discovery card owns an editable draft', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'Hello friend');
    addTearDown(controller.dispose);
    Widget card({bool interactive = true}) => DiscoveryCardContent(
      keyboardOpen: false,
      conversation: const Text('Profile'),
      controller: controller,
      isReplying: false,
      isInteractive: interactive,
      onSendMessage: () {},
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SwipeableDiscoveryDeck(
            cardKey: 'front',
            frontCard: card(),
            previousCard: card(interactive: false),
            nextCard: card(interactive: false),
            onSwiped: (_) {},
            enabled: true,
          ),
        ),
      ),
    );
    expect(find.byType(EditableText), findsOneWidget);
    await tester.tap(find.byType(TextField));
    await tester.pump();
    controller.selection = const TextSelection.collapsed(offset: 5);
    await tester.pump();
    expect(controller.selection.baseOffset, 5);
    expect(
      tester
          .state<EditableTextState>(find.byType(EditableText))
          .widget
          .focusNode
          .hasFocus,
      isTrue,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
