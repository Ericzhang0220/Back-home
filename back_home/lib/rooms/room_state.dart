import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'room_placement.dart';

part 'furniture_catalog.dart';

enum RoomItemCategory { statement, storage, seating, decor, lighting }

enum RoomItemVisualKind {
  bed,
  nightstand,
  wardrobe,
  vanity,
  ottoman,
  floorLamp,
  plant,
  table,
  chair,
  sofa,
  bookshelf,
}

/// Weather shown in the sky beyond the window.
enum SkyWeather { clear, cloudy, overcast, rain }

/// Scenery outside the room's window.
enum OutdoorEnvironment { island, waterfall, city, forest }

class GridPoint {
  const GridPoint(this.x, this.z);

  final double x;
  final double z;

  GridPoint copyWith({double? x, double? z}) =>
      GridPoint(x ?? this.x, z ?? this.z);

  @override
  bool operator ==(Object other) {
    return other is GridPoint && other.x == x && other.z == z;
  }

  @override
  int get hashCode => Object.hash(x, z);
}

class GridSize {
  const GridSize(this.width, this.depth);

  final int width;
  final int depth;
}

class RoomActionResult {
  const RoomActionResult.success(this.message, {this.instanceId})
    : isSuccess = true;

  const RoomActionResult.failure(this.message)
    : isSuccess = false,
      instanceId = null;

  final bool isSuccess;
  final String message;
  final String? instanceId;
}

class RoomEditSnapshot {
  RoomEditSnapshot({
    required Iterable<PlacedRoomItem> placedItems,
    required this.selectedItemId,
    required this.nextInstanceId,
  }) : placedItems = List.unmodifiable(
         placedItems.map(
           (item) => item.copyWith(origin: item.origin.copyWith()),
         ),
       );

  final List<PlacedRoomItem> placedItems;
  final String? selectedItemId;
  final int nextInstanceId;
}

class RoomItemDefinition {
  const RoomItemDefinition({
    required this.id,
    required this.title,
    required this.typeLabel,
    required this.category,
    required this.price,
    required this.icon,
    required this.tint,
    required this.description,
    required this.visualKind,
    required this.width,
    required this.depth,
    this.canRotate = true,
    this.design,
  });

  final String id;
  final String title;
  final String typeLabel;
  final RoomItemCategory category;
  final int price;
  final IconData icon;
  final Color tint;
  final String description;
  final RoomItemVisualKind visualKind;
  final int width;
  final int depth;
  final bool canRotate;
  final FurnitureDesign? design;

  GridSize footprintForRotation(int quarterTurns) {
    final normalizedTurns = quarterTurns % 2;
    if (normalizedTurns == 1) {
      return GridSize(depth, width);
    }
    return GridSize(width, depth);
  }
}

class PlacedRoomItem {
  const PlacedRoomItem({
    required this.instanceId,
    required this.definitionId,
    required this.origin,
    int rotationQuarterTurns = 0,
    double? rotationDegrees,
    this.elevation = 0,
  }) : rotationDegrees = rotationDegrees ?? rotationQuarterTurns * 90.0;

  final String instanceId;
  final String definitionId;
  final GridPoint origin;
  final double rotationDegrees;
  final double elevation;

  int get rotationQuarterTurns => (rotationDegrees / 90).round() % 4;

  PlacedRoomItem copyWith({
    String? instanceId,
    String? definitionId,
    GridPoint? origin,
    int? rotationQuarterTurns,
    double? rotationDegrees,
    double? elevation,
  }) {
    return PlacedRoomItem(
      instanceId: instanceId ?? this.instanceId,
      definitionId: definitionId ?? this.definitionId,
      origin: origin ?? this.origin,
      elevation: elevation ?? this.elevation,
      rotationDegrees:
          rotationDegrees ??
          (rotationQuarterTurns == null
              ? this.rotationDegrees
              : rotationQuarterTurns * 90.0),
    );
  }
}

