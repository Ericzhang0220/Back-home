import 'package:back_home/audio/background_music_controller.dart';
import 'package:back_home/auth/app_auth_controller.dart';
import 'package:back_home/screens/create_post_screen.dart';
import 'package:back_home/screens/profile_screen.dart';
import 'package:back_home/settings/app_settings_controller.dart';
import 'package:back_home/theme/app_theme.dart';
import 'package:back_home/widgets/swipe_back_page_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('profile subpages and the own profile swipe back one level', (
    tester,
  ) async {
    final auth = AppAuthController.offline();
    final settings = AppSettingsController();
    final music = BackgroundMusicController(settingsController: settings);
    addTearDown(auth.dispose);
    addTearDown(settings.dispose);
    addTearDown(music.dispose);
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push<void>(
                SwipeBackPageRoute(
                  builder: (_) => Scaffold(
                    body: SafeArea(
                      child: ProfileScreen(
                        settingsController: settings,
                        musicController: music,
                        authController: auth,
                        showBackButton: true,
                      ),
                    ),
                  ),
                ),
              ),
              child: const Text('Hall'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Hall'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Profile settings'));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);
    await tester.dragFrom(const Offset(90, 400), const Offset(210, 0));
    await tester.pumpAndSettle();
    expect(find.byType(ProfileScreen), findsOneWidget);

    await tester.tap(find.byTooltip('Notifications'));
    await tester.pumpAndSettle();
    expect(find.text('Sign in to see your notifications.'), findsOneWidget);
    await tester.dragFrom(const Offset(90, 400), const Offset(210, 0));
    await tester.pumpAndSettle();
    expect(find.byType(ProfileScreen), findsOneWidget);

    await tester.ensureVisible(find.text('Tap to open monthly mood calendar'));
    await tester.tap(find.text('Tap to open monthly mood calendar'));
    await tester.pumpAndSettle();
    expect(find.text('Mood Calendar'), findsOneWidget);
    await tester.dragFrom(const Offset(90, 400), const Offset(210, 0));
    await tester.pumpAndSettle();
    expect(find.byType(ProfileScreen), findsOneWidget);

    // Left swipes and vertical scrolling do not navigate back.
    await tester.dragFrom(const Offset(280, 400), const Offset(-200, 0));
    await tester.pumpAndSettle();
    await tester.dragFrom(const Offset(180, 400), const Offset(0, -100));
    await tester.pumpAndSettle();
    expect(find.byType(ProfileScreen), findsOneWidget);
    await tester.dragFrom(const Offset(90, 400), const Offset(210, 0));
    await tester.pumpAndSettle();
    expect(find.text('Hall'), findsOneWidget);
    expect(find.byType(ProfileScreen), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('right swiping the post editor returns without submitting', (
    tester,
  ) async {
    Object? result = 'pending';
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await Navigator.of(context).push(
                  SwipeBackPageRoute(builder: (_) => const CreatePostScreen()),
                );
              },
              child: const Text('Hall'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Hall'));
    await tester.pumpAndSettle();
    await tester.dragFrom(const Offset(2, 400), const Offset(260, 0));
    await tester.pumpAndSettle();
    expect(find.text('Hall'), findsOneWidget);
    expect(result, isNull);
    expect(tester.takeException(), isNull);
  });
}
