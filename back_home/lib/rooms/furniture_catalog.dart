part of 'room_state.dart';

/// Stable recipe IDs: never reorder forms or finishes after publishing.
@immutable
class FurnitureDesign {
  const FurnitureDesign(this.form, this.finish);
  final int form;
  final int finish;
}

extension FurnitureDepartment on RoomItemVisualKind {
  String get label => switch (this) {
    RoomItemVisualKind.bed => 'Beds',
    RoomItemVisualKind.nightstand => 'Nightstands',
    RoomItemVisualKind.wardrobe => 'Wardrobes',
    RoomItemVisualKind.vanity => 'Desks & vanities',
    RoomItemVisualKind.ottoman => 'Ottomans & benches',
    RoomItemVisualKind.floorLamp => 'Lighting',
    RoomItemVisualKind.plant => 'Plants',
    RoomItemVisualKind.table => 'Tables',
    RoomItemVisualKind.chair => 'Chairs',
    RoomItemVisualKind.sofa => 'Sofas',
    RoomItemVisualKind.bookshelf => 'Shelving',
  };
  IconData get icon => switch (this) {
    RoomItemVisualKind.bed => Icons.bed_outlined,
    RoomItemVisualKind.nightstand => Icons.bedroom_parent_outlined,
    RoomItemVisualKind.wardrobe => Icons.door_sliding_outlined,
    RoomItemVisualKind.vanity => Icons.desk_outlined,
    RoomItemVisualKind.ottoman => Icons.weekend_outlined,
    RoomItemVisualKind.floorLamp => Icons.light_outlined,
    RoomItemVisualKind.plant => Icons.local_florist_outlined,
    RoomItemVisualKind.table => Icons.table_restaurant_outlined,
    RoomItemVisualKind.chair => Icons.chair_alt_outlined,
    RoomItemVisualKind.sofa => Icons.chair_outlined,
    RoomItemVisualKind.bookshelf => Icons.shelves,
  };
  RoomItemCategory get category => switch (this) {
    RoomItemVisualKind.nightstand ||
    RoomItemVisualKind.wardrobe ||
    RoomItemVisualKind.bookshelf => RoomItemCategory.storage,
    RoomItemVisualKind.chair ||
    RoomItemVisualKind.sofa ||
    RoomItemVisualKind.ottoman => RoomItemCategory.seating,
    RoomItemVisualKind.floorLamp => RoomItemCategory.lighting,
    RoomItemVisualKind.plant => RoomItemCategory.decor,
    _ => RoomItemCategory.statement,
  };
}

const furnitureForms = <RoomItemVisualKind, List<String>>{
  RoomItemVisualKind.table: [
    'Square dining table',
    'Round pedestal table',
    'Long trestle table',
    'Oval dining table',
    'Drop-leaf table',
    'Round coffee table',
    'Nesting tables',
    'Console table',
    'Cross-leg dining table',
    'Octagonal bistro table',
  ],
  RoomItemVisualKind.bed: [
    'Platform bed',
    'Spindle bed',
    'Four-poster bed',
    'Storage bed',
    'Daybed',
    'Bunk bed',
    'Sleigh bed',
    'Wingback bed',
    'Canopy bed',
    'Slatted bed',
  ],
  RoomItemVisualKind.nightstand: [
    'One-drawer nightstand',
    'Open bedside shelf',
    'Round bedside table',
    'Three-drawer nightstand',
    'Door bedside cabinet',
    'Cane bedside cabinet',
    'Fluted nightstand',
    'Tray bedside table',
    'C-leg bedside table',
    'Twin-tier bedside table',
  ],
  RoomItemVisualKind.wardrobe: [
    'Panel wardrobe',
    'Three-door wardrobe',
    'Sliding wardrobe',
    'Mirrored wardrobe',
    'Open clothes rail',
    'Drawer wardrobe',
    'Louvered wardrobe',
    'Arch wardrobe',
    'Cane wardrobe',
    'Wardrobe with side shelves',
  ],
  RoomItemVisualKind.vanity: [
    'Writing desk',
    'Round-mirror vanity',
    'Double-pedestal desk',
    'L-shaped desk',
    'Secretary desk',
    'Standing desk',
    'Trestle desk',
    'Hutch desk',
    'Dressing table',
    'Corner vanity',
  ],
  RoomItemVisualKind.ottoman: [
    'Round pouf',
    'Square ottoman',
    'Storage bench',
    'Tufted bench',
    'Slatted bench',
    'Oval footstool',
    'Drum ottoman',
    'Tripod stool',
    'Saddle stool',
    'Bolster bench',
  ],
  RoomItemVisualKind.floorLamp: [
    'Cone floor lamp',
    'Tripod lamp',
    'Arc lamp',
    'Globe lamp',
    'Twin-arm lamp',
    'Paper lantern lamp',
    'Shelf lamp',
    'Mushroom table lamp',
    'Task lamp',
    'Three-globe lamp',
  ],
  RoomItemVisualKind.plant: [
    'Palm planter',
    'Snake plant',
    'Cactus planter',
    'Olive tree',
    'Monstera planter',
    'Bamboo planter',
    'Fiddle-leaf fig',
    'Succulent bowl',
    'Topiary tree',
    'Raised fern planter',
  ],
  RoomItemVisualKind.chair: [
    'Spindle chair',
    'Upholstered chair',
    'Armchair',
    'Cantilever chair',
    'Cross-back chair',
    'Bar stool',
    'Shell chair',
    'Ladder-back chair',
    'Rocking chair',
    'Lounge chair',
  ],
  RoomItemVisualKind.sofa: [
    'Two-seat sofa',
    'Three-seat sofa',
    'Left chaise sofa',
    'Right chaise sofa',
    'Corner sectional',
    'Tuxedo sofa',
    'Rolled-arm sofa',
    'Armless modular sofa',
    'Daybed sofa',
    'Curved sofa',
  ],
  RoomItemVisualKind.bookshelf: [
    'Open bookcase',
    'Ladder shelf',
    'Cube shelf',
    'Low media cabinet',
    'Asymmetric bookcase',
    'Arch bookcase',
    'Sideboard',
    'Display cabinet',
    'Tiered shelf',
    'Room divider',
  ],
};