class RoomEditorController extends ChangeNotifier {
  RoomEditorController()
    : _catalog = [
        RoomItemDefinition(
          id: 'sunset-bed',
          title: 'Sunset bed',
          typeLabel: 'Statement',
          category: RoomItemCategory.statement,
          price: 120,
          icon: Icons.bed_rounded,
          tint: const Color(0xFFF3D9CE),
          description:
              'Low-profile bed with a soft clay duvet and stacked pillows.',
          visualKind: RoomItemVisualKind.bed,
          width: 3,
          depth: 4,
          canRotate: true,
        ),
        RoomItemDefinition(
          id: 'soft-nightstand',
          title: 'Soft nightstand',
          typeLabel: 'Storage',
          category: RoomItemCategory.storage,
          price: 42,
          icon: Icons.nightlight_round_rounded,
          tint: const Color(0xFFF3E8D7),
          description: 'Compact drawer table that pairs with beds or windows.',
          visualKind: RoomItemVisualKind.nightstand,
          width: 1,
          depth: 1,
        ),
        RoomItemDefinition(
          id: 'linen-wardrobe',
          title: 'Linen wardrobe',
          typeLabel: 'Storage',
          category: RoomItemCategory.storage,
          price: 95,
          icon: Icons.door_sliding_rounded,
          tint: const Color(0xFFF1E4C6),
          description:
              'Tall wardrobe for anchoring a wall and balancing the layout.',
          visualKind: RoomItemVisualKind.wardrobe,
          width: 2,
          depth: 1,
        ),
        RoomItemDefinition(
          id: 'mirror-vanity',
          title: 'Mirror vanity',
          typeLabel: 'Furniture',
          category: RoomItemCategory.statement,
          price: 86,
          icon: Icons.table_restaurant_rounded,
          tint: const Color(0xFFE9DDD0),
          description:
              'Slim desk with mirror and stool for the right-side wall.',
          visualKind: RoomItemVisualKind.vanity,
          width: 2,
          depth: 1,
        ),
        RoomItemDefinition(
          id: 'cloud-ottoman',
          title: 'Cloud ottoman',
          typeLabel: 'Seating',
          category: RoomItemCategory.seating,
          price: 58,
          icon: Icons.weekend_rounded,
          tint: const Color(0xFFF0D8D2),
          description:
              'Moveable accent stool for empty corners and desk setups.',
          visualKind: RoomItemVisualKind.ottoman,
          width: 1,
          depth: 1,
        ),
        RoomItemDefinition(
          id: 'dusk-lamp',
          title: 'Dusk lamp',
          typeLabel: 'Lighting',
          category: RoomItemCategory.lighting,
          price: 48,
          icon: Icons.light_rounded,
          tint: const Color(0xFFEBDDC7),
          description: 'Warm lamp with a cone shade for gentle evening light.',
          visualKind: RoomItemVisualKind.floorLamp,
          width: 1,
          depth: 1,
        ),
        RoomItemDefinition(
          id: 'fern-tree',
          title: 'Fern tree',
          typeLabel: 'Decor',
          category: RoomItemCategory.decor,
          price: 34,
          icon: Icons.local_florist_rounded,
          tint: const Color(0xFFD7E6D6),
          description:
              'Tall plant that softens the room edges and empty tiles.',
          visualKind: RoomItemVisualKind.plant,
          width: 1,
          depth: 1,
        ),
        ...expandedFurnitureCatalog,
      ],
      _ownedCounts = {
        'sunset-bed': 1,
        'soft-nightstand': 2,
        'linen-wardrobe': 1,
        'mirror-vanity': 1,
        'cloud-ottoman': 1,
        'dusk-lamp': 1,
        'fern-tree': 0,
      },
      // A new user starts with just the bed placed. The desk, window, sofa and
      // door are built-in room decor (see IsometricRoomView), so the starter
      // room reads as "bed, desk, window, sofa, door" out of the box.
      _placedItems = [
        const PlacedRoomItem(
          instanceId: 'item-1',
          definitionId: 'sunset-bed',
          origin: GridPoint(3, 3),
          rotationQuarterTurns: 0,
        ),
      ] {
    _definitionsById = {
      for (final definition in _catalog) definition.id: definition,
    };
  }

  RoomEditorController.editing(RoomEditorController source)
    : viewPose = source.viewPose,
      _catalog = List<RoomItemDefinition>.of(source._catalog),
      _ownedCounts = Map<String, int>.of(source._ownedCounts),
      _placedItems = [
        for (final item in source._placedItems)
          item.copyWith(origin: item.origin.copyWith()),
      ],
      _likesBalance = source._likesBalance,
      _nextInstanceId = source._nextInstanceId,
      _selectedItemId = source._selectedItemId {
    _definitionsById = {
      for (final definition in _catalog) definition.id: definition,
    };
  }

