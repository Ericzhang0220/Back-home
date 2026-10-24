import 'package:back_home/rooms/ios_room_gesture_policy.dart';
import 'package:back_home/rooms/isometric_room_view.dart';
import 'package:back_home/rooms/room_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const channel = MethodChannel('back_home/room_gestures');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return null;
        });
    IsometricRoomView.rendererEnabled = false;
  });
  tearDown(() {
    IsometricRoomView.rendererEnabled = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('room activation, hiding and disposal update native gestures', (
    tester,
  ) async {
    final controller = RoomEditorController();
    addTearDown(controller.dispose);
    Widget room(bool active) => MaterialApp(
      home: IsometricRoomView(controller: controller, isActive: active),
    );
    await tester.pumpWidget(room(true));
    await tester.pumpWidget(room(true));
    await tester.pumpWidget(room(false));
    await tester.pumpWidget(room(true));
    await tester.pumpWidget(const SizedBox.shrink());
    expect(
      calls.map((call) => call.method),
      everyElement('setRoomGesturesActive'),
    );
    expect(calls.map((call) => (call.arguments as Map)['active']), [
      true,
      false,
      true,
      false,
    ]);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets(
    'overlapping scenes only restore system gestures after both exit',
    (tester) async {
      final first = Object();
      final second = Object();
      IosRoomGesturePolicy.setActive(first, true);
      IosRoomGesturePolicy.setActive(second, true);
      IosRoomGesturePolicy.setActive(first, false);
      await tester.pump();
      expect(calls.length, 1);
      expect(calls.single.arguments, {'active': true});
      IosRoomGesturePolicy.setActive(second, false);
      await tester.pump();
      expect(calls.last.arguments, {'active': false});
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets('Android room gestures do not call an iOS platform channel', (
    tester,
  ) async {
    final owner = Object();
    IosRoomGesturePolicy.setActive(owner, true);
    IosRoomGesturePolicy.setActive(owner, false);
    await tester.pump();
    expect(calls, isEmpty);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}
