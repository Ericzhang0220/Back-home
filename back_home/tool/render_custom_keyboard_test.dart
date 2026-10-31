// Run with: flutter test tool/render_custom_keyboard_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:back_home/chat/ai_models.dart';
import 'package:back_home/keyboard/custom_keyboard_screen.dart';
import 'package:back_home/keyboard/keyboard_catalog.dart';
import 'package:back_home/keyboard/keyboard_shop.dart';
import 'package:back_home/keyboard/keyboard_store.dart';
import 'package:back_home/rooms/room_state.dart';
import 'package:back_home/theme/app_theme.dart';
import 'package:back_home/widgets/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _character = AiCharacter(
  id: 'custom-demo',
  name: 'Luna',
  personality: 'A quiet astronomer who loves moonlit gardens and soft music.',
  introduction: 'There is always another star to discover.',
  preview: 'A little wonder, every day.',
  colorValue: 0xFFB6B0E4,
  iconCodePoint: 'music',
  isCustom: true,
);

void main() {
  testWidgets('render abstract shop and custom generation flow', (
    tester,
  ) async {
    // The visual demo uses disposable preferences.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      await (FontLoader(
            'ChetCJK',
          )..addFont(rootBundle.load('assets/keyboard/NotoSansSC-Regular.otf')))
          .load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    });
    final room = RoomEditorController();
    final store = KeyboardStore(
      room,
      characters: (_) => Stream.value([_character]),
    );
    addTearDown(store.dispose);
    addTearDown(room.dispose);
    await store.loadForAccount('preview');
    final boundary = GlobalKey();
    Future<void> show(Widget page, String name) async {
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light().copyWith(
              textTheme: AppTheme.light().textTheme.apply(
                fontFamily: 'ChetCJK',
              ),
            ),
            home: page,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final render =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await render.toImage(pixelRatio: 2);
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        final folder = Directory('output/keyboards')
          ..createSync(recursive: true);
        await File(
          '${folder.path}/$name.png',
        ).writeAsBytes(png!.buffer.asUint8List());
      });
    }

    await show(
      Scaffold(
        backgroundColor: AppColors.cream,
        appBar: AppBar(title: const Text('Keyboards')),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: KeyboardShopSection(store: store),
        ),
      ),
      'abstract-keyboard-shop',
    );
    await show(CustomKeyboardScreen(store: store), 'custom-keyboard-setup');
    expect(await store.purchaseCustomKeyboard(_character.id), isNull);
    final id = store.projects.single.id;
    expect(
      await store.generateKeyboard(
        id,
        'Midnight blue with soft lavender accents',
      ),
      isNull,
    );
    expect(
      await store.generateKeyboard(id, 'Pastel purple, soft rounded keys'),
      isNull,
    );
    await show(
      CustomKeyboardScreen(
        key: const ValueKey('results'),
        store: store,
        projectId: id,
      ),
      'custom-keyboard-results',
    );
    expect(
      await store.saveCustomKeyboard(
        id,
        store.projects.single.results.last.skin.id,
        KeyboardUseScope.aiOnly,
      ),
      isNull,
    );
    await show(
      Scaffold(
        backgroundColor: AppColors.cream,
        appBar: AppBar(title: const Text('Keyboards')),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: KeyboardShopSection(store: store),
        ),
      ),
      'custom-keyboard-saved',
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
