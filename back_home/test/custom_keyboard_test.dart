import 'dart:async';

import 'package:back_home/chat/ai_models.dart';
import 'package:back_home/keyboard/custom_keyboard.dart';
import 'package:back_home/keyboard/custom_keyboard_screen.dart';
import 'package:back_home/keyboard/keyboard_catalog.dart';
import 'package:back_home/keyboard/keyboard_panel.dart';
import 'package:back_home/keyboard/keyboard_editing.dart';
import 'package:back_home/keyboard/keyboard_shop.dart';
import 'package:back_home/keyboard/keyboard_store.dart';
import 'package:back_home/rooms/room_state.dart';
import 'package:back_home/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const ownAi = AiCharacter(
  id: 'my-ai',
  name: 'Luna',
  personality: 'A calm botanist who loves gardens',
  introduction: 'Welcome to my glasshouse',
  preview: 'A quiet garden',
  colorValue: 0xFFAACC99,
  iconCodePoint: 'plants',
  isCustom: true,
  authorUid: 'a',
);
const otherAi = AiCharacter(
  id: 'someone-else',
  name: 'Other',
  personality: 'A musician',
  introduction: 'Hello',
  preview: 'Music',
  colorValue: 0xFFAACC99,
  iconCodePoint: 'music',
  isCustom: true,
  authorUid: 'b',
);

