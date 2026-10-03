import 'dart:ui' as ui;

import 'package:back_home/chat/ai_models.dart';
import 'package:back_home/widgets/character_portrait.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'all presets and existing account copies have distinct bundled art',
    () async {
      final paths = <String>{};
      for (final preset in AiCharacter.presets) {
        final restored = AiCharacter.fromData(
          id: preset.id,
          data: preset.toFirestore(),
        );
        expect(restored.portraitAsset, preset.portraitAsset);
        final path = restored.portraitAsset!;
        expect(
          paths.add(path),
          isTrue,
          reason: '${preset.name} shares artwork',
        );

        // Check the shipped bundle, not just whether the source file exists.
        final bytes = await rootBundle.load(path);
        final codec = await ui.instantiateImageCodec(
          bytes.buffer.asUint8List(),
        );
        final frame = await codec.getNextFrame();
        expect(frame.image.width, greaterThanOrEqualTo(1024));
        expect(frame.image.height, greaterThan(frame.image.width));
        frame.image.dispose();
        codec.dispose();
      }
      expect(paths.length, 20);
    },
  );

  testWidgets(
    'an unavailable uploaded portrait falls back to bundled artwork',
    (tester) async {
      final path = AiCharacter.presets.first.portraitAsset!;
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 58,
            height: 58,
            child: CharacterPortrait(
              photoUrl: 'https://example.invalid/unavailable.png',
              assetPath: path,
              fallback: const Icon(Icons.person),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final bundledImage = find.byWidgetPredicate(
        (widget) => widget is Image && widget.image is AssetImage,
      );
      expect(bundledImage, findsOneWidget);
      final image = tester.widget<Image>(bundledImage);
      expect((image.image as AssetImage).assetName, path);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('custom characters retain their upload or icon fallback', (
    tester,
  ) async {
    final custom = AiCharacter.fromData(
      id: AiCharacter.presets.first.id,
      data: {...AiCharacter.presets.first.toFirestore(), 'isCustom': true},
    );
    expect(custom.portraitAsset, isNull);
    await tester.pumpWidget(
      MaterialApp(
        home: CharacterPortrait(
          assetPath: custom.portraitAsset,
          fallback: const Icon(Icons.favorite),
        ),
      ),
    );
    expect(find.byIcon(Icons.favorite), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });
}
