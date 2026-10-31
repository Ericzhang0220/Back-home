import 'package:back_home/audio/background_music_controller.dart';
import 'package:back_home/rooms/isometric_room_view.dart';
import 'package:back_home/rooms/room_state.dart';
import 'package:back_home/screens/room_screen.dart';
import 'package:back_home/settings/app_settings_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => IsometricRoomView.rendererEnabled = false);
  tearDown(() => IsometricRoomView.rendererEnabled = true);

  for (final window in [true, false]) {
    testWidgets(
      'double-tapping after the ${window ? 'window' : 'desk'} shortcut keeps the current view',
      (tester) async {
        final controller = RoomEditorController();
        final settings = AppSettingsController();
        final music = BackgroundMusicController(settingsController: settings);
        addTearDown(controller.dispose);
        addTearDown(settings.dispose);
        addTearDown(music.dispose);
        var reveals = 0;
        final subviews = <bool>[];
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: RoomScreen(
                controller: controller,
                settingsController: settings,
                musicController: music,
                onOpenShop: () {},
                isActive: true,
                isChromeVisible: false,
                isChromeInteractive: false,
                onRevealChrome: () => reveals++,
                onSubviewChanged: subviews.add,
              ),
            ),
          ),
        );
        IsometricRoomView view() =>
            tester.widget<IsometricRoomView>(find.byType(IsometricRoomView));
        if (window) {
          view().onTapWindow!();
        } else {
          view().onTapDesk!();
        }
        await tester.pump();
        for (var tap = 0; tap < 3; tap++) {
          view().onDoubleTapRoom!();
          await tester.pump();
          expect(view().outsideView, window);
          expect(view().deskFocused, !window);
        }
        expect(reveals, 3);
        expect(subviews, [true]);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