class _ControlledPreferences extends Fake implements SharedPreferences {
  final values = <String, String>{};
  bool fail = false;
  Completer<void>? gate;
  @override
  String? getString(String key) => values[key];
  @override
  Future<bool> setString(String key, String value) async {
    await gate?.future;
    if (fail) return false;
    values[key] = value;
    return true;
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<KeyboardStore> makeStore(
    RoomEditorController room, {
    Future<SharedPreferences> Function()? preferences,
  }) async {
    final store = KeyboardStore(
      room,
      preferences: preferences,
      characters: (_) =>
          Stream.value([ownAi, otherAi, AiCharacter.presets.first]),
    );
    await store.loadForAccount('a');
    await Future<void>.delayed(Duration.zero);
    addTearDown(store.dispose);
    addTearDown(room.dispose);
    return store;
  }

  test(
    'one purchase caps at three, preserves alternatives and persists one chosen keyboard',
    () async {
      final room = RoomEditorController();
      final store = await makeStore(room);
      expect(store.ownCharacters.map((c) => c.id), ['my-ai']);
      expect(await store.purchaseCustomKeyboard('someone-else'), isNotNull);
      expect(
        await store.purchaseCustomKeyboard(AiCharacter.presets.first.id),
        isNotNull,
      );
      expect(room.likesBalance, 238);
      expect(await store.purchaseCustomKeyboard(ownAi.id), isNull);
      final id = store.projects.single.id;
      expect(room.likesBalance, 238 - customKeyboardPrice);
      expect(await store.generateKeyboard(id, ''), isNotNull);
      expect(store.projects.single.remaining, 3);
      expect(
        await store.generateKeyboard(id, 'pastel green, round keys'),
        isNull,
      );
      final first = store.projects.single.results.single.skin;
      expect(
        await store.saveCustomKeyboard(id, first.id, KeyboardUseScope.allPages),
        isNull,
      );
      expect(store.activeSkin, first);
      expect(await store.generateKeyboard(id, 'midnight purple'), isNull);
      expect(store.projects.single.results, hasLength(2));
      expect(await store.generateKeyboard(id, 'blue ocean'), isNull);
      expect(await store.generateKeyboard(id, 'fourth attempt'), isNotNull);
      expect(store.projects.single.results, hasLength(3));
      final last = store.projects.single.results.last.skin;
      expect(
        await store.saveCustomKeyboard(id, last.id, KeyboardUseScope.aiOnly),
        isNull,
      );
      expect(store.owned, contains(last.id));
      expect(store.owned, isNot(contains(first.id)));
      expect(room.likesBalance, 178);
      expect(await store.buyOrApply(last, KeyboardUseScope.allPages), isNull);
      expect(room.likesBalance, 178);

      final restoredRoom = RoomEditorController();
      final restored = await makeStore(restoredRoom);
      expect(restored.projects.single.results, hasLength(3));
      expect(restored.projects.single.remaining, 0);
      expect(restored.activeSkin.id, last.id);
      expect(restored.activeSkin.base, last.base);
      expect(restored.scope, KeyboardUseScope.allPages);
      expect(restoredRoom.likesBalance, 178);
      await restored.loadForAccount('b');
      expect(restored.projects, isEmpty);
      expect(restored.owned, isNot(contains(last.id)));
      expect(restoredRoom.likesBalance, 238);
    },
  );

  test(
    'failed purchases, attempts and selections roll back; parallel attempts do not overrun the cap',
    () async {
      final prefs = _ControlledPreferences();
      final room = RoomEditorController();
      final store = await makeStore(room, preferences: () async => prefs);
      prefs.fail = true;
      expect(await store.purchaseCustomKeyboard(ownAi.id), isNotNull);
      expect(store.projects, isEmpty);
      expect(room.likesBalance, 238);
      prefs.fail = false;
      expect(await store.purchaseCustomKeyboard(ownAi.id), isNull);
      final id = store.projects.single.id;
      prefs.fail = true;
      expect(await store.generateKeyboard(id, 'ocean blue'), isNotNull);
      expect(store.projects.single.remaining, 3);
      prefs.fail = false;
      prefs.gate = Completer<void>();
      final firstAttempt = store.generateKeyboard(id, 'ocean blue');
      expect(await store.generateKeyboard(id, 'duplicate tap'), isNotNull);
      prefs.gate!.complete();
      expect(await firstAttempt, isNull);
      prefs.gate = null;
      prefs.fail = true;
      final skin = store.projects.single.results.single.skin;
      expect(
        await store.saveCustomKeyboard(id, skin.id, KeyboardUseScope.allPages),
        isNotNull,
      );
      expect(store.projects.single.selectedId, isNull);
      expect(store.owned, isNot(contains(skin.id)));
      expect(store.activeId, 'mia-anderson');
      expect(room.likesBalance, 178);
    },
  );

  test(
    'generation uses character background and explicit style, with distinct repeat results',
    () {
      final project = CustomKeyboardProject.forCharacter('test', ownAi);
      final light = generateCustomKeyboard(project, 'pastel blue square keys');
      final dark = generateCustomKeyboard(
        project,
        'midnight purple rounded keys',
      );
      expect(light.skin.isDark, isFalse);
      expect(light.skin.radius, 6);
      expect(dark.skin.isDark, isTrue);
      expect(light.skin.accent, isNot(dark.skin.accent));
      final second = generateCustomKeyboard(
        project.withResult(light),
        light.style,
      );
      expect(second.skin.id, isNot(light.skin.id));
      expect(second.skin.accent, isNot(light.skin.accent));
      final otherBackground = CustomKeyboardProject.forCharacter(
        'test',
        otherAi,
      );
      expect(
        generateCustomKeyboard(otherBackground, light.style).skin.id,
        isNot(light.skin.id),
      );
    },
  );

  testWidgets(
    'purchase, regenerate, compare two or three results, and save locally',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final room = RoomEditorController();
      final store = KeyboardStore(
        room,
        characters: (_) => Stream.value([ownAi]),
      );
      addTearDown(store.dispose);
      addTearDown(room.dispose);
      await store.loadForAccount('a');
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: CustomKeyboardScreen(store: store),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Luna').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField),
        'Midnight blue with rounded keys',
      );
      await tester.ensureVisible(find.text('Buy & generate · 60 Likes'));
      await tester.tap(find.text('Buy & generate · 60 Likes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Buy · 60 Likes'));
      await tester.pumpAndSettle();
      expect(room.likesBalance, 178);
      expect(
        find.text('1 of 3 generated · 2 generations left'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('Regenerate · 2 left'));
      await tester.tap(find.text('Regenerate · 2 left'));
      await tester.pumpAndSettle();
      expect(find.byType(KeyboardThumbnail), findsNWidgets(2));
      FilledButton saveButton() => tester.widget<FilledButton>(
        find
            .ancestor(
              of: find.text('Save selected keyboard'),
              matching: find.byWidgetPredicate(
                (widget) => widget is FilledButton,
              ),
            )
            .first,
      );
      expect(saveButton().onPressed, isNull);
      await tester.ensureVisible(
        find.bySemanticsLabel(RegExp('Select design 1')),
      );
      await tester.tap(find.bySemanticsLabel(RegExp('Select design 1')));
      await tester.pump();
      expect(saveButton().onPressed, isNotNull);
      await tester.ensureVisible(find.text('Regenerate · 1 left'));
      await tester.tap(find.text('Regenerate · 1 left'));
      await tester.pumpAndSettle();
      expect(find.byType(KeyboardThumbnail), findsNWidgets(3));
      expect(find.textContaining('Regenerate ·'), findsNothing);
      expect(saveButton().onPressed, isNull);
      await tester.ensureVisible(
        find.bySemanticsLabel(RegExp('Select design 2')),
      );
      await tester.tap(find.bySemanticsLabel(RegExp('Select design 2')));
      await tester.pump();
      await tester.ensureVisible(find.text('Save selected keyboard'));
      await tester.tap(find.text('Save selected keyboard'));
      await tester.pumpAndSettle();
      expect(store.activeSkin.id, store.projects.single.results[1].skin.id);
      expect(store.projects.single.selectedId, store.activeId);
      expect(room.likesBalance, 178);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'regular preview and keyboard contain no character images even with chat artwork',
    (tester) async {
      final room = RoomEditorController();
      final store = KeyboardStore(room);
      addTearDown(store.dispose);
      addTearDown(room.dispose);
      await store.loadForAccount('a');
      await tester.pumpWidget(
        MaterialApp(
          home: KeyboardPreviewScreen(skin: keyboardSkins[4], store: store),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsNothing);
      expect(find.text('Caleb Johnson'), findsNothing);
      final editing = KeyboardEditing();
      addTearDown(editing.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 300,
              child: CharacterKeyboard(
                skin: keyboardSkins[4],
                editing: editing,
                artworkAsset: 'assets/ai_characters/caleb-johnson.png',
                onAction: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(Image), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
