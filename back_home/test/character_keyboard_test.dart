import 'package:back_home/keyboard/keyboard_catalog.dart';
import 'package:back_home/keyboard/keyboard_editing.dart';
import 'package:back_home/keyboard/keyboard_host.dart';
import 'package:back_home/keyboard/keyboard_panel.dart';
import 'package:back_home/keyboard/keyboard_store.dart';
import 'package:back_home/rooms/room_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('custom AI input preserves selection, invokes onChanged and send', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final room = RoomEditorController();
    final store = KeyboardStore(room);
    final draft = TextEditingController();
    addTearDown(draft.dispose); addTearDown(store.dispose); addTearDown(room.dispose);
    await store.loadForAccount('a');
    await tester.runAsync(PinyinLexicon.load);
    String? changed;
    String? sent;
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => AppKeyboardHost(store: store, child: child!),
      home: Scaffold(body: KeyboardTarget(isAi: true, child: TextField(
        controller: draft, textInputAction: TextInputAction.send,
        onChanged: (value) => changed = value, onSubmitted: (value) => sent = value,
      ))),
    ));
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(find.byType(CharacterKeyboard), findsOneWidget);
    expect(tester.testTextInput.isVisible, isFalse);
    for (final key in 'nihao'.split('')) {
      await tester.tap(find.text(key)); await tester.pump();
    }
    expect(draft.text, 'nihao');
    final activeKeyboard = tester.widget<CharacterKeyboard>(find.byType(CharacterKeyboard));
    expect(activeKeyboard.editing.lexicon, isNotNull);
    expect(activeKeyboard.editing.pinyin, 'nihao');
    expect(find.text('你好'), findsOneWidget);
    await tester.tap(find.text('你好')); await tester.pump();
    expect(draft.text, '你好'); expect(changed, '你好');
    await tester.tap(find.bySemanticsLabel('Send').last); await tester.pump();
    expect(sent, '你好');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('scope excludes Human inputs until all-pages is chosen; passwords remain native', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final room = RoomEditorController(); final store = KeyboardStore(room);
    addTearDown(store.dispose); addTearDown(room.dispose);
    await store.loadForAccount('a');
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => AppKeyboardHost(store: store, child: child!),
      home: const Scaffold(body: Column(children: [TextField(), TextField(obscureText: true)])),
    ));
    await tester.tap(find.byType(TextField).first); await tester.pumpAndSettle();
    expect(find.byType(CharacterKeyboard), findsNothing);
    await store.buyOrApply(keyboardSkins[14], KeyboardUseScope.allPages);
    await tester.pumpAndSettle();
    expect(find.byType(CharacterKeyboard), findsOneWidget);
    await tester.tap(find.byType(TextField).last); await tester.pumpAndSettle();
    expect(find.byType(CharacterKeyboard), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('all keyboard skins fit small screens and enlarged text', (tester) async {
    final editing = KeyboardEditing(); addTearDown(editing.dispose);
    tester.view.physicalSize = const Size(320, 568); tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
    for (final skin in keyboardSkins) {
      await tester.pumpWidget(MaterialApp(home: MediaQuery(
        data: const MediaQueryData(size: Size(320, 568), textScaler: TextScaler.linear(1.15)),
        child: Scaffold(body: Align(alignment: Alignment.bottomCenter, child: SizedBox(height: 270,
          child: CharacterKeyboard(skin: skin, editing: editing, onAction: () {})))),
      )));
      await tester.pump();
      expect(tester.takeException(), isNull, reason: skin.name);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
