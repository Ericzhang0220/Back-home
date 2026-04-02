import 'package:flutter_test/flutter_test.dart';

import 'package:back_home/app.dart';
import 'package:back_home/widgets/app_ui.dart';

void main() {
  testWidgets('renders the Back Home shell and switches tabs', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const BackHomeApp());
    expect(find.text('Welcome Back'), findsOneWidget);
    expect(find.text('Open room'), findsOneWidget);

    await tester.tap(find.text('Open room'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      find.text('Open settings for inventory, rotate, and store controls.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Chat').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Recent conversations'), findsOneWidget);
  });

  testWidgets('opens the monthly mood calendar from the profile chart', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const BackHomeApp());

    await tester.tap(find.text('Open room'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.text('Profile').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(MoodBarChart), findsOneWidget);

    await tester.tap(find.text('Tap to open monthly mood calendar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Mood Calendar'), findsOneWidget);
  });
}
