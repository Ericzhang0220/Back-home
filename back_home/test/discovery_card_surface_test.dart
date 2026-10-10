import 'package:back_home/app.dart';
import 'package:back_home/chat/discovery_card_content.dart';
import 'package:back_home/chat/discovery_card_surface.dart';
import 'package:back_home/rooms/furniture_preview.dart';
import 'package:back_home/rooms/isometric_room_view.dart';
import 'package:back_home/screens/chat_screen.dart';
import 'package:back_home/widgets/character_portrait.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final keyboardOpen in [false, true]) {
    for (final navVisible in [false, true]) {
      testWidgets('portrait covers the status bar without moving controls '
          '(keyboard: $keyboardOpen, navigation: $navVisible)', (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(393, 852);
        tester.view.padding = const FakeViewPadding(top: 59, bottom: 34);
        tester.view.viewPadding = const FakeViewPadding(top: 59, bottom: 34);
        tester.view.viewInsets = FakeViewPadding(
          bottom: keyboardOpen ? 300 : 0,
        );
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetPadding);
        addTearDown(tester.view.resetViewPadding);
        addTearDown(tester.view.resetViewInsets);
        final controller = TextEditingController(text: 'My draft');
        addTearDown(controller.dispose);

        Widget page({required bool fullBleed}) {
          final background = const CharacterPortrait(
            key: ValueKey('portrait'),
            assetPath: 'assets/ai_characters/mason-williams.png',
            fallback: ColoredBox(color: Colors.blue),
          );
          final foreground = Stack(
            fit: StackFit.expand,
            children: [
              Positioned(
                top: 76,
                left: 18,
                child: IconButton(
                  key: const ValueKey('heart'),
                  onPressed: () {},
                  icon: const Icon(Icons.favorite_border),
                ),
              ),
              DiscoveryCardContent(
                keyboardOpen: keyboardOpen,
                navVisible: navVisible,
                conversation: const Text('Mason Williams'),
                controller: controller,
                isReplying: false,
                onSendMessage: () {},
              ),
            ],
          );
          return MaterialApp(
            home: Scaffold(
              body: fullBleed
                  ? DiscoveryCardSurface(
                      background: background,
                      foreground: foreground,
                    )
                  : SafeArea(
                      bottom: false,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [background, foreground],
                      ),
                    ),
            ),
          );
        }

        await tester.pumpWidget(page(fullBleed: false));
        await tester.pumpAndSettle();
        final controls = [
          find.byKey(const ValueKey('heart')),
          find.text('Mason Williams'),
          find.byType(TextField),
          find.byTooltip('Send'),
        ];
        final originalRects = controls.map(tester.getRect).toList();
        final originalPortrait = tester.getRect(
          find.byKey(const ValueKey('portrait')),
        );
        expect(originalPortrait.top, 59);

        await tester.pumpWidget(page(fullBleed: true));
        await tester.pumpAndSettle();
        final expandedPortrait = tester.getRect(
          find.byKey(const ValueKey('portrait')),
        );
        expect(expandedPortrait.top, 0);
        expect(expandedPortrait.bottom, originalPortrait.bottom);
        for (var index = 0; index < controls.length; index++) {
          expect(tester.getRect(controls[index]), originalRects[index]);
        }
        expect(controller.text, 'My draft');
        expect(SystemChrome.latestStyle?.statusBarColor, Colors.transparent);
        expect(SystemChrome.latestStyle?.statusBarBrightness, Brightness.dark);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
    }
  }

  testWidgets('chat fills the top inset while AI Human Tutor stay below it', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 852);
    tester.view.padding = const FakeViewPadding(top: 59, bottom: 34);
    tester.view.viewPadding = const FakeViewPadding(top: 59, bottom: 34);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);
    FurniturePreviewStage.rendererEnabled = false;
    IsometricRoomView.rendererEnabled = false;
    addTearDown(() {
      FurniturePreviewStage.rendererEnabled = true;
      IsometricRoomView.rendererEnabled = true;
    });

    await tester.pumpWidget(const BackHomeApp());
    await tester.ensureVisible(find.text('Low'));
    await tester.tap(find.text('Low'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Open room'));
    await tester.pump();
    await tester.tap(find.text('Chat').last);
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.getTopLeft(find.byType(ChatScreen)).dy, 0);
    for (final label in ['AI', 'Human', 'Tutor']) {
      final button = find
          .ancestor(of: find.text(label), matching: find.byType(InkWell))
          .first;
      // The original top safe area (59) plus the tab container's padding (10).
      expect(tester.getTopLeft(button).dy, 69);
    }
    expect(SystemChrome.latestStyle?.statusBarBrightness, Brightness.light);
    final portrait = OverlayEntry(
      builder: (_) => const Positioned.fill(
        child: DiscoveryCardSurface(
          background: ColoredBox(color: Colors.black),
          foreground: SizedBox.expand(),
        ),
      ),
    );
    Overlay.of(tester.element(find.byType(ChatScreen))).insert(portrait);
    await tester.pump();
    expect(SystemChrome.latestStyle?.statusBarBrightness, Brightness.dark);
    portrait.remove();
    portrait.dispose();
    await tester.pump();
    expect(SystemChrome.latestStyle?.statusBarBrightness, Brightness.light);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
}
