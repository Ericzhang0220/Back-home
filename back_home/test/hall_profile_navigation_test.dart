import 'package:back_home/screens/hall_post.dart';
import 'package:back_home/profile/hall_profile_navigation.dart';
import 'package:back_home/screens/hall_post_thread_screen.dart';
import 'package:back_home/screens/hall_user_profile_screen.dart';
import 'package:back_home/theme/app_theme.dart';
import 'package:back_home/widgets/hall_post_card.dart';
import 'package:back_home/widgets/profile_avatar.dart';
import 'package:back_home/widgets/swipe_back_page_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

HallPost _post({List<HallComment> thread = const []}) => HallPost(
  author: 'Alex',
  mood: 'Good',
  topic: 'Home',
  message: 'A peaceful evening',
  likes: 2,
  lastUpdatedAt: DateTime.now(),
  thread: thread,
);

void main() {
  testWidgets('own identity uses the account page and never matches by name', (
    tester,
  ) async {
    var ownProfileOpened = 0;
    late BuildContext pageContext;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) {
            pageContext = context;
            return const Scaffold();
          },
        ),
      ),
    );

    openHallProfile(
      pageContext,
      displayName: 'You',
      uid: 'me',
      currentUid: 'me',
      onOwnProfileTap: () => ownProfileOpened++,
    );
    openHallProfile(
      pageContext,
      displayName: 'Old name',
      isMe: true,
      currentUid: 'me',
      onOwnProfileTap: () => ownProfileOpened++,
    );
    expect(ownProfileOpened, 2);
    expect(find.byType(HallUserProfileScreen), findsNothing);

    openHallProfile(
      pageContext,
      displayName: 'You',
      currentUid: 'me',
      onOwnProfileTap: () => ownProfileOpened++,
    );
    await tester.pumpAndSettle();
    expect(ownProfileOpened, 2);
    expect(find.byType(HallUserProfileScreen), findsOneWidget);
  });

  testWidgets('own post and comment avatars use the account page callback', (
    tester,
  ) async {
    var ownProfileOpened = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: HallPostThreadScreen(
          authorUid: 'me',
          post: _post(
            thread: const [
              HallComment(
                author: 'You',
                authorUid: 'me',
                message: 'My comment',
                sentAt: 'Now',
                isMe: true,
              ),
            ],
          ).copyWith(authorUid: 'me', canEdit: true),
          onOwnProfileTap: () => ownProfileOpened++,
        ),
      ),
    );
    for (var index = 0; index < 2; index++) {
      await tester.tap(find.byType(ProfileAvatar).at(index));
      await tester.pumpAndSettle();
    }
    expect(ownProfileOpened, 2);
    expect(find.byType(HallUserProfileScreen), findsNothing);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
  });

  testWidgets('right swipe returns the updated thread exactly one page', (
    tester,
  ) async {
    HallPost? result;
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await Navigator.of(context).push<HallPost>(
                  SwipeBackPageRoute(
                    builder: (_) => HallPostThreadScreen(post: _post()),
                  ),
                );
              },
              child: const Text('Open thread'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open thread'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.favorite_border_rounded));
    await tester.enterText(find.byType(TextField), 'New reply');
    await tester.pump();
    await tester.tap(find.byTooltip('Send comment'));
    await tester.pumpAndSettle();

    await tester.dragFrom(const Offset(80, 420), const Offset(210, 0));
    await tester.pumpAndSettle();
    expect(find.text('Open thread'), findsOneWidget);
    expect(result?.likes, 3);
    expect(result?.thread.single.message, 'New reply');
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('repeated authors can open profiles without opening the thread', (
    tester,
  ) async {
    var threadOpened = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => ListView(
              children: List.generate(
                2,
                (_) => HallPostCard(
                  post: _post(),
                  onCommentTap: () => threadOpened = true,
                  onAuthorTap: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) =>
                          const HallUserProfileScreen(displayName: 'Alex'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    for (var index = 0; index < 2; index++) {
      await tester.tap(find.byType(ProfileAvatar).at(index));
      await tester.pumpAndSettle();
      expect(find.byType(HallUserProfileScreen), findsOneWidget);
      expect(threadOpened, isFalse);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
    }
  });

  testWidgets(
    'thread and comment avatars open the right profile and keep draft',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 852));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: HallPostThreadScreen(
            post: _post(
              thread: const [
                HallComment(
                  author: 'Sam',
                  message: 'That sounds lovely',
                  sentAt: 'Now',
                ),
              ],
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'My draft');
      await tester.pump();

      for (final name in ['Alex', 'Sam']) {
        await tester.tap(
          find.byWidgetPredicate(
            (widget) => widget is ProfileAvatar && widget.displayName == name,
          ),
        );
        await tester.pumpAndSettle();
        final profile = tester.widget<HallUserProfileScreen>(
          find.byType(HallUserProfileScreen),
        );
        expect(profile.displayName, name);
        expect(profile.mood, name == 'Alex' ? 'Good' : isNull);
        expect(tester.takeException(), isNull);
        if (name == 'Sam') {
          await tester.dragFrom(const Offset(80, 420), const Offset(210, 0));
        } else {
          await tester.tap(find.byType(BackButton));
        }
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          'My draft',
        );
      }

      // The rest of the comment still mentions its author for replies.
      await tester.tap(find.text('That sounds lovely'));
      await tester.pumpAndSettle();
      expect(find.byType(HallUserProfileScreen), findsNothing);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '@Sam ',
      );
      expect(
        tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus,
        isTrue,
      );
    },
  );
}
