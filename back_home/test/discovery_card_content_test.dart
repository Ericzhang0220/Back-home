import 'package:back_home/chat/discovery_card_content.dart';
import 'package:back_home/screens/chat_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('hidden navigation space is reclaimed without losing the draft', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 850);
    tester.view.viewPadding = const FakeViewPadding(bottom: 34);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetViewPadding);
    final controller = TextEditingController();
    final navVisible = ValueNotifier(true);
    addTearDown(controller.dispose);
    addTearDown(navVisible.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<bool>(
            valueListenable: navVisible,
            builder: (context, visible, _) => DiscoveryCardContent(
              navVisible: visible,
              keyboardOpen: false,
              conversation: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [Text('Name'), Text('Introduction')],
              ),
              controller: controller,
              isReplying: false,
              onSendMessage: () {},
            ),
          ),
        ),
      ),
    );
    final field = find.byType(TextField);
    await tester.enterText(field, 'My draft');
    controller.selection = const TextSelection.collapsed(offset: 3);
    await tester.pump();
    final editable = tester.state<EditableTextState>(find.byType(EditableText));
    final fieldY = tester.getBottomLeft(field).dy;
    final nameY = tester.getTopLeft(find.text('Name')).dy;
    final introY = tester.getTopLeft(find.text('Introduction')).dy;

    navVisible.value = false;
    await tester.pumpAndSettle();
    final shift = tester.getBottomLeft(field).dy - fieldY;
    expect(shift, closeTo(72, 1));
    expect(tester.getTopLeft(find.text('Name')).dy - nameY, closeTo(shift, 1));
    expect(
      tester.getTopLeft(find.text('Introduction')).dy - introY,
      closeTo(shift, 1),
    );
    expect(tester.getBottomLeft(field).dy, closeTo(850 - 34 - 12, 1));
    expect(
      tester.state<EditableTextState>(find.byType(EditableText)),
      same(editable),
    );
    expect(editable.widget.focusNode.hasFocus, isTrue);
    expect(controller.text, 'My draft');
    expect(controller.selection.baseOffset, 3);

    navVisible.value = true;
    await tester.pumpAndSettle();
    expect(tester.getBottomLeft(field).dy, closeTo(fieldY, 1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

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
    final browsingBottom = tester.getBottomLeft(field).dy;
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
    expect(tester.getBottomLeft(field).dy, closeTo(browsingBottom, 1));
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

  for (final keyboardOpen in [false, true]) {
    testWidgets(
      'long message can be read from beginning to end with keyboard $keyboardOpen',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(400, 850);
        if (keyboardOpen) {
          tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        }
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetViewInsets);
        final controller = TextEditingController();
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DiscoveryCardContent(
                keyboardOpen: keyboardOpen,
                controller: controller,
                isReplying: false,
                onSendMessage: () {},
                conversation: Container(
                  padding: const EdgeInsets.all(14),
                  color: Colors.white,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Beginning of the message'),
                      Text(List.filled(40, 'A complete paragraph.\n').join()),
                      const Text('End of the message'),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        final scrollView = find.byType(SingleChildScrollView);
        final scrollController = tester
            .widget<SingleChildScrollView>(scrollView)
            .controller!;
        expect(find.text('End of the message').hitTestable(), findsOneWidget);
        expect(
          find.text('Beginning of the message').hitTestable(),
          findsNothing,
        );
        if (keyboardOpen) {
          expect(tester.getTopLeft(scrollView).dy, closeTo(12, 1));
        }

        // Drag in the reverse viewport to reveal the start of a message that
        // is taller than the entire available conversation area.
        await tester.drag(scrollView, const Offset(0, 2400));
        await tester.pumpAndSettle();
        expect(
          scrollController.offset,
          scrollController.position.maxScrollExtent,
        );
        expect(
          find.text('Beginning of the message').hitTestable(),
          findsOneWidget,
        );

        await tester.drag(scrollView, const Offset(0, -2400));
        await tester.pumpAndSettle();
        expect(find.text('End of the message').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
