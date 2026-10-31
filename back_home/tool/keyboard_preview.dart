import 'package:back_home/chat/ai_models.dart';
import 'package:back_home/keyboard/keyboard_host.dart';
import 'package:back_home/keyboard/keyboard_store.dart';
import 'package:back_home/rooms/room_state.dart';
import 'package:back_home/screens/shop_screen.dart';
import 'package:back_home/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Isolated, disposable shop demo. Purchases never touch a real account.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The demo deliberately uses a disposable in-memory preferences store.
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});
  final room = RoomEditorController();
  final store = KeyboardStore(
    room,
    characters: (_) => Stream.value(const [
      AiCharacter(
        id: 'my-demo-ai',
        name: 'My stargazer',
        personality: 'A quiet astronomer who loves moonlit gardens.',
        introduction: 'There is always another star to discover.',
        preview: 'A little wonder, every day.',
        colorValue: 0xFFB6B0E4,
        iconCodePoint: 'plants',
        isCustom: true,
        authorUid: 'keyboard-demo',
      ),
    ]),
  );
  await store.loadForAccount('keyboard-demo');
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      builder: (context, child) => AppKeyboardHost(store: store, child: child!),
      home: ShopScreen(controller: room, initialKeyboards: true),
    ),
  );
}