  static const int roomWidth = 10;
  // Depth runs front-to-back. The original decorated room (back wall, window,
  // desk, starter furniture) all anchor to the far -Z wall, so they occupy the
  // far half; the near half is open floor with the camera standing in the
  // middle. Was 8 (the old single-room depth); doubling it keeps the existing
  // content as roughly the far half of this larger room.
  static const int roomDepth = 16;
  static const double cellSize = 1.0;

  final List<RoomItemDefinition> _catalog;
  final Map<String, int> _ownedCounts;
  final List<PlacedRoomItem> _placedItems;
  late final Map<String, RoomItemDefinition> _definitionsById;

  int _likesBalance = 238;
  int _nextInstanceId = 7;
  String? _selectedItemId;

  RoomViewPose viewPose = defaultRoomViewPose;

  int get likesBalance => _likesBalance;
  Map<String, dynamic> get inventoryRecord => {
    'placementVersion': 2,
    'owned': Map<String, int>.of(_ownedCounts),
    'nextId': _nextInstanceId,
    'placed': [
      for (final item in _placedItems)
        {
          'id': item.instanceId,
          'definition': item.definitionId,
          'x': item.origin.x,
          'z': item.origin.z,
          'rotation': item.rotationDegrees,
          'elevation': item.elevation,
        },
    ],
  };

  void restoreInventory(Map<String, dynamic>? data) {
    final starter = RoomEditorController();
    final counts = Map<String, int>.of(starter._ownedCounts);
    final items = List<PlacedRoomItem>.of(starter._placedItems);
    var nextId = starter._nextInstanceId;
    starter.dispose();
    if (data != null) {
      counts.clear();
      for (final entry in (data['owned'] as Map).entries) {
        if (_definitionsById.containsKey(entry.key) &&
            entry.value is int &&
            entry.value >= 0) {
          counts[entry.key as String] = entry.value as int;
        }
      }
      items.clear();
      for (final raw in data['placed'] as List) {
        final item = raw as Map;
        final definition = item['definition'] as String;
        if (!_definitionsById.containsKey(definition)) continue;
        if (items.where((entry) => entry.definitionId == definition).length >=
            (counts[definition] ?? 0)) {
          continue;
        }
        final degrees = (item['rotation'] as num).toDouble();
        var origin = GridPoint((item['x'] as num).toDouble(), (item['z'] as num).toDouble());
        if (data['placementVersion'] != 2) {
          final design = definitionFor(definition);
          final oldSize = design.footprintForRotation((degrees / 90).round() % 4);
          origin = GridPoint(origin.x + (oldSize.width - design.width) / 2,
            origin.z + (oldSize.depth - design.depth) / 2);
        }
        items.add(PlacedRoomItem(
          instanceId: item['id'] as String,
          definitionId: definition,
          origin: origin,
          rotationDegrees: degrees,
          elevation: (item['elevation'] as num?)?.toDouble() ?? 0,
        ));
      }
      nextId = data['nextId'] as int;
    }
    _ownedCounts
      ..clear()
      ..addAll(counts);
    _placedItems
      ..clear()
      ..addAll(items);
    _nextInstanceId = nextId;
    _selectedItemId = null;
    notifyListeners();
  }

  bool shopPurchaseLocked = false;

  /// Restores the shared local shop wallet, including keyboard purchases.
  void restoreLikesBalance(int value) {
    if (value < 0) throw ArgumentError.value(value, 'value');
    if (_likesBalance == value) return;
    _likesBalance = value;
    notifyListeners();
  }

  String? get selectedItemId => _selectedItemId;

  UnmodifiableListView<RoomItemDefinition> get catalog =>
      UnmodifiableListView(_catalog);

  UnmodifiableListView<PlacedRoomItem> get placedItems =>
      UnmodifiableListView(_placedItems);

  List<RoomItemDefinition> get ownedCatalog {
    return _catalog
        .where((definition) => ownedCount(definition.id) > 0)
        .toList();
  }

  RoomItemDefinition definitionFor(String definitionId) {
    return _definitionsById[definitionId]!;
  }

  PlacedRoomItem? placedItemById(String instanceId) {
    for (final item in _placedItems) {
      if (item.instanceId == instanceId) {
        return item;
      }
    }
    return null;
  }

  int ownedCount(String definitionId) => _ownedCounts[definitionId] ?? 0;

  int placedCount(String definitionId) {
    var count = 0;
    for (final item in _placedItems) {
      if (item.definitionId == definitionId) {
        count += 1;
      }
    }
    return count;
  }

