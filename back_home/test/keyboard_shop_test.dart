import 'package:back_home/keyboard/keyboard_catalog.dart';
import 'package:back_home/keyboard/keyboard_host.dart';
import 'package:back_home/keyboard/keyboard_shop.dart';
import 'package:back_home/keyboard/keyboard_store.dart';
import 'package:back_home/rooms/furniture_preview.dart';
import 'package:back_home/rooms/room_state.dart';
import 'package:back_home/screens/shop_screen.dart';
import 'package:back_home/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'Room Shop previews twenty skins and charges only once while scope changes',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      FurniturePreviewStage.rendererEnabled = false;
      addTearDown(() => FurniturePreviewStage.rendererEnabled = true);
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final room = RoomEditorController();
      final store = KeyboardStore(room);
      addTearDown(store.dispose);
      addTearDown(room.dispose);
      await store.loadForAccount('shop-test');
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          builder: (context, child) =>
              KeyboardStoreScope(store: store, child: child!),
          home: ShopScreen(controller: room, initialKeyboards: true),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(KeyboardThumbnail), findsNWidgets(20));
      final item = find.text('Golden Court').last;
      await tester.ensureVisible(item);
      await tester.pumpAndSettle();
      await tester.tap(item);
      await tester.pumpAndSettle();
      expect(find.byType(KeyboardPreviewScreen), findsOneWidget);
      await tester.tap(find.text('Buy · 28 Likes'));
      await tester.pumpAndSettle();
      expect(find.text('AI chats only'), findsOneWidget);
      await tester.tap(find.text('All app pages'));
      await tester.pump();
      await tester.tap(find.text('Buy & apply'));
      await tester.pumpAndSettle();
      expect(store.scope, KeyboardUseScope.allPages);
      expect(room.likesBalance, 210);
      await tester.tap(find.text('Use keyboard'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('AI chats only'));
      await tester.pump();
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      expect(store.scope, KeyboardUseScope.aiOnly);
      expect(room.likesBalance, 210);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
