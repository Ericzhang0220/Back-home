import 'dart:convert';
import 'dart:async';

import 'package:back_home/widgets/fullscreen_photo_viewer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const channel = MethodChannel('gal');
  final calls = <MethodCall>[];
  var allowed = true;
  var failSave = false;
  Completer<void>? pendingSave;
  setUp(() {
    allowed = true;
    failSave = false;
    pendingSave = null;
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'requestAccess') return allowed;
          if (call.method == 'putImageBytes') {
            if (failSave) throw PlatformException(code: 'NOT_ENOUGH_SPACE');
            await pendingSave?.future;
          }
          return null;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
  final image = MemoryImage(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==',
    ),
  );
  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  showFullscreenPhoto(context, image: image, label: 'Luna'),
              child: const Text('Open photo'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open photo'));
    await tester.pumpAndSettle();
    expect(find.byType(FullscreenPhotoViewer), findsOneWidget);
  }

  testWidgets('photo fills a separate screen and downward swipe returns', (
    tester,
  ) async {
    await open(tester);
    final picture = tester.widget<Image>(find.byType(Image));
    expect(picture.fit, BoxFit.contain);
    expect(
      tester.getSize(find.byType(FullscreenPhotoViewer)),
      tester.view.physicalSize / tester.view.devicePixelRatio,
    );
    await tester.drag(find.byType(InteractiveViewer), const Offset(0, 180));
    await tester.pumpAndSettle();
    expect(find.byType(FullscreenPhotoViewer), findsNothing);
    expect(find.text('Open photo'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('short or horizontal swipes stay open; close button returns', (
    tester,
  ) async {
    await open(tester);
    await tester.drag(find.byType(InteractiveViewer), const Offset(0, 40));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(InteractiveViewer), const Offset(180, 5));
    await tester.pumpAndSettle();
    expect(find.byType(FullscreenPhotoViewer), findsOneWidget);
    await tester.tap(find.byTooltip('Close photo'));
    await tester.pumpAndSettle();
    expect(find.byType(FullscreenPhotoViewer), findsNothing);
  });

  testWidgets('pinch zoom and panning do not dismiss the photo', (
    tester,
  ) async {
    await open(tester);
    final center = tester.getCenter(find.byType(InteractiveViewer));
    final left = await tester.startGesture(
      center - const Offset(40, 0),
      pointer: 1,
    );
    final right = await tester.startGesture(
      center + const Offset(40, 0),
      pointer: 2,
    );
    await tester.pump();
    await left.moveTo(center - const Offset(100, 0));
    await right.moveTo(center + const Offset(100, 0));
    await tester.pump();
    await left.moveTo(center - const Offset(160, 0));
    await right.moveTo(center + const Offset(160, 0));
    await tester.pump();
    await left.up();
    await right.up();
    await tester.pumpAndSettle();
    final viewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    expect(
      viewer.transformationController!.value.getMaxScaleOnAxis(),
      greaterThan(1.01),
    );
    await tester.drag(find.byType(InteractiveViewer), const Offset(0, 180));
    await tester.pumpAndSettle();
    expect(find.byType(FullscreenPhotoViewer), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'long press offers saving; cancel does not request photo access',
    (tester) async {
      await open(tester);
      await tester.longPress(find.byType(Image));
      await tester.pumpAndSettle();
      expect(find.text('Save to Photos'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      expect(find.byType(FullscreenPhotoViewer), findsOneWidget);
    },
  );

  testWidgets(
    'save writes the original photo once and waits for native success',
    (tester) async {
      pendingSave = Completer<void>();
      await open(tester);
      await tester.longPress(find.byType(Image));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save to Photos'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Saving…'), findsOneWidget);
      expect(find.text('Saved to Photos'), findsNothing);
      await tester.longPress(find.byType(Image));
      await tester.pump();
      expect(find.text('Save to Photos'), findsNothing);
      final saves = calls
          .where((call) => call.method == 'putImageBytes')
          .toList();
      expect(saves, hasLength(1));
      expect(saves.single.arguments['bytes'], orderedEquals(image.bytes));
      expect(saves.single.arguments['album'], isNull);
      pendingSave!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Saved to Photos'), findsOneWidget);
      expect(find.text('Saving…'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('denied permission does not save or show a success message', (
    tester,
  ) async {
    allowed = false;
    await open(tester);
    await tester.longPress(find.byType(Image));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save to Photos'));
    await tester.pumpAndSettle();
    expect(calls.where((call) => call.method == 'putImageBytes'), isEmpty);
    expect(find.text('Saved to Photos'), findsNothing);
    expect(
      find.text('Allow photo access in Settings to save photos.'),
      findsOneWidget,
    );
  });

  testWidgets('native save failure is explained and saving can be retried', (
    tester,
  ) async {
    failSave = true;
    await open(tester);
    await tester.longPress(find.byType(Image));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save to Photos'));
    await tester.pumpAndSettle();
    expect(find.text('Not enough space to save this photo.'), findsOneWidget);
    expect(find.text('Saved to Photos'), findsNothing);
    failSave = false;
    await tester.longPress(find.byType(Image));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save to Photos'));
    await tester.pumpAndSettle();
    expect(find.text('Saved to Photos'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
