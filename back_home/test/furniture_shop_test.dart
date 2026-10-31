import 'dart:io';
import 'dart:ui' as ui;

import 'package:back_home/rooms/furniture_preview.dart';
import 'package:back_home/rooms/furniture_thumbnail_painter.dart';
import 'package:back_home/rooms/room_state.dart';
import 'package:back_home/screens/shop_screen.dart';
import 'package:back_home/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    '330 stable recipes cover every department with ten forms and three finishes',
    () {
      final room = RoomEditorController();
      addTearDown(room.dispose);
      expect(room.catalog.length, 337);
      expect(room.catalog.map((e) => e.id).toSet().length, 337);
      for (final kind in RoomItemVisualKind.values) {
        final items = room.catalog.where(
          (e) => e.visualKind == kind && e.design != null,
        );
        expect(items.length, 30);
        expect(items.map((e) => e.design!.form).toSet().length, 10);
        expect(items.map((e) => e.design!.finish).toSet().length, 3);
      }
    },
  );

  test(
    'category and both sort directions work with sales, prices and cold starts',
    () {
      final room = RoomEditorController();
      addTearDown(room.dispose);
      final catalog = room.catalog;
      final hot = catalog.first.id, cold = catalog.last.id;
      expect(
        browseFurniture(catalog, popularity: {hot: 9, cold: 2}).first.id,
        hot,
      );
      expect(
        browseFurniture(
          catalog,
          descending: false,
          popularity: {hot: 9, cold: 2},
        ).last.id,
        hot,
      );
      for (final descending in [true, false]) {
        final items = browseFurniture(
          catalog,
          kind: RoomItemVisualKind.table,
          sort: FurnitureSort.price,
          descending: descending,
        );
        expect(items.length, 30);
        for (var i = 1; i < items.length; i++) {
          expect(
            descending
                ? items[i - 1].price >= items[i].price
                : items[i - 1].price <= items[i].price,
            isTrue,
          );
        }
      }
      expect(
        browseFurniture(catalog).map((e) => e.id),
        browseFurniture(catalog.reversed).map((e) => e.id),
      );
    },
  );

  test(
    'new SKU buys, places, rotates and survives applying an edit session',
    () {
      final room = RoomEditorController();
      addTearDown(room.dispose);
      const id = 'studio-table-1-2';
      final balance = room.likesBalance;
      expect(room.purchaseItem(id).isSuccess, isTrue);
      expect(room.likesBalance, balance - room.definitionFor(id).price);
      final edited = RoomEditorController.editing(room);
      addTearDown(edited.dispose);
      expect(
        edited
            .addOwnedItem(
              id,
              preferredOrigin: const GridPoint(6, 7),
              rotationQuarterTurns: 1,
            )
            .isSuccess,
        isTrue,
      );
      room.applyEditSession(edited);
      expect(room.placedItems.any((e) => e.definitionId == id), isTrue);
      expect(room.availableToPlace(id), 0);
    },
  );

  testWidgets(
    'categories precede cards; filtering, sorting, detail and related styles work',
    (tester) async {
      FurniturePreviewStage.rendererEnabled = false;
      addTearDown(() => FurniturePreviewStage.rendererEnabled = true);
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final room = RoomEditorController();
      addTearDown(room.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: ShopScreen(controller: room),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.widgetWithText(ChoiceChip, 'Tables'), findsOneWidget);
      expect(find.byType(FurnitureThumbnail).evaluate().length, lessThan(20));
      await tester.tap(find.widgetWithText(ChoiceChip, 'Tables'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('shop-sort')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Price'));
      await tester.tap(find.text('Low to high'));
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.text('Price ↑'), findsOneWidget);
      final first = find.byKey(const ValueKey('product-studio-table-0-0'));
      await tester.ensureVisible(first);
      await tester.tap(first);
      await tester.pumpAndSettle();
      expect(find.byType(FurniturePreviewStage), findsOneWidget);
      expect(find.text('More tables'), findsOneWidget);
      await tester.tap(find.text('Buy · 55 Likes'));
      await tester.pumpAndSettle();
      expect(room.ownedCount('studio-table-0-0'), 1);
      await tester.drag(
        find.byType(CustomScrollView).last,
        const Offset(0, -400),
      );
      await tester.pumpAndSettle();
      final related = find.byKey(const ValueKey('related-studio-table-1-0'));
      await tester.scrollUntilVisible(
        related,
        150,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(related);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FurniturePreviewStage>(find.byType(FurniturePreviewStage))
            .definition!
            .id,
        'studio-table-1-0',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('catalog visual contact sheets from the real mesh', (
    tester,
  ) async {
    if (Platform.environment['RENDER_FURNITURE'] != '1') return;
    await tester.runAsync(() async {
      final font = FontLoader('FurniturePreviewSans')
        ..addFont(rootBundle.load('assets/keyboard/NotoSansSC-Regular.otf'));
      await font.load();
    });
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final key = GlobalKey();
    for (final kind in RoomItemVisualKind.values) {
      final items = expandedFurnitureCatalog
          .where((e) => e.visualKind == kind)
          .toList();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(fontFamily: 'FurniturePreviewSans'),
          home: RepaintBoundary(
            key: key,
            child: Material(
              color: const Color(0xFFF5EBDF),
              child: Column(
                children: [
                  Text(
                    '${kind.label} — 10 structures × 3 finishes',
                    style: const TextStyle(fontSize: 26),
                  ),
                  Expanded(
                    child: GridView.count(
                      crossAxisCount: 10,
                      childAspectRatio: .46,
                      children: [
                        for (var finish = 0; finish < 3; finish++)
                          for (var form = 0; form < 10; form++)
                            Column(
                              children: [
                                FurnitureMeshThumbnail(
                                  definition: items[form * 3 + finish],
                                  size: 136,
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(4),
                                  child: Text(
                                    items[form * 3 + finish].title,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                              ],
                            ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          '/private/tmp/furniture-${kind.name}.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
