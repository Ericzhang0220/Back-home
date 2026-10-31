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

/// Stands in for the iOS text input plugin, which reports a connection closed
/// whenever the native text view holding first responder resigns — on
/// `TextInput.hide`, and when `show` moves first responder to a newer view.
/// Views replaced by a later `setClient` report the stale id 0.
class _IosTextInput {
  _IosTextInput(this.tester) {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.textInput,
      _handle,
    );
  }

  final WidgetTester tester;
  final _closed = <int>[];
  int? _activeId;
  int? _responderId;
  bool _responderIsActive = false;
  String? lastInputType;

  Future<Object?> _handle(MethodCall call) async {
    switch (call.method) {
      case 'TextInput.setClient':
        final args = call.arguments as List<Object?>;
        _activeId = args[0] as int;
        lastInputType =
            ((args[1] as Map)['inputType'] as Map)['name'] as String?;
        if (_responderId != null) _responderId = 0;
        _responderIsActive = false;
      case 'TextInput.clearClient':
        _activeId = null;
        if (_responderId != null) _responderId = 0;
      case 'TextInput.show':
        if (_responderId != null && !_responderIsActive) {
          _closed.add(_responderId!);
        }
        if (_activeId != null) {
          _responderId = _activeId;
          _responderIsActive = true;
        }
      case 'TextInput.hide':
        if (_responderId != null) _closed.add(_responderId!);
        _responderId = null;
    }
    return null;
  }

  /// Delivers the queued reports and lets the framework react to them.
  Future<void> settle() async {
    for (var round = 0; round < 10; round++) {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      if (_closed.isEmpty) return;
      final pending = [..._closed];
      _closed.clear();
      for (final id in pending) {
        await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
          SystemChannels.textInput.name,
          SystemChannels.textInput.codec.encodeMethodCall(
            MethodCall('TextInputClient.onConnectionClosed', [id]),
          ),
          (_) {},
        );
      }
    }
  }
}

void main() {
  testWidgets(
    'iOS: the custom keyboard keeps focus and swaps with the system keyboard',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final room = RoomEditorController();
      final store = KeyboardStore(room);
      addTearDown(store.dispose);
      addTearDown(room.dispose);
      await store.loadForAccount('a');
      // Load outside the fake clock, or the cached load never finishes.
      await tester.runAsync(PinyinLexicon.load);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) =>
              AppKeyboardHost(store: store, child: child!),
          home: const Scaffold(
            body: Column(
              children: [
                KeyboardTarget(isAi: true, child: TextField()),
                TextField(),
              ],
            ),
          ),
        ),
      );
      final platform = _IosTextInput(tester);
      addTearDown(tester.testTextInput.register);
      bool focused(int index) => tester
          .widget<EditableText>(find.byType(EditableText).at(index))
          .focusNode
          .hasFocus;

      await tester.tap(find.byType(TextField).first);
      await platform.settle();
      expect(focused(0), isTrue);
      expect(find.byType(CharacterKeyboard), findsOneWidget);
      expect(platform.lastInputType, 'TextInputType.none');

      // Moving to an ordinary field brings the system keyboard back.
      await tester.tap(find.byType(TextField).last);
      await platform.settle();
      expect(focused(1), isTrue);
      expect(find.byType(CharacterKeyboard), findsNothing);
      expect(platform.lastInputType, isNot('TextInputType.none'));

      // And back again, still without losing focus.
      await tester.tap(find.byType(TextField).first);
      await platform.settle();
      expect(focused(0), isTrue);
      expect(find.byType(CharacterKeyboard), findsOneWidget);
      expect(platform.lastInputType, 'TextInputType.none');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'custom AI input preserves selection, invokes onChanged and send',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final room = RoomEditorController();
      final store = KeyboardStore(room);
      final draft = TextEditingController();
      addTearDown(draft.dispose);
      addTearDown(store.dispose);
      addTearDown(room.dispose);
      await store.loadForAccount('a');
      await tester.runAsync(PinyinLexicon.load);
      String? changed;
      String? sent;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) =>
              AppKeyboardHost(store: store, child: child!),
          home: Scaffold(
            body: KeyboardTarget(
              isAi: true,
              child: TextField(
                controller: draft,
                textInputAction: TextInputAction.send,
                onChanged: (value) => changed = value,
                onSubmitted: (value) => sent = value,
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      expect(find.byType(CharacterKeyboard), findsOneWidget);
      // The native field stays attached but asks for no system keyboard.
      expect(
        (tester.testTextInput.setClientArgs!['inputType'] as Map)['name'],
        'TextInputType.none',
      );
      await tester.tap(find.text('EN'));
      await tester.pump();
      for (final key in 'nihao'.split('')) {
        await tester.tap(find.text(key));
        await tester.pump();
      }
      expect(draft.text, 'nihao');
      final activeKeyboard = tester.widget<CharacterKeyboard>(
        find.byType(CharacterKeyboard),
      );
      expect(activeKeyboard.editing.lexicon, isNotNull);
      expect(activeKeyboard.editing.pinyin, 'nihao');
      expect(find.text('你好'), findsOneWidget);
      await tester.tap(find.text('你好'));
      await tester.pump();
      expect(draft.text, '你好');
      expect(changed, '你好');
      await tester.tap(find.bySemanticsLabel('Send').last);
      await tester.pump();
      expect(sent, '你好');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'scope excludes Human inputs until all-pages is chosen; passwords remain native',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final room = RoomEditorController();
      final store = KeyboardStore(room);
      addTearDown(store.dispose);
      addTearDown(room.dispose);
      await store.loadForAccount('a');
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) =>
              AppKeyboardHost(store: store, child: child!),
          home: const Scaffold(
            body: Column(children: [TextField(), TextField(obscureText: true)]),
          ),
        ),
      );
      await tester.tap(find.byType(TextField).first);
      await tester.pumpAndSettle();
      expect(find.byType(CharacterKeyboard), findsNothing);
      await store.buyOrApply(keyboardSkins[14], KeyboardUseScope.allPages);
      await tester.pumpAndSettle();
      expect(find.byType(CharacterKeyboard), findsOneWidget);
      await tester.tap(find.byType(TextField).last);
      await tester.pumpAndSettle();
      expect(find.byType(CharacterKeyboard), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('all keyboard skins fit small screens and enlarged text', (
    tester,
  ) async {
    final editing = KeyboardEditing();
    addTearDown(editing.dispose);
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final skin in keyboardSkins) {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 568),
              textScaler: TextScaler.linear(1.15),
            ),
            child: Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: SizedBox(
                  height: 270,
                  child: CharacterKeyboard(
                    skin: skin,
                    editing: editing,
                    onAction: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull, reason: skin.name);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
