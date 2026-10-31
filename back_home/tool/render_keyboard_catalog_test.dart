// Run with: flutter test tool/render_keyboard_catalog_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:back_home/keyboard/keyboard_catalog.dart';
import 'package:back_home/keyboard/keyboard_shop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('export the twenty real keyboard designs', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(440, 340);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.runAsync(() async {
      final sans = FontLoader('KeyboardPreviewSans')
        ..addFont(rootBundle.load('assets/keyboard/NotoSansSC-Regular.otf'));
      await sans.load();
      final cjk = FontLoader('ChetCJK')
        ..addFont(rootBundle.load('assets/keyboard/NotoSansSC-Regular.otf'));
      await cjk.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
    });
    final folder = Directory('output/keyboards')..createSync(recursive: true);
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    for (var i = 0; i < keyboardSkins.length; i++) {
      final skin = keyboardSkins[i];
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(fontFamily: 'KeyboardPreviewSans'),
          home: Scaffold(
            body: Center(
              child: RepaintBoundary(
                key: key,
                child: Container(
                  width: 420,
                  height: 318,
                  color: skin.base,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 9),
                        child: Row(
                          children: [
                            Text(
                              (i + 1).toString().padLeft(2, '0'),
                              style: TextStyle(
                                color: skin.accent,
                                fontSize: 24,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    skin.name,
                                    style: TextStyle(
                                      color: skin.ink,
                                      fontSize: 17,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    '${skin.category} · ${skin.price == 0 ? 'Starter' : '${skin.price} Likes'}',
                                    style: TextStyle(
                                      color: skin.ink.withValues(alpha: 0.72),
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(child: KeyboardThumbnail(skin: skin)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: skin.name);
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        await File(
          '${folder.path}/${(i + 1).toString().padLeft(2, '0')}-${skin.id}.png',
        ).writeAsBytes(png!.buffer.asUint8List());
      });
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