  int availableToPlace(String definitionId) {
    return ownedCount(definitionId) - placedCount(definitionId);
  }

  GridSize footprintForDefinition(String definitionId, int quarterTurns) {
    return definitionFor(definitionId).footprintForRotation(quarterTurns);
  }

  static const _wallClearance = .21;
  static const _ceiling = 4.8;

  GridPoint clampOrigin(String definitionId, int quarterTurns, GridPoint origin, {double? rotationDegrees}) {
    final box = roomPlacementBox(definitionFor(definitionId), origin, rotationDegrees ?? quarterTurns * 90, 0);
    return GridPoint(
      origin.x + box.x.clamp(_wallClearance + box.extentX, roomWidth - _wallClearance - box.extentX) - box.x,
      origin.z + box.z.clamp(_wallClearance + box.extentZ, roomDepth - _wallClearance - box.extentZ) - box.z,
    );
  }

  RoomPlacementBox placementBox(PlacedRoomItem item) =>
      roomPlacementBox(definitionFor(item.definitionId), item.origin, item.rotationDegrees, item.elevation);

  bool canOccupy({
    required String definitionId,
    required GridPoint origin,
    required int rotationQuarterTurns,
    double? rotationDegrees,
    double elevation = 0,
    String? ignoringInstanceId,
  }) {
    final box = roomPlacementBox(definitionFor(definitionId), origin,
      rotationDegrees ?? rotationQuarterTurns * 90, elevation);
    const tolerance = .001;
    if (elevation < 0 || box.bottom < -.025 || box.top > _ceiling + tolerance ||
        box.x - box.extentX < _wallClearance - tolerance ||
        box.x + box.extentX > roomWidth - _wallClearance + tolerance ||
        box.z - box.extentZ < _wallClearance - tolerance ||
        box.z + box.extentZ > roomDepth - _wallClearance + tolerance) {
      return false;
    }
    return !_placedItems.any((item) =>
      item.instanceId != ignoringInstanceId && box.overlaps(placementBox(item)));
  }

  GridPoint? findFirstOpenSpot(String definitionId, {int quarterTurns = 0, GridPoint? preferredOrigin}) {
    GridPoint? tryOrigin(GridPoint candidate) {
      final origin = clampOrigin(definitionId, quarterTurns, candidate);
      return canOccupy(definitionId: definitionId, origin: origin, rotationQuarterTurns: quarterTurns)
          ? origin : null;
    }
    if (preferredOrigin != null) {
      final preferred = tryOrigin(preferredOrigin);
      if (preferred != null) return preferred;
    }
    final design = definitionFor(definitionId);
    final forwardX = math.sin(viewPose.yaw);
    final forwardZ = -math.cos(viewPose.yaw);
    GridPoint atDistance(double distance, double lateral) => GridPoint(
      viewPose.x + roomWidth / 2 + distance * forwardX - lateral * forwardZ - design.width / 2,
      viewPose.z + roomDepth / 2 + distance * forwardZ + lateral * forwardX - design.depth / 2,
    );
    final minimumDistance = math.max(2.4, math.max(design.width, design.depth) * .65 + .9);
    for (var distance = minimumDistance; distance <= 8; distance += .5) {
      for (final lateral in [0.0, -.45, .45, -.9, .9, -1.4, 1.4]) {
        final origin = tryOrigin(atDistance(distance, lateral));
        if (origin == null) continue;
        final dx = origin.x + design.width / 2 - roomWidth / 2 - viewPose.x;
        final dz = origin.z + design.depth / 2 - roomDepth / 2 - viewPose.z;
        if (dx * forwardX + dz * forwardZ >= minimumDistance - .1 &&
            (dx * forwardZ - dz * forwardX).abs() <= distance * .48) {
          return origin;
        }
      }
    }
    // When the camera faces a nearby wall, find a nearby open spot to frame.
    final candidates = [
      for (var z = 0.0; z <= roomDepth; z += .5)
        for (var x = 0.0; x <= roomWidth; x += .5) GridPoint(x, z),
    ];
    final ideal = atDistance(minimumDistance, 0);
    double distanceToIdeal(GridPoint point) =>
        (point.x - ideal.x) * (point.x - ideal.x) + (point.z - ideal.z) * (point.z - ideal.z);
    candidates.sort((a, b) => distanceToIdeal(a).compareTo(distanceToIdeal(b)));
    for (final candidate in candidates) {
      final origin = tryOrigin(candidate);
      if (origin == null) continue;
      final box = roomPlacementBox(design, origin, quarterTurns * 90, 0);
      if (!box.blocksEye(viewPose.x, viewPose.y, viewPose.z, .35)) return origin;
    }
    return null;
  }

