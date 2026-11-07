import 'package:back_home/app.dart';
import 'package:back_home/rooms/isometric_room_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Chat dock holds 2.9 seconds then slides out over 380ms', (
    tester,
  ) async {
    IsometricRoomView.rendererEnabled = false;
    addTearDown(() => IsometricRoomView.rendererEnabled = true);
    await tester.pumpWidget(const BackHomeApp());
    await tester.ensureVisible(find.text('Low'));
    await tester.tap(find.text('Low'));
    await tester.pump();
    await tester.tap(find.text('Open room'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Chat').last);
    await tester.pump();
    final dock = find.byWidgetPredicate(
      (widget) =>
          widget is AnimatedSlide && widget.key == const ValueKey(false),
    );
    await tester.pump(const Duration(milliseconds: 2899));
    expect(tester.widget<AnimatedSlide>(dock).offset, Offset.zero);
    await tester.pump(const Duration(milliseconds: 1));
    expect(tester.widget<AnimatedSlide>(dock).offset, const Offset(0, 1));
    expect(
      tester.widget<AnimatedSlide>(dock).duration,
      const Duration(milliseconds: 380),
    );
    await tester.pump(const Duration(milliseconds: 380));
    final transition = find
        .descendant(of: dock, matching: find.byType(SlideTransition))
        .first;
    expect(
      tester.widget<SlideTransition>(transition).position.value,
      const Offset(0, 1),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
