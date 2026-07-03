import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:back_home/app.dart';
import 'package:back_home/rooms/isometric_room_view.dart';
import 'package:back_home/rooms/room_state.dart';
import 'package:back_home/screens/shop_screen.dart';
import 'package:back_home/theme/app_theme.dart';
import 'package:back_home/widgets/app_ui.dart';

void main() {
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

    expect(find.text('AI chats'), findsOneWidget);
    expect(
      find.text('Want music first, or a quiet unpacking of the day?'),
      findsOneWidget,
    );
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
