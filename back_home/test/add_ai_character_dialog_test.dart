import 'dart:convert';

import 'package:back_home/chat/ai_character_photo.dart';
import 'package:back_home/widgets/add_ai_character_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final photo = AiCharacterPhoto(
    bytes: base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGPoWHXmPwAGugL+GyFQfgAAAABJRU5ErkJggg==',
    ),
    contentType: 'image/png',
  );
  for (final dismissal in ['Cancel', 'barrier', 'back', 'Add']) {
    testWidgets('character dialog survives $dismissal during keyboard close', (
      tester,
    ) async {
      addTearDown(tester.view.resetViewInsets);
      AiCharacterDraft? result;
      var returned = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  returned = false;
                  result = await showAddAiCharacterDialog(
                    context,
                    pickPhoto: () async => photo,
                  );
                  returned = true;
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), '  Luna  ');
      await tester.enterText(find.byType(TextField).at(1), '  Kind and calm  ');
      if (dismissal == 'Add') {
        final photoButton = find.text('Add photo');
        await tester.ensureVisible(photoButton);
        await tester.tap(photoButton);
        await tester.pumpAndSettle();
        expect(find.byType(Image), findsOneWidget);
        expect(find.text('Change photo'), findsOneWidget);
        await tester.ensureVisible(find.byType(SwitchListTile));
        await tester.tap(find.byType(SwitchListTile));
      }
      tester.view.viewInsets = const FakeViewPadding(bottom: 200);
      await tester.pumpAndSettle();
      final controllers = tester
          .widgetList<TextField>(find.byType(TextField))
          .map((field) => field.controller!)
          .toList();

      if (dismissal == 'barrier') {
        await tester.tapAt(const Offset(5, 5));
      } else if (dismissal == 'back') {
        await tester.binding.handlePopRoute();
      } else {
        await tester.ensureVisible(find.text(dismissal));
        await tester.tap(find.text(dismissal));
      }
      // The route result arrives before its reverse animation removes the
      // fields. A keyboard metrics update can rebuild them in this interval.
      tester.view.resetViewInsets();
      await tester.pump();
      expect(returned, isTrue);
      expect(find.byType(TextField), findsNWidgets(2));
      expect(tester.takeException(), isNull);
      for (final controller in controllers) {
        void listener() {}
        controller.addListener(listener);
        controller.removeListener(listener);
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(TextField), findsNothing);
      for (final controller in controllers) {
        expect(() => controller.addListener(() {}), throwsFlutterError);
      }
      if (dismissal == 'Add') {
        expect(result?.name, 'Luna');
        expect(result?.personality, 'Kind and calm');
        expect(result?.isPublic, isTrue);
        expect(result?.photo, same(photo));
      } else {
        expect(result, isNull);
      }

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      for (final field in tester.widgetList<TextField>(
        find.byType(TextField),
      )) {
        expect(field.controller!.text, isEmpty);
      }
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isFalse,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
