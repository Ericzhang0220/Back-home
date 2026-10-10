import 'package:back_home/chat/ai_models.dart';
import 'package:back_home/widgets/edit_ai_character_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const character = AiCharacter(
  id: 'custom',
  name: 'Luna',
  personality: 'Quiet and kind',
  introduction: '',
  preview: '',
  colorValue: 0,
  iconCodePoint: 'heart',
  isCustom: true,
);

void main() {
  Future<void> open(
    WidgetTester tester,
    Future<void> Function(String, String) save,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showEditAiCharacterDialog(
                context,
                character: character,
                onSave: save,
              ),
              child: const Text('Edit'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
  }

  testWidgets('editor preloads details and retries without losing changes', (
    tester,
  ) async {
    var attempts = 0;
    await open(tester, (name, personality) async {
      expect(name, 'Nova');
      expect(personality, 'Talkative and kind');
      if (attempts++ == 0) throw StateError('offline');
    });
    final fields = find.byType(TextFormField);
    expect(find.text('Luna'), findsOneWidget);
    expect(find.text('Quiet and kind'), findsOneWidget);
    await tester.enterText(fields.first, ' Nova ');
    await tester.enterText(fields.last, 'Talkative and kind');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Could not save. Please try again.'), findsOneWidget);
    expect(find.text(' Nova '), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty fields do not save and cancel closes safely', (
    tester,
  ) async {
    var saves = 0;
    await open(tester, (_, _) async {
      saves++;
    });
    await tester.enterText(find.byType(TextFormField).first, ' ');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a name.'), findsOneWidget);
    expect(saves, 0);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