  void selectItem(String? instanceId) {
    if (_selectedItemId == instanceId) {
      return;
    }

    _selectedItemId = instanceId;
    notifyListeners();
  }

  void applyEditSession(RoomEditorController edited) {
    _ownedCounts
      ..clear()
      ..addAll(edited._ownedCounts);
    _placedItems
      ..clear()
      ..addAll([
        for (final item in edited._placedItems)
          item.copyWith(origin: item.origin.copyWith()),
      ]);
    _nextInstanceId = edited._nextInstanceId;
    _selectedItemId = edited._selectedItemId;
    notifyListeners();
  }

  RoomEditSnapshot createEditSnapshot() {
    return RoomEditSnapshot(
      placedItems: _placedItems,
      selectedItemId: _selectedItemId,
      nextInstanceId: _nextInstanceId,
    );
  }

  void restoreEditSnapshot(RoomEditSnapshot snapshot) {
    _placedItems
      ..clear()
      ..addAll([
        for (final item in snapshot.placedItems)
          item.copyWith(origin: item.origin.copyWith()),
      ]);
    _selectedItemId = snapshot.selectedItemId;
    _nextInstanceId = snapshot.nextInstanceId;
    notifyListeners();
  }

  GridPoint centerOriginFor(String definitionId, {int quarterTurns = 0}) {
    final footprint = footprintForDefinition(definitionId, quarterTurns);
    final centered = GridPoint(
      (roomWidth - footprint.width) / 2,
      (roomDepth - footprint.depth) / 2,
    );
    return clampOrigin(definitionId, quarterTurns, centered);
  }

  RoomActionResult addOwnedItemForEditing(
    String definitionId, {
    GridPoint? preferredOrigin,
    int rotationQuarterTurns = 0,
  }) => addOwnedItem(definitionId,
    preferredOrigin: preferredOrigin, rotationQuarterTurns: rotationQuarterTurns);

  bool isPlacedItemValid(String instanceId) {
    final item = placedItemById(instanceId);
    if (item == null) {
      return false;
    }
    return canOccupy(
      definitionId: item.definitionId,
      origin: item.origin,
      rotationQuarterTurns: item.rotationQuarterTurns,
      ignoringInstanceId: item.instanceId,
    );
  }

  bool get hasValidLayout {
    for (final item in _placedItems) {
      if (!isPlacedItemValid(item.instanceId)) {
        return false;
      }
    }
    return true;
  }

  /// Records a furniture purchase coordinated by the shop wallet.
  void addPurchasedItem(String definitionId) {
    definitionFor(definitionId);
    _ownedCounts[definitionId] = ownedCount(definitionId) + 1;
    notifyListeners();
  }

  RoomActionResult purchaseItem(String definitionId) {
    if (shopPurchaseLocked) {
      return RoomActionResult.failure('Another purchase is being saved.');
    }
    final definition = definitionFor(definitionId);
    if (_likesBalance < definition.price) {
      return RoomActionResult.failure(
        'Not enough likes for ${definition.title}.',
      );
    }

    _likesBalance -= definition.price;
    addPurchasedItem(definitionId);
    return RoomActionResult.success(
      '${definition.title} added to your inventory.',
    );
  }

  RoomActionResult addOwnedItem(
    String definitionId, {
    GridPoint? preferredOrigin,
    int rotationQuarterTurns = 0,
  }) {
    final definition = definitionFor(definitionId);

    if (availableToPlace(definitionId) <= 0) {
      return RoomActionResult.failure(
        'Buy ${definition.title} from the shop first.',
      );
    }

    final origin = findFirstOpenSpot(definitionId, quarterTurns: rotationQuarterTurns, preferredOrigin: preferredOrigin);

    if (origin == null) {
      return RoomActionResult.failure(
        'No open room space left for ${definition.title}.',
      );
    }

    final item = PlacedRoomItem(
      instanceId: 'item-${_nextInstanceId++}',
      definitionId: definitionId,
      origin: origin,
      rotationQuarterTurns: rotationQuarterTurns,
    );

    _placedItems.add(item);
    _selectedItemId = item.instanceId;
    notifyListeners();
    return RoomActionResult.success(
      '${definition.title} placed in the room.',
      instanceId: item.instanceId,
    );
  }

