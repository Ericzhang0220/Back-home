import 'package:back_home/auth/app_auth_controller.dart';
import 'package:back_home/chat/discovery_top_tabs.dart';
import 'package:back_home/screens/chat_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

typedef _Settings = ({bool portrait, bool navVisible, bool active});

Future<void> _pumpTabs(
  WidgetTester tester,
  ValueNotifier<_Settings> settings,
  ValueChanged<String> onPressed, {
  String? friendsTab,
}) => tester.pumpWidget(
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
                              child: Text(
                                label == friendsTab && !value.portrait
                                    ? 'Friend'
                                    : label,
                              ),
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

  testWidgets(
    'revealed tabs work and stay visible on leaving a portrait page',
    (tester) async {
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

      // Returning to the portrait grants a reveal window instead of hiding the
      // controls immediately under the person's finger.
      settings.value = (portrait: true, navVisible: false, active: true);
      await tester.pump();
      expect(_opacity(tester), 1);
      expect(find.text('Tutor').hitTestable(), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1500));
      expect(_opacity(tester), 0);
      expect(tester.takeException(), isNull);
    },
  );

  for (final tab in ['AI', 'Human']) {
    testWidgets(
      '$tab Friend to portrait keeps tabs and Like for the reveal window',
      (tester) async {
        final settings = ValueNotifier<_Settings>((
          portrait: false,
          navVisible: false,
          active: true,
        ));
        addTearDown(settings.dispose);
        final pressed = <String>[];
        await _pumpTabs(tester, settings, (label) {
          pressed.add(label);
          settings.value = (portrait: true, navVisible: false, active: true);
        }, friendsTab: tab);
        expect(find.text('Friend').hitTestable(), findsOneWidget);
        await tester.tap(find.text('Friend'));
        await tester.pump();
        expect(pressed, [tab]);
        expect(_opacity(tester), 1);
        expect(_likeOpacity(tester), 1);
        for (final label in ['AI', 'Human', 'Tutor']) {
          expect(find.text(label).hitTestable(), findsOneWidget);
        }
        await tester.pump(const Duration(milliseconds: 1499));
        expect(_opacity(tester), 1);
        await tester.pump(const Duration(milliseconds: 1));
        expect(_opacity(tester), 0);
        expect(_likeOpacity(tester), 0);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Human and Friend toggles retain controls and allow upward dismissal',
    (tester) async {
      final settings = ValueNotifier<_Settings>((
        portrait: true,
        navVisible: false,
        active: true,
      ));
      addTearDown(settings.dispose);
      final pressed = <String>[];
      await _pumpTabs(tester, settings, (label) {
        pressed.add(label);
        if (label == 'Human') {
          settings.value = (
            portrait: !settings.value.portrait,
            navVisible: false,
            active: true,
          );
        }
      }, friendsTab: 'Human');
      await _doubleTap(tester, tester.getCenter(find.text('Human')));
      await tester.pump(const Duration(milliseconds: 260));
      await tester.tap(find.text('Human'));
      await tester.pump();
      expect(find.text('Friend').hitTestable(), findsOneWidget);
      expect(_opacity(tester), 1);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Friend'));
      await tester.pump();
      expect(pressed, ['Human', 'Human']);
      expect(find.text('Human').hitTestable(), findsOneWidget);
      expect(_opacity(tester), 1);
      expect(_likeOpacity(tester), 1);
      await tester.drag(find.byType(DiscoveryTopTabs), const Offset(0, -90));
      await tester.pumpAndSettle();
      expect(_opacity(tester), 0);
      expect(_likeOpacity(tester), 0);
      await _doubleTap(tester, tester.getCenter(find.text('Human')));
      await tester.pump(const Duration(milliseconds: 260));
      expect(_opacity(tester), 1);
      expect(find.text('Human').hitTestable(), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('switching through Friend retains an existing reveal deadline', (
    tester,
  ) async {
    final settings = ValueNotifier<_Settings>((
      portrait: true,
      navVisible: false,
      active: true,
    ));
    addTearDown(settings.dispose);
    await _pumpTabs(tester, settings, (_) {});
    await _doubleTap(tester, tester.getCenter(find.text('AI')));
    await tester.pump(const Duration(milliseconds: 300));
    settings.value = (portrait: false, navVisible: false, active: true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    settings.value = (portrait: true, navVisible: false, active: true);
    await tester.pump();
    expect(_opacity(tester), 1);
    await tester.pump(const Duration(milliseconds: 799));
    expect(_opacity(tester), 1);
    await tester.pump(const Duration(milliseconds: 1));
    expect(_opacity(tester), 0);
    expect(_likeOpacity(tester), 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'upward swipe dismisses portrait controls even with dock visible',
    (tester) async {
      final settings = ValueNotifier<_Settings>((
        portrait: true,
        navVisible: true,
        active: true,
      ));
      addTearDown(settings.dispose);
      final pressed = <String>[];
      await _pumpTabs(tester, settings, pressed.add);
      await tester.drag(find.byType(DiscoveryTopTabs), const Offset(0, -90));
      await tester.pumpAndSettle();
      expect(_opacity(tester), 0);
      expect(_likeOpacity(tester), 0);
      expect(pressed, isEmpty);
      expect(settings.value.navVisible, isTrue);
      await _doubleTap(tester, tester.getCenter(find.text('AI')));
      await tester.pump(const Duration(milliseconds: 260));
      expect(_opacity(tester), 1);
      await tester.tap(find.text('Human'));
      expect(pressed, ['Human']);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('horizontal and downward drags do not dismiss the tabs', (
    tester,
  ) async {
    final settings = ValueNotifier<_Settings>((
      portrait: true,
      navVisible: true,
      active: true,
    ));
    addTearDown(settings.dispose);
    await _pumpTabs(tester, settings, (_) {});
    await tester.drag(find.byType(DiscoveryTopTabs), const Offset(80, 0));
    await tester.pumpAndSettle();
    expect(_opacity(tester), 1);
    await tester.drag(find.byType(DiscoveryTopTabs), const Offset(0, 80));
    await tester.pumpAndSettle();
    expect(_opacity(tester), 1);
    settings.value = (portrait: false, navVisible: false, active: true);
    await tester.pump();
    await tester.drag(find.byType(DiscoveryTopTabs), const Offset(0, -90));
    await tester.pumpAndSettle();
    expect(_opacity(tester), 1);
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
