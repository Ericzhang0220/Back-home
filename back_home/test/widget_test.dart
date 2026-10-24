import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:back_home/app.dart';
import 'package:back_home/auth/app_auth_controller.dart';
import 'package:back_home/rooms/furniture_preview.dart';
import 'package:back_home/rooms/isometric_room_view.dart';
import 'package:back_home/rooms/room_state.dart';
import 'package:back_home/screens/chat_screen.dart';
import 'package:back_home/screens/shop_screen.dart';
import 'package:back_home/theme/app_theme.dart';
import 'package:back_home/widgets/app_ui.dart';
import 'package:back_home/widgets/bottom_navigation_reveal.dart';

void main() {
  // The 3D views would otherwise open real GL contexts, whose platform channels
  // never answer under the test binding.
  setUp(() {
    FurniturePreviewStage.rendererEnabled = false;
    IsometricRoomView.rendererEnabled = false;
  });
  tearDown(() {
    FurniturePreviewStage.rendererEnabled = true;
    IsometricRoomView.rendererEnabled = true;
  });

  testWidgets('touching draft text keeps focus and moves the caret', (
    WidgetTester tester,
  ) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);
    await tester.pumpWidget(const BackHomeApp());
    showDialog<void>(
      context: tester.element(find.byType(Scaffold).first),
      builder: (_) => AlertDialog(
        content: TextField(controller: controller, focusNode: focusNode),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Hello wonderful world');
    await tester.pump();
    final editable = tester.state<EditableTextState>(find.byType(EditableText));
    final caret = editable.renderEditable.getLocalRectForCaret(
      const TextPosition(offset: 6),
    );
    final gesture = await tester.startGesture(
      editable.renderEditable.localToGlobal(caret.center),
    );
    await tester.pump();
    // A drag-down callback fires before the text field wins the gesture arena.
    // It must not dismiss focus simply because the finger touched the text.
    expect(focusNode.hasFocus, isTrue);
    await gesture.up();
    await tester.pump();
    expect(controller.selection.baseOffset, 6);
    expect(focusNode.hasFocus, isTrue);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(focusNode.hasFocus, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('discovery card follows the swipe and reveals the card below', (
    WidgetTester tester,
  ) async {
    int? swipeDirection;
    await tester.binding.setSurfaceSize(const Size(400, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SwipeableDiscoveryDeck(
            cardKey: 'front',
            frontCard: const ColoredBox(
              key: ValueKey('front-card'),
              color: Colors.red,
            ),
            previousCard: const ColoredBox(
              key: ValueKey('previous-card'),
              color: Colors.green,
            ),
            nextCard: const ColoredBox(
              key: ValueKey('next-card'),
              color: Colors.blue,
            ),
            enabled: true,
            onSwiped: (direction) => swipeDirection = direction,
          ),
        ),
      ),
    );

    final front = find.byKey(const ValueKey('front-card'));
    final next = find.byKey(const ValueKey('next-card'));
    final initialFrontX = tester.getTopLeft(front).dx;
    final nextX = tester.getTopLeft(next).dx;

    final gesture = await tester.startGesture(tester.getCenter(front));
    await gesture.moveBy(const Offset(-30, 0));
    await gesture.moveBy(const Offset(-120, 0));
    await tester.pump();

    expect(tester.getTopLeft(front).dx, lessThan(initialFrontX));
    expect(tester.getTopLeft(next).dx, lessThan(nextX));

    await gesture.up();
    await tester.pumpAndSettle();

    expect(swipeDirection, 1);
  });

  testWidgets('renders the Back Home shell and switches tabs', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const BackHomeApp());
    expect(find.text('Welcome Back'), findsOneWidget);
    expect(find.text('Open room'), findsOneWidget);

    await tester.ensureVisible(find.text('Low'));
    await tester.tap(find.text('Low'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.text('Open room'));
    await tester.pump();

    expect(find.byType(IsometricRoomView), findsOneWidget);

    await tester.tap(find.text('Chat').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('AI'), findsOneWidget);
    // The discovery experience needs an account, so the signed-out shell
    // shows the sign-in prompt rather than a suggested AI friend.
    expect(find.text('Sign in to use the AI chats and tutor.'), findsOneWidget);
  });

  testWidgets('reselecting Tutor keeps the page and only animates the tab', (
    tester,
  ) async {
    final auth = AppAuthController.offline();
    addTearDown(auth.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ChatScreen(authController: auth)),
      ),
    );
    await tester.tap(find.text('Tutor'));
    await tester.pump();
    final page = tester.widget<AnimatedSwitcher>(find.byType(AnimatedSwitcher));
    expect(page.duration, Duration.zero);
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('Tutor'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        tester.widget<AnimatedSwitcher>(find.byType(AnimatedSwitcher)),
        same(page),
      );
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('hidden navigation returns with double tap or upward swipe', (
    tester,
  ) async {
    await tester.pumpWidget(const BackHomeApp());
    await tester.ensureVisible(find.text('Low'));
    await tester.tap(find.text('Low'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Open room'));
    await tester.pump();
    await tester.tap(find.text('Chat').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      tester.widget<ChatScreen>(find.byType(ChatScreen)).navVisible,
      isTrue,
    );

    // 400 ms has elapsed since opening Chat. Chrome starts hiding at 4 seconds.
    await tester.pump(const Duration(milliseconds: 3599));
    expect(
      tester.widget<ChatScreen>(find.byType(ChatScreen)).navVisible,
      isTrue,
    );
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      tester.widget<ChatScreen>(find.byType(ChatScreen)).navVisible,
      isFalse,
    );
    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    final bottom = Offset(size.width / 2, size.height - 50);
    await tester.tapAt(bottom);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tapAt(bottom);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      tester.widget<ChatScreen>(find.byType(ChatScreen)).navVisible,
      isTrue,
    );

    await tester.timedDrag(
      find.byType(NavigationBar),
      const Offset(0, 65),
      const Duration(seconds: 1),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      tester
          .widget<BottomNavigationReveal>(find.byType(BottomNavigationReveal))
          .enabled,
      isTrue,
    );
    await tester.dragFrom(bottom, const Offset(0, -80));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      tester.widget<ChatScreen>(find.byType(ChatScreen)).navVisible,
      isTrue,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'every tab supports swipe reveal and dismiss; Room skips double tap',
    (tester) async {
      await tester.pumpWidget(const BackHomeApp());
      final size = tester.view.physicalSize / tester.view.devicePixelRatio;
      final bottom = Offset(size.width / 2, size.height - 50);
      final background = Offset(size.width - 8, size.height * 0.4);
      bool hidden() => tester
          .widget<BottomNavigationReveal>(find.byType(BottomNavigationReveal))
          .enabled;
      Future<void> settle() async {
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
      }

      // The landing page can reveal the same navigation without opening a tab.
      expect(hidden(), isTrue);
      await tester.dragFrom(bottom, const Offset(0, -90));
      await settle();
      expect(hidden(), isFalse);
      for (final label in ['Room', 'Hall', 'Chat', 'Profile']) {
        await tester.tap(
          find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text(label),
          ),
        );
        await settle();
        await tester.timedDrag(
          find.byType(NavigationBar),
          const Offset(0, 65),
          const Duration(seconds: 1),
        );
        await settle();
        expect(
          hidden(),
          isTrue,
          reason: '$label must support slow downward dismissal',
        );
        await tester.tapAt(background);
        await tester.pump(const Duration(milliseconds: 100));
        await tester.tapAt(background);
        await settle();
        expect(
          hidden(),
          label == 'Room',
          reason: 'Only Room ignores double-tap navigation reveal',
        );
        if (label != 'Room') {
          await tester.drag(find.byType(NavigationBar), const Offset(0, 65));
          await settle();
        }
        await tester.dragFrom(bottom, const Offset(0, -90));
        await settle();
        expect(hidden(), isFalse, reason: '$label must support upward reveal');
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'navigation stays above settings and switches out of the detail route',
    (tester) async {
      await tester.pumpWidget(const BackHomeApp());
      final size = tester.view.physicalSize / tester.view.devicePixelRatio;
      final bottom = Offset(size.width / 2, size.height - 50);
      await tester.dragFrom(bottom, const Offset(0, -90));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Profile'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Profile settings'));
      await tester.pumpAndSettle();
      expect(find.text('Settings'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Settings'), findsNothing);
      expect(find.byTooltip('Profile settings'), findsOneWidget);
      await tester.tap(find.byTooltip('Profile settings'));
      await tester.pumpAndSettle();
      // Hide it while the detail route remains open, then reveal from that page.
      await tester.drag(find.byType(NavigationBar), const Offset(0, 65));
      await tester.pumpAndSettle();
      await tester.dragFrom(bottom, const Offset(0, -90));
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar).hitTestable(), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Chat'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Settings'), findsNothing);
      expect(find.byType(ChatScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'a page opened from Room can double tap without changing Room gestures',
    (tester) async {
      await tester.pumpWidget(const BackHomeApp());
      final size = tester.view.physicalSize / tester.view.devicePixelRatio;
      final bottom = Offset(size.width / 2, size.height - 50);
      await tester.dragFrom(bottom, const Offset(0, -90));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Room'),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      final pageNavigator = Navigator.of(
        tester.element(find.byType(IsometricRoomView)),
      );
      pageNavigator.push<void>(
        MaterialPageRoute(
          builder: (_) =>
              const Scaffold(body: Center(child: Text('Room detail'))),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.drag(find.byType(NavigationBar), const Offset(0, 65));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        tester
            .widget<BottomNavigationReveal>(find.byType(BottomNavigationReveal))
            .allowDoubleTap,
        isTrue,
      );
      await tester.tap(find.text('Room detail'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('Room detail'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        tester
            .widget<BottomNavigationReveal>(find.byType(BottomNavigationReveal))
            .enabled,
        isFalse,
      );
      pageNavigator.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.drag(find.byType(NavigationBar), const Offset(0, 65));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        tester
            .widget<BottomNavigationReveal>(find.byType(BottomNavigationReveal))
            .allowDoubleTap,
        isFalse,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('typing on a pushed page resizes once and keeps selection', (
    tester,
  ) async {
    await tester.pumpWidget(const BackHomeApp());
    addTearDown(tester.view.resetViewInsets);
    final controller = TextEditingController(text: 'Hello wonderful world');
    addTearDown(controller.dispose);
    final pageContext = tester.element(find.text('Welcome Back'));
    Navigator.of(pageContext).push<void>(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: TextField(controller: controller),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextField));
    controller.selection = const TextSelection.collapsed(offset: 9);
    await tester.pump();
    final state = tester.state<EditableTextState>(find.byType(EditableText));
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    expect(
      tester.getBottomRight(find.byType(TextField)).dy,
      closeTo(size.height - 100, 1),
    );
    final gestures = tester.widget<BottomNavigationReveal>(
      find.byType(BottomNavigationReveal),
    );
    expect(gestures.enabled, isFalse);
    expect(gestures.allowDoubleTap, isFalse);
    expect(controller.selection.baseOffset, 9);
    expect(
      tester.state<EditableTextState>(find.byType(EditableText)),
      same(state),
    );
    tester.view.resetViewInsets();
    await tester.pumpAndSettle();
    expect(controller.selection.baseOffset, 9);
    expect(state.widget.focusNode.hasFocus, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('room and Weather sheet lay out cleanly in landscape', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(844, 390));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const BackHomeApp());
    await tester.ensureVisible(find.text('Low'));
    await tester.tap(find.text('Low'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Open room'));
    await tester.pump();

    expect(find.byType(IsometricRoomView), findsOneWidget);

    await tester.longPress(find.byType(IsometricRoomView));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Weather'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Dispose the renderer before the next test changes the surface metrics;
    // ThreeJS observes those changes with a short debounce timer.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('opens the monthly mood calendar from the profile chart', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const BackHomeApp());

    await tester.ensureVisible(find.text('Low'));
    await tester.tap(find.text('Low'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.text('Open room'));
    await tester.pump();

    await tester.tap(find.text('Profile').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(MoodBarChart), findsOneWidget);
    expect(find.byTooltip('Save bio'), findsNothing);
    expect(
      find.text('0/${AppAuthController.maxProfileBioLength}'),
      findsNothing,
    );

    await tester.tap(find.text('Tap to open monthly mood calendar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Mood Calendar'), findsOneWidget);
  });

  testWidgets('renders the shop catalog at phone size', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: ShopScreen(controller: RoomEditorController()),
      ),
    );

    expect(find.text('Comfort shop'), findsOneWidget);
    expect(find.text('Likes balance'), findsOneWidget);
    expect(find.text('Categories'), findsOneWidget);
    expect(find.text('Buy'), findsWidgets);
    expect(find.text('Edit'), findsWidgets);
    expect(find.textContaining('You have:'), findsWidgets);
  });

  testWidgets('tapping a catalog card moves it onto the preview turntable', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: ShopScreen(controller: RoomEditorController()),
      ),
    );

    // The first catalog piece starts on the turntable, so its name shows twice:
    // once in the preview panel, once on its own card.
    expect(find.text('Sunset bed'), findsNWidgets(2));
    expect(find.text('Soft nightstand'), findsOneWidget);

    final nightstandCard = find.text('Soft nightstand');
    await tester.ensureVisible(nightstandCard);
    await tester.pumpAndSettle();
    await tester.tap(nightstandCard);
    await tester.pumpAndSettle();

    expect(find.text('Soft nightstand'), findsNWidgets(2));
    expect(find.text('Sunset bed'), findsOneWidget);
  });

  testWidgets('shop buy adds inventory without opening the editor', (
    WidgetTester tester,
  ) async {
    final controller = RoomEditorController();
    final initialPlacedCount = controller.placedItems.length;

    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: ShopScreen(controller: controller),
      ),
    );

    final buyButton = find.widgetWithText(FilledButton, 'Buy').first;
    await tester.ensureVisible(buyButton);
    await tester.pumpAndSettle();
    await tester.tap(buyButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Comfort shop'), findsOneWidget);
    expect(find.text('Save'), findsNothing);
    expect(controller.ownedCount('sunset-bed'), 2);
    expect(controller.availableToPlace('sunset-bed'), 1);
    expect(controller.placedItems.length, initialPlacedCount);
  });
}