  RoomActionResult buyAndAddItem(String definitionId) {
    if (shopPurchaseLocked) {
      return RoomActionResult.failure('Another purchase is being saved.');
    }
    final definition = definitionFor(definitionId);
    if (_likesBalance < definition.price) {
      return RoomActionResult.failure(
        'Not enough likes for ${definition.title}.',
      );
    }

    final origin = findFirstOpenSpot(definitionId);
    _likesBalance -= definition.price;
    _ownedCounts[definitionId] = ownedCount(definitionId) + 1;

    if (origin == null) {
      notifyListeners();
      return RoomActionResult.success(
        '${definition.title} purchased, but the room is full.',
      );
    }

    final item = PlacedRoomItem(
      instanceId: 'item-${_nextInstanceId++}',
      definitionId: definitionId,
      origin: origin,
      rotationQuarterTurns: 0,
    );

    _placedItems.add(item);
    _selectedItemId = item.instanceId;
    notifyListeners();
    return RoomActionResult.success(
      '${definition.title} purchased and placed.',
      instanceId: item.instanceId,
    );
  }

  RoomActionResult movePlacedItem(String instanceId, GridPoint origin, {double? elevation}) {
    final itemIndex = _placedItems.indexWhere(
      (item) => item.instanceId == instanceId,
    );
    if (itemIndex == -1) {
      return const RoomActionResult.failure(
        'That furniture item no longer exists.',
      );
    }

    final item = _placedItems[itemIndex];
    final clampedOrigin = clampOrigin(
      item.definitionId,
      item.rotationQuarterTurns,
      origin,
      rotationDegrees: item.rotationDegrees,
    );

    final height = math.max(0.0, elevation ?? item.elevation);
    if (!canOccupy(
      definitionId: item.definitionId,
      origin: clampedOrigin,
      rotationQuarterTurns: item.rotationQuarterTurns,
      rotationDegrees: item.rotationDegrees,
      elevation: item.elevation,
      rotationDegrees: item.rotationDegrees,
      elevation: height,
      ignoringInstanceId: instanceId,
    )) {
      return const RoomActionResult.failure(
        'Furniture must fit without overlapping another item.',
      );
    }

    if (item.origin == clampedOrigin && item.elevation == height) {
      return const RoomActionResult.success('Furniture stayed in place.');
    }

    _placedItems[itemIndex] = item.copyWith(origin: clampedOrigin, elevation: height);
    notifyListeners();
    return const RoomActionResult.success('Furniture moved.');
  }

  RoomActionResult rotatePlacedItem(
    String instanceId, {
    double deltaDegrees = 90,
  }) {
    final itemIndex = _placedItems.indexWhere(
      (item) => item.instanceId == instanceId,
    );
    if (itemIndex == -1) {
      return const RoomActionResult.failure(
        'That furniture item no longer exists.',
      );
    }

    final item = _placedItems[itemIndex];
    final definition = definitionFor(item.definitionId);
    if (!definition.canRotate) {
      return RoomActionResult.failure('${definition.title} cannot rotate.');
    }

    final nextDegrees = (item.rotationDegrees + deltaDegrees) % 360;
    if (!canOccupy(
      definitionId: item.definitionId, origin: item.origin,
      rotationQuarterTurns: item.rotationQuarterTurns,
      rotationDegrees: nextDegrees, elevation: item.elevation,
      ignoringInstanceId: instanceId,
    )) {
      return const RoomActionResult.failure('No room to rotate here.');
    }
    _placedItems[itemIndex] = item.copyWith(rotationDegrees: nextDegrees);
    notifyListeners();
    return RoomActionResult.success('${definition.title} rotated.');
  }

  RoomActionResult storePlacedItem(String instanceId) {
    final itemIndex = _placedItems.indexWhere(
      (item) => item.instanceId == instanceId,
    );
    if (itemIndex == -1) {
      return const RoomActionResult.failure(
        'That furniture item no longer exists.',
      );
    }

    final removed = _placedItems.removeAt(itemIndex);
    if (_selectedItemId == removed.instanceId) {
      _selectedItemId = null;
    }
    notifyListeners();
    return RoomActionResult.success(
      '${definitionFor(removed.definitionId).title} returned to inventory.',
    );
  }
}
