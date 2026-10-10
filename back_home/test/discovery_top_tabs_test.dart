import 'package:back_home/auth/app_auth_controller.dart';
import 'package:back_home/chat/discovery_top_tabs.dart';
import 'package:back_home/screens/chat_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

typedef _Settings = ({bool portrait, bool navVisible, bool active});

Future<void> _pumpTabs(
  WidgetTester tester,
  ValueNotifier<_Settings> settings,
  ValueChanged<String> onPressed,
) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: SafeArea(
        child: ValueListenableBuilder<_Settings>(
          valueListenable: settings,
          builder: (_, value, _) => DiscoveryControls(
            autoHide: value.portrait,
            navVisible: value.navVisible,
            isActive: value.active,
            child: Column(
              children: [
                DiscoveryTopTabs(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                    child: Row(
                      children: [
                        for (final label in ['AI', 'Human', 'Tutor'])
                          Expanded(
                            child: TextButton(
                              onPressed: () => onPressed(label),
                              child: Text(label),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                DiscoveryControlVisibility(
                  key: const ValueKey('like-visibility'),
                  child: IconButton(
                    tooltip: 'Like',
                    onPressed: () => onPressed('Like'),
                    icon: const Icon(Icons.favorite_border),
                  ),
                ),
                const Expanded(child: ColoredBox(color: Colors.blue)),
              ],
            ),
          ),
        ),
      ),
    ),
  ),
);

double _opacity(WidgetTester tester) => tester
    .widget<AnimatedOpacity>(
      find.descendant(
        of: find.byType(DiscoveryTopTabs),
        matching: find.byType(AnimatedOpacity),
      ),
    )
    .opacity;

double _likeOpacity(WidgetTester tester) => tester
    .widget<AnimatedOpacity>(
      find.descendant(
        of: find.byKey(const ValueKey('like-visibility')),
        matching: find.byType(AnimatedOpacity),
      ),
    )
    .opacity;

Future<void> _doubleTap(WidgetTester tester, Offset point) async {
  await tester.tapAt(point);
  await tester.pump(const Duration(milliseconds: 100));
  await tester.tapAt(point);
  await tester.pump();
}

void main() {
  testWidgets(
    'tabs and Like hide and reveal together for 1.5 seconds on double tap',
    (tester) async {
      final settings = ValueNotifier<_Settings>((
        portrait: true,
        navVisible: true,
        active: true,
      ));
      addTearDown(settings.dispose);
      final pressed = <String>[];
      await _pumpTabs(tester, settings, pressed.add);
      final tabsRect = tester.getRect(find.byType(DiscoveryTopTabs));
      final buttonRects = [
        for (final label in ['AI', 'Human', 'Tutor'])
          tester.getRect(find.text(label)),
      ];
      final revealPoint = tester.getCenter(find.text('Human'));
      final likeRect = tester.getRect(find.byTooltip('Like'));
      expect(_opacity(tester), 1);
      expect(_likeOpacity(tester), 1);

      settings.value = (portrait: true, navVisible: false, active: true);
      await tester.pumpAndSettle();
      expect(_opacity(tester), 0);
      expect(_likeOpacity(tester), 0);
      expect(find.text('Human').hitTestable(), findsNothing);
      expect(find.byTooltip('Like').hitTestable(), findsNothing);
      expect(tester.getRect(find.byType(DiscoveryTopTabs)), tabsRect);
      await tester.tapAt(likeRect.center);

      await tester.tapAt(revealPoint);
      await tester.pump(const Duration(milliseconds: 400));
      expect(_opacity(tester), 0);
      expect(pressed, isEmpty);

      for (var repeat = 0; repeat < 2; repeat++) {
        await _doubleTap(tester, revealPoint);
        expect(_opacity(tester), 1);
        expect(_likeOpacity(tester), 1);
        expect(tester.getRect(find.byTooltip('Like')), likeRect);
        expect(pressed, isEmpty);
        expect(settings.value.navVisible, isFalse);
        for (final (index, label) in ['AI', 'Human', 'Tutor'].indexed) {
          expect(tester.getRect(find.text(label)), buttonRects[index]);
        }
        await tester.pump(const Duration(milliseconds: 1499));
        expect(_opacity(tester), 1);
        expect(_likeOpacity(tester), 1);
        await tester.pump(const Duration(milliseconds: 1));
        expect(_opacity(tester), 0);
        expect(_likeOpacity(tester), 0);
        await tester.pumpAndSettle();
        expect(find.text('Human').hitTestable(), findsNothing);
        expect(find.byTooltip('Like').hitTestable(), findsNothing);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('revealed tabs work and stay visible on leaving a portrait page', (
    tester,
  ) async {
    final settings = ValueNotifier<_Settings>((
      portrait: true,
      navVisible: false,
      active: true,
    ));
    addTearDown(settings.dispose);
    final pressed = <String>[];
    await _pumpTabs(tester, settings, (label) {
      pressed.add(label);
      if (label != 'Like') {
        settings.value = (portrait: false, navVisible: false, active: true);
      }
    });
    await _doubleTap(tester, tester.getCenter(find.text('Tutor')));
    await tester.pump(const Duration(milliseconds: 260));
    await tester.tap(find.byTooltip('Like'));
    expect(pressed, ['Like']);
    expect(_opacity(tester), 1);
    expect(_likeOpacity(tester), 1);
    await tester.tap(find.text('Tutor'));
    await tester.pump();
    expect(pressed, ['Like', 'Tutor']);
    await tester.pump(const Duration(seconds: 2));
    expect(_opacity(tester), 1);
    expect(find.text('Tutor').hitTestable(), findsOneWidget);

    // Switching back to the portrait with the dock hidden hides the tabs again.
    settings.value = (portrait: true, navVisible: false, active: true);
    await tester.pumpAndSettle();
    expect(_opacity(tester), 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dock return and screen changes cancel a temporary reveal', (
    tester,
  ) async {
    final settings = ValueNotifier<_Settings>((
      portrait: true,
      navVisible: false,
      active: true,
    ));
    addTearDown(settings.dispose);
    await _pumpTabs(tester, settings, (_) {});
    final point = tester.getCenter(find.text('AI'));
    await _doubleTap(tester, point);
    settings.value = (portrait: true, navVisible: true, active: true);
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(_opacity(tester), 1);
    settings.value = (portrait: true, navVisible: false, active: true);
    await tester.pumpAndSettle();
    expect(_opacity(tester), 0);

    await _doubleTap(tester, point);
    settings.value = (portrait: true, navVisible: false, active: false);
    await tester.pump();
    settings.value = (portrait: true, navVisible: false, active: true);
    await tester.pumpAndSettle();
    expect(_opacity(tester), 0);

    await _doubleTap(tester, point);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'non-portrait Chat and Tutor keep their tabs with the dock hidden',
    (tester) async {
      final auth = AppAuthController.offline();
      addTearDown(auth.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatScreen(authController: auth, navVisible: false),
          ),
        ),
      );
      for (final label in ['Tutor', 'AI']) {
        await tester.tap(find.text(label));
        await tester.pump(const Duration(seconds: 2));
        expect(
          tester
              .widget<DiscoveryControls>(find.byType(DiscoveryControls))
              .autoHide,
          isFalse,
        );
        expect(_opacity(tester), 1);
        for (final tab in ['AI', 'Human', 'Tutor']) {
          expect(find.text(tab).hitTestable(), findsOneWidget);
        }
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
