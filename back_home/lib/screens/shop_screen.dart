import 'dart:async';

import 'package:flutter/material.dart';

import '../keyboard/keyboard_host.dart';
import '../keyboard/keyboard_shop.dart';
import '../rooms/furniture_preview.dart';
import '../rooms/room_state.dart';
import '../rooms/shop_popularity.dart';
import '../widgets/app_ui.dart';
import 'room_edit_screen.dart';

class ShopScreen extends StatefulWidget {
  const ShopScreen({
    super.key,
    required this.controller,
    this.initialKeyboards = false,
  });
  final RoomEditorController controller;
  final bool initialKeyboards;
  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  late bool _showKeyboards;
  RoomItemVisualKind? _category;
  FurnitureSort _sort = FurnitureSort.popularity;
  bool _descending = true;
  Map<String, int> _popularity = {};
  bool _popularityAvailable = false;
  final _scroll = ScrollController();
  final _sales = ShopPopularity();

  @override
  void initState() {
    super.initState();
    _showKeyboards = widget.initialKeyboards;
    unawaited(_refreshPopularity());
  }

  Future<void> _refreshPopularity() async {
    final sales = await _sales.load();
    if (!mounted) return;
    setState(() {
      _popularityAvailable = sales != null;
      _popularity = sales ?? {};
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  List<RoomItemDefinition> _items([RoomItemVisualKind? kind]) =>
      browseFurniture(
        widget.controller.catalog,
        kind: kind ?? _category,
        sort: _sort,
        descending: _descending,
        popularity: _popularity,
      );

  @override
  Widget build(BuildContext context) {
    final keyboards = KeyboardStoreScope.maybeOf(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          const Positioned.fill(child: AmbientBackground()),
          SafeArea(
            child: AnimatedBuilder(
              animation: widget.controller,
              builder: (context, _) {
                final items = _items();
                return CustomScrollView(
                  controller: _scroll,
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                      sliver: SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Expanded(
                                  child: Text(
                                    'STORE',
                                    style: TextStyle(
                                      color: AppColors.clay,
                                      letterSpacing: 1.6,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                if (!_showKeyboards)
                                  TextButton.icon(
                                    onPressed: () => _openEditor(context),
                                    icon: const Icon(Icons.edit_outlined),
                                    label: const Text('Edit room'),
                                  ),
                                IconButton.filledTonal(
                                  tooltip: 'Close shop',
                                  onPressed: () => Navigator.of(context).pop(),
                                  icon: const Icon(Icons.close_rounded),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _showKeyboards
                                  ? 'Keyboard studio'
                                  : 'Comfort shop',
                              style: Theme.of(context).textTheme.headlineMedium,
                            ),
                            const SizedBox(height: 16),
                            if (keyboards != null) ...[
                              SegmentedButton<bool>(
                                style: SegmentedButton.styleFrom(
                                  textStyle: const TextStyle(fontSize: 13),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                  ),
                                ),
                                segments: const [
                                  ButtonSegment(
                                    value: false,
                                    icon: Icon(Icons.chair_outlined),
                                    label: Text('Furniture'),
                                  ),
                                  ButtonSegment(
                                    value: true,
                                    icon: Icon(Icons.keyboard_outlined),
                                    label: Text('Keyboards'),
                                  ),
                                ],
                                selected: {_showKeyboards},
                                onSelectionChanged: (value) => setState(
                                  () => _showKeyboards = value.single,
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],
                            if (!_showKeyboards) ...[
                              // All departments live here, before any products or promotions.
                              Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                children: [
                                  ChoiceChip(
                                    label: const Text('All'),
                                    selected: _category == null,
                                    onSelected: (_) =>
                                        setState(() => _category = null),
                                  ),
                                  for (final kind in RoomItemVisualKind.values)
                                    ChoiceChip(
                                      label: Text(kind.label),
                                      selected: _category == kind,
                                      onSelected: (_) =>
                                          setState(() => _category = kind),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 12),
                            ],
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF4E2D3),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.favorite_rounded,
                                    color: AppColors.clay,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '${widget.controller.likesBalance} Likes',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    _showKeyboards
                                        ? 'Balance'
                                        : '${widget.controller.catalog.length} pieces',
                                    style: const TextStyle(
                                      color: AppColors.muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (!_showKeyboards) ...[
                              const SizedBox(height: 14),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${_category?.label ?? 'All furniture'} · ${items.length}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  TextButton.icon(
                                    key: const ValueKey('shop-sort'),
                                    onPressed: _chooseSort,
                                    icon: const Icon(
                                      Icons.tune_rounded,
                                      size: 20,
                                    ),
                                    label: Text(
                                      '${_sort == FurnitureSort.price ? 'Price' : 'Popular'} ${_descending ? '↓' : '↑'}',
                                    ),
                                  ),
                                ],
                              ),
                              if (!_popularityAvailable &&
                                  _sort == FurnitureSort.popularity)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Row(
                                    children: [
                                      const Expanded(
                                        child: Text(
                                          'Sales ranking unavailable · showing name order',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: AppColors.muted,
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: 'Retry sales ranking',
                                        onPressed: _refreshPopularity,
                                        icon: const Icon(
                                          Icons.refresh,
                                          size: 18,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              else if (_sort == FurnitureSort.popularity &&
                                  _popularity.values.every(
                                    (count) => count == 0,
                                  ))
                                const Padding(
                                  padding: EdgeInsets.only(bottom: 12),
                                  child: Text(
                                    'New collection · sales ranking starts with purchases',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppColors.muted,
                                    ),
                                  ),
                                ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    if (_showKeyboards && keyboards != null)
                      SliverPadding(
                        padding: const EdgeInsets.all(20),
                        sliver: SliverToBoxAdapter(
                          child: KeyboardShopSection(store: keyboards),
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                        sliver: SliverLayoutBuilder(
                          builder: (context, constraints) {
                            final columns = constraints.crossAxisExtent >= 900
                                ? 4
                                : constraints.crossAxisExtent >= 580
                                ? 3
                                : 2;
                            return SliverGrid.builder(
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: columns,
                                    mainAxisExtent:
                                        315 +
                                        (MediaQuery.textScalerOf(
                                                  context,
                                                ).scale(14) -
                                                14) *
                                            5,
                                    crossAxisSpacing: 12,
                                    mainAxisSpacing: 12,
                                  ),
                              itemCount: items.length,
                              itemBuilder: (context, index) => _ProductCard(
                                definition: items[index],
                                owned: widget.controller.ownedCount(
                                  items[index].id,
                                ),
                                canBuy:
                                    widget.controller.likesBalance >=
                                        items[index].price &&
                                    !widget.controller.shopPurchaseLocked,
                                onTap: () => _openProduct(items[index]),
                                onBuy: () => _buy(items[index]),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _chooseSort() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, updateSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Sort by', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  children: [
                    for (final sort in FurnitureSort.values)
                      ChoiceChip(
                        label: Text(
                          sort == FurnitureSort.price ? 'Price' : 'Popularity',
                        ),
                        selected: _sort == sort,
                        onSelected: (_) {
                          setState(() => _sort = sort);
                          updateSheet(() {});
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                ListTile(
                  leading: const Icon(Icons.south_rounded),
                  title: const Text('High to low'),
                  trailing: _descending
                      ? const Icon(Icons.check_rounded)
                      : null,
                  onTap: () {
                    setState(() => _descending = true);
                    updateSheet(() {});
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.north_rounded),
                  title: const Text('Low to high'),
                  trailing: !_descending
                      ? const Icon(Icons.check_rounded)
                      : null,
                  onTap: () {
                    setState(() => _descending = false);
                    updateSheet(() {});
                  },
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Done'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _buy(RoomItemDefinition item) {
    final result = widget.controller.purchaseItem(item.id);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(result.message)));
    if (result.isSuccess) {
      unawaited(
        _sales
            .recordPurchase(item.id)
            .then(
              (_) => _refreshPopularity(),
              onError: (Object _) => _refreshPopularity(),
            ),
      );
    }
  }

  Future<void> _openEditor(
    BuildContext context, {
    String? initialDefinitionId,
  }) => Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => RoomEditScreen(
        controller: widget.controller,
        initialDefinitionId: initialDefinitionId,
      ),
    ),
  );

  Future<void> _openProduct(RoomItemDefinition initial) async {
    var selected = initial;
    final related = _items(initial.visualKind);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, updateSheet) => FractionallySizedBox(
          heightFactor: .9,
          child: AnimatedBuilder(
            animation: widget.controller,
            builder: (context, _) => CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                selected.title,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Close preview',
                              onPressed: () => Navigator.pop(sheetContext),
                              icon: const Icon(Icons.close),
                            ),
                          ],
                        ),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: selected.tint,
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: FurniturePreviewStage(
                            definition: selected,
                            bakeKinds: const [],
                            height: 240,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(selected.description),
                        const SizedBox(height: 6),
                        Text(
                          '${selected.width} × ${selected.depth} floor tiles · Drag to rotate',
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton(
                                onPressed:
                                    widget.controller.likesBalance >=
                                            selected.price &&
                                        !widget.controller.shopPurchaseLocked
                                    ? () => _buy(selected)
                                    : null,
                                child: Text('Buy · ${selected.price} Likes'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            OutlinedButton(
                              onPressed:
                                  widget.controller.availableToPlace(
                                        selected.id,
                                      ) >
                                      0
                                  ? () async {
                                      Navigator.pop(sheetContext);
                                      await _openEditor(
                                        this.context,
                                        initialDefinitionId: selected.id,
                                      );
                                    }
                                  : null,
                              child: const Text('Place'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'More ${initial.visualKind.label.toLowerCase()}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${related.length} styles & finishes',
                          style: const TextStyle(color: AppColors.muted),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                  sliver: SliverList.builder(
                    itemCount: related.length,
                    itemBuilder: (context, index) {
                      final item = related[index];
                      return ListTile(
                        key: ValueKey('related-${item.id}'),
                        contentPadding: const EdgeInsets.symmetric(vertical: 6),
                        leading: FurnitureThumbnail(definition: item, size: 64),
                        title: Text(item.title),
                        subtitle: Text('${item.price} Likes'),
                        selected: selected.id == item.id,
                        onTap: () {
                          updateSheet(() => selected = item);
                          Scrollable.of(context).position.animateTo(
                            0,
                            duration: const Duration(milliseconds: 250),
                            curve: Curves.easeOut,
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.definition,
    required this.owned,
    required this.canBuy,
    required this.onTap,
    required this.onBuy,
  });
  final RoomItemDefinition definition;
  final int owned;
  final bool canBuy;
  final VoidCallback onTap, onBuy;
  @override
  Widget build(BuildContext context) => Material(
    key: ValueKey('product-${definition.id}'),
    color: const Color(0xFFFBF6EF),
    borderRadius: BorderRadius.circular(24),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 128,
              width: double.infinity,
              decoration: BoxDecoration(
                color: definition.tint,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Center(
                child: FurnitureThumbnail(definition: definition, size: 124),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              definition.title,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            const Spacer(),
            Row(
              children: [
                const Icon(
                  Icons.favorite_rounded,
                  size: 16,
                  color: AppColors.clay,
                ),
                const SizedBox(width: 4),
                Text(
                  '${definition.price}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                if (owned > 0)
                  Text(
                    'Own $owned',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.muted,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: canBuy ? onBuy : null,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  visualDensity: VisualDensity.compact,
                ),
                child: Text(
                  canBuy ? 'Buy' : 'Need likes',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
