import 'dart:async';
import 'dart:convert';

import 'package:back_home/chat/ai_character_photo.dart';
import 'package:back_home/widgets/add_ai_character_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

final photo = AiCharacterPhoto(
  bytes: base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGPoWHXmPwAGugL+GyFQfgAAAABJRU5ErkJggg==',
  ),
  contentType: 'image/png',
);

Future<void> openDialog(
  WidgetTester tester, {
  Future<AiCharacterPhoto?> Function()? picker,
  Future<void> Function(AiCharacterDraft)? create,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showAddAiCharacterDialog(
              context,
              pickPhoto: picker ?? () async => photo,
              onCreate: create,
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

Future<void> fillDraft(WidgetTester tester, {bool choosePhoto = true}) async {
  if (choosePhoto) {
    await tester.ensureVisible(
      find.byKey(const ValueKey('ai-character-photo-picker')),
    );
    await tester.tap(find.byKey(const ValueKey('ai-character-photo-picker')));
    await tester.pumpAndSettle();
  }
  await tester.enterText(find.byType(TextField).at(0), 'Luna');
  await tester.enterText(find.byType(TextField).at(1), 'Kind and calm');
  await tester.ensureVisible(find.text('Add'));
}

void main() {
  testWidgets(
    'phone form keeps required photo, gender and tags when the keyboard opens',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      addTearDown(tester.view.resetViewInsets);
      AiCharacterDraft? created;
      await openDialog(
        tester,
        create: (draft) async {
          created = draft;
        },
      );
      await fillDraft(tester);
      await tester.enterText(
        find.byType(TextField).at(1),
        'Kind and calm, loves reading novels.',
      );
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Not specified'));
      await tester.tap(find.text('Not specified'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Female').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Add'));
      await tester.tap(find.text('Add'));
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      expect(created!.photo, same(photo));
      expect(created!.gender, 'female');
      expect(created!.tags, contains('book'));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'creation requires a photo and canceling the picker keeps the draft',
    (tester) async {
      var created = 0;
      await openDialog(
        tester,
        picker: () async => null,
        create: (_) async {
          created++;
        },
      );
      await fillDraft(tester);
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      expect(created, 0);
      expect(
        find.text('Choose a character photo to continue.'),
        findsOneWidget,
      );
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        'Luna',
      );
      expect(find.byType(AlertDialog), findsOneWidget);
    },
  );

  testWidgets('photo denial is recoverable without losing entered details', (
    tester,
  ) async {
    var denied = true;
    await openDialog(
      tester,
      picker: () async {
        if (denied) throw PlatformException(code: 'photo_access_denied');
        return photo;
      },
    );
    await fillDraft(tester, choosePhoto: false);
    await tester.ensureVisible(
      find.byKey(const ValueKey('ai-character-photo-picker')),
    );
    await tester.tap(find.byKey(const ValueKey('ai-character-photo-picker')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Allow access in Settings'), findsOneWidget);
    denied = false;
    await tester.tap(find.byKey(const ValueKey('ai-character-photo-picker')));
    await tester.pumpAndSettle();
    expect(find.text('Change photo'), findsOneWidget);
    expect(find.textContaining('Allow access in Settings'), findsNothing);
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      'Luna',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'failed upload keeps the photo and allows the same draft to retry',
    (tester) async {
      var attempts = 0;
      AiCharacterDraft? created;
      await openDialog(
        tester,
        create: (draft) async {
          attempts++;
          if (attempts == 1) throw StateError('Upload unavailable');
          created = draft;
        },
      );
      await fillDraft(tester);
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('ai-character-create-error')),
        findsOneWidget,
      );
      expect(find.text('Change photo'), findsOneWidget);
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      expect(attempts, 2);
      expect(created!.photo, same(photo));
      expect(created!.name, 'Luna');
      expect(created!.isPublic, isFalse);
      expect(find.byType(AlertDialog), findsNothing);
    },
  );

  testWidgets(
    'upload progress prevents duplicate creation and closing mid-save',
    (tester) async {
      final upload = Completer<void>();
      var attempts = 0;
      await openDialog(
        tester,
        create: (_) {
          attempts++;
          return upload.future;
        },
      );
      await fillDraft(tester);
      await tester.tap(find.text('Add'));
      await tester.pump();
      expect(attempts, 1);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Cancel'))
            .onPressed,
        isNull,
      );
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byType(AlertDialog), findsOneWidget);
      upload.complete();
      await tester.pumpAndSettle();
      expect(attempts, 1);
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
