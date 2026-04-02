import 'dart:collection';

import 'package:flutter/material.dart';

enum RoomItemCategory { statement, storage, seating, decor, lighting }

enum RoomItemVisualKind {
  bed,
  nightstand,
  wardrobe,
  vanity,
  ottoman,
  floorLamp,
  plant,
}

class GridPoint {
  const GridPoint(this.x, this.z);

  final int x;
  final int z;

  GridPoint copyWith({int? x, int? z}) => GridPoint(x ?? this.x, z ?? this.z);

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
    required this.rotationQuarterTurns,
  });

  final String instanceId;
  final String definitionId;
  final GridPoint origin;
  final int rotationQuarterTurns;

  PlacedRoomItem copyWith({
    String? instanceId,
    String? definitionId,
    GridPoint? origin,
    int? rotationQuarterTurns,
  }) {
    return PlacedRoomItem(
      instanceId: instanceId ?? this.instanceId,
      definitionId: definitionId ?? this.definitionId,
      origin: origin ?? this.origin,
      rotationQuarterTurns: rotationQuarterTurns ?? this.rotationQuarterTurns,
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
      _placedItems = [
        const PlacedRoomItem(
          instanceId: 'item-1',
          definitionId: 'sunset-bed',
          origin: GridPoint(1, 2),
          rotationQuarterTurns: 0,
        ),
        const PlacedRoomItem(
          instanceId: 'item-2',
          definitionId: 'soft-nightstand',
          origin: GridPoint(0, 4),
          rotationQuarterTurns: 0,
        ),
        const PlacedRoomItem(
          instanceId: 'item-3',
          definitionId: 'linen-wardrobe',
          origin: GridPoint(6, 0),
          rotationQuarterTurns: 0,
        ),
        const PlacedRoomItem(
          instanceId: 'item-4',
          definitionId: 'mirror-vanity',
          origin: GridPoint(6, 5),
          rotationQuarterTurns: 0,
        ),
        const PlacedRoomItem(
          instanceId: 'item-5',
          definitionId: 'cloud-ottoman',
          origin: GridPoint(7, 6),
          rotationQuarterTurns: 0,
        ),
        const PlacedRoomItem(
          instanceId: 'item-6',
          definitionId: 'dusk-lamp',
          origin: GridPoint(0, 6),
          rotationQuarterTurns: 0,
        ),
      ] {
    _definitionsById = {
      for (final definition in _catalog) definition.id: definition,
    };
  }

  static const int roomWidth = 10;
  static const int roomDepth = 8;
  static const double cellSize = 1.0;

  final List<RoomItemDefinition> _catalog;
  final Map<String, int> _ownedCounts;
  final List<PlacedRoomItem> _placedItems;
  late final Map<String, RoomItemDefinition> _definitionsById;

  int _likesBalance = 238;
  int _nextInstanceId = 7;
  String? _selectedItemId;

  int get likesBalance => _likesBalance;
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

  GridPoint clampOrigin(
    String definitionId,
    int quarterTurns,
    GridPoint origin,
  ) {
    final footprint = footprintForDefinition(definitionId, quarterTurns);
    final clampedX = origin.x.clamp(0, roomWidth - footprint.width);
    final clampedZ = origin.z.clamp(0, roomDepth - footprint.depth);
    return GridPoint(clampedX, clampedZ);
  }

  bool canOccupy({
    required String definitionId,
    required GridPoint origin,
    required int rotationQuarterTurns,
    String? ignoringInstanceId,
  }) {
    final footprint = footprintForDefinition(
      definitionId,
      rotationQuarterTurns,
    );

    if (origin.x < 0 ||
        origin.z < 0 ||
        origin.x + footprint.width > roomWidth ||
        origin.z + footprint.depth > roomDepth) {
      return false;
    }

    for (final item in _placedItems) {
      if (item.instanceId == ignoringInstanceId) {
        continue;
      }

      final otherFootprint = footprintForDefinition(
        item.definitionId,
        item.rotationQuarterTurns,
      );

      final overlaps =
          origin.x < item.origin.x + otherFootprint.width &&
          origin.x + footprint.width > item.origin.x &&
          origin.z < item.origin.z + otherFootprint.depth &&
          origin.z + footprint.depth > item.origin.z;

      if (overlaps) {
        return false;
      }
    }

    return true;
  }

  GridPoint? findFirstOpenSpot(String definitionId, {int quarterTurns = 0}) {
    final footprint = footprintForDefinition(definitionId, quarterTurns);

    for (var z = 0; z <= roomDepth - footprint.depth; z += 1) {
      for (var x = 0; x <= roomWidth - footprint.width; x += 1) {
        final origin = GridPoint(x, z);
        if (canOccupy(
          definitionId: definitionId,
          origin: origin,
          rotationQuarterTurns: quarterTurns,
        )) {
          return origin;
        }
      }
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

  RoomActionResult purchaseItem(String definitionId) {
    final definition = definitionFor(definitionId);
    if (_likesBalance < definition.price) {
      return RoomActionResult.failure(
        'Not enough likes for ${definition.title}.',
      );
    }

    _likesBalance -= definition.price;
    _ownedCounts[definitionId] = ownedCount(definitionId) + 1;
    notifyListeners();
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

    final clampedPreferred = preferredOrigin == null
        ? null
        : clampOrigin(definitionId, rotationQuarterTurns, preferredOrigin);

    final origin =
        clampedPreferred != null &&
            canOccupy(
              definitionId: definitionId,
              origin: clampedPreferred,
              rotationQuarterTurns: rotationQuarterTurns,
            )
        ? clampedPreferred
        : findFirstOpenSpot(definitionId, quarterTurns: rotationQuarterTurns);

    if (origin == null) {
      return RoomActionResult.failure(
        'No open grid space left for ${definition.title}.',
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

  RoomActionResult movePlacedItem(String instanceId, GridPoint origin) {
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
    );

    if (!canOccupy(
      definitionId: item.definitionId,
      origin: clampedOrigin,
      rotationQuarterTurns: item.rotationQuarterTurns,
      ignoringInstanceId: instanceId,
    )) {
      return const RoomActionResult.failure(
        'That tile is blocked by another item.',
      );
    }

    if (item.origin == clampedOrigin) {
      return const RoomActionResult.success('Furniture stayed in place.');
    }

    _placedItems[itemIndex] = item.copyWith(origin: clampedOrigin);
    notifyListeners();
    return const RoomActionResult.success('Furniture moved.');
  }

  RoomActionResult rotatePlacedItem(String instanceId) {
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

    final nextTurns = (item.rotationQuarterTurns + 1) % 4;
    final clampedOrigin = clampOrigin(
      item.definitionId,
      nextTurns,
      item.origin,
    );

    if (!canOccupy(
      definitionId: item.definitionId,
      origin: clampedOrigin,
      rotationQuarterTurns: nextTurns,
      ignoringInstanceId: item.instanceId,
    )) {
      return const RoomActionResult.failure(
        'Not enough open tiles to rotate that item.',
      );
    }

    _placedItems[itemIndex] = item.copyWith(
      origin: clampedOrigin,
      rotationQuarterTurns: nextTurns,
    );
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