List<String> furnitureFinishes(RoomItemVisualKind kind) => switch (kind) {
  RoomItemVisualKind.table || RoomItemVisualKind.nightstand => const [
    'Solid oak',
    'Walnut',
    'Marble & brass',
  ],
  RoomItemVisualKind.plant => const ['Terracotta', 'Ceramic', 'Fluted stone'],
  RoomItemVisualKind.floorLamp => const [
    'Oak & linen',
    'Black metal',
    'Brass & opal',
  ],
  RoomItemVisualKind.chair ||
  RoomItemVisualKind.sofa ||
  RoomItemVisualKind.ottoman ||
  RoomItemVisualKind.bed => const [
    'Oak & linen',
    'Walnut & leather',
    'Ivory boucle',
  ],
  _ => const ['Solid oak', 'Walnut & cane', 'Ivory & brass'],
};

/// 110 silhouettes, each in three finishes. No random IDs or session-dependent
/// prices: an owned item always resolves to the same model after an update.
final List<RoomItemDefinition> expandedFurnitureCatalog = List.unmodifiable([
  for (final kind in RoomItemVisualKind.values)
    for (var form = 0; form < 10; form++)
      for (var finish = 0; finish < 3; finish++)
        RoomItemDefinition(
          id: 'studio-${kind.name}-$form-$finish',
          title:
              '${furnitureFinishes(kind)[finish]} ${furnitureForms[kind]![form].toLowerCase()}',
          typeLabel: kind.label,
          category: kind.category,
          price: _basePrice(kind) + form * 4 + finish * 12,
          icon: kind.icon,
          tint: const [
            Color(0xFFF0E2D0),
            Color(0xFFE7D9D0),
            Color(0xFFEDE8DD),
          ][finish],
          description:
              '${furnitureForms[kind]![form]} · ${furnitureFinishes(kind)[finish]}.',
          visualKind: kind,
          width: _catalogFootprint(kind, form).width,
          depth: _catalogFootprint(kind, form).depth,
          design: FurnitureDesign(form, finish),
        ),
]);

int _basePrice(RoomItemVisualKind kind) => switch (kind) {
  RoomItemVisualKind.bed => 120,
  RoomItemVisualKind.sofa => 100,
  RoomItemVisualKind.wardrobe => 90,
  RoomItemVisualKind.vanity => 70,
  RoomItemVisualKind.table => 55,
  RoomItemVisualKind.bookshelf => 60,
  RoomItemVisualKind.chair => 35,
  RoomItemVisualKind.nightstand => 32,
  RoomItemVisualKind.ottoman => 30,
  RoomItemVisualKind.floorLamp => 28,
  RoomItemVisualKind.plant => 20,
};

GridSize _catalogFootprint(RoomItemVisualKind kind, int form) => switch (kind) {
  RoomItemVisualKind.bed => const GridSize(3, 4),
  RoomItemVisualKind.sofa => GridSize(
    form == 0 ? 3 : 4,
    form >= 2 && form <= 4 ? 3 : 2,
  ),
  RoomItemVisualKind.table => GridSize(
    form == 2 || form == 3 || form == 7 ? 3 : 2,
    form == 7 ? 1 : 2,
  ),
  RoomItemVisualKind.vanity => GridSize(3, form == 3 || form == 9 ? 2 : 1),
  RoomItemVisualKind.wardrobe ||
  RoomItemVisualKind.bookshelf => const GridSize(3, 1),
  RoomItemVisualKind.ottoman => GridSize(
    form == 2 || form == 3 || form == 4 || form == 9 ? 2 : 1,
    1,
  ),
  RoomItemVisualKind.floorLamp => GridSize(form == 2 ? 2 : 1, 1),
  _ => const GridSize(1, 1),
};

enum FurnitureSort { popularity, price }

List<RoomItemDefinition> browseFurniture(
  Iterable<RoomItemDefinition> catalog, {
  RoomItemVisualKind? kind,
  FurnitureSort sort = FurnitureSort.popularity,
  bool descending = true,
  Map<String, int> popularity = const {},
}) {
  final items = catalog
      .where((item) => kind == null || item.visualKind == kind)
      .toList();
  items.sort((a, b) {
    final comparison = sort == FurnitureSort.price
        ? a.price.compareTo(b.price)
        : (popularity[a.id] ?? 0).compareTo(popularity[b.id] ?? 0);
    if (comparison != 0) return descending ? -comparison : comparison;
    // Honest cold start: equal sales use a stable alphabetical order.
    final title = a.title.compareTo(b.title);
    return title != 0 ? title : a.id.compareTo(b.id);
  });
  return items;
}
