// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:back_home/app.dart';

void main() {
  testWidgets('renders the Back Home shell and switches tabs', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const BackHomeApp());
    expect(find.text('Back Home'), findsOneWidget);
    expect(find.text('Quick doors'), findsOneWidget);

    await tester.tap(find.text('Chat').last);
    await tester.pumpAndSettle();

    expect(find.text('Recent conversations'), findsOneWidget);
  });
}
