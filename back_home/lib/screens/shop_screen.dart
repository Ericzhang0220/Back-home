import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../rooms/furniture_preview.dart';
import '../rooms/room_state.dart';
import '../widgets/app_ui.dart';
import 'room_edit_screen.dart';

class ShopScreen extends StatefulWidget {
  const ShopScreen({super.key, required this.controller});

  final RoomEditorController controller;

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  RoomItemDefinition? _previewed;

  @override
  void initState() {
    super.initState();
    final catalog = widget.controller.catalog;
    _previewed = catalog.isEmpty ? null : catalog.first;
  }

  List<RoomItemVisualKind> get _catalogKinds {
    final kinds = <RoomItemVisualKind>[];
    for (final definition in widget.controller.catalog) {
      if (!kinds.contains(definition.visualKind)) {
        kinds.add(definition.visualKind);
      }
    }
    return kinds;
  }

  void _preview(RoomItemDefinition definition) {
    if (_previewed?.id == definition.id) {
      return;
    }
    setState(() {
      _previewed = definition;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          const Positioned.fill(child: AmbientBackground()),
          Positioned.fill(
            child: SafeArea(
              child: AnimatedBuilder(
                animation: widget.controller,
                builder: (context, _) {
                  return AppPage(
                    eyebrow: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'STORE',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: AppColors.clay,
                            letterSpacing: 1.6,
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            FilledButton.icon(
                              onPressed: () => _openEditor(context),
                              icon: const Icon(Icons.edit_rounded),
                              label: const Text(
                                'Edit',
                                style: TextStyle(fontSize: 13),
                              ),
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton.filledTonal(
                              onPressed: () => Navigator.of(context).pop(),
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                        ),
                      ],
                    ),
                    title: 'Comfort shop',
                    subtitle:
                        'Buy more furniture, then arrange it in edit mode.',
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
                    children: [
                      SoftCard(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFFF8F0), Color(0xFFF4D8C7)],
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Likes balance',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.muted,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '${widget.controller.likesBalance}',
                                    style: const TextStyle(
                                      fontSize: 34,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.ink,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  const Text(
                                    'Purchases add to your inventory for later placement.',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: AppColors.muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 14),
                            InfoPill(
                              icon: Icons.aspect_ratio_rounded,
                              label: 'Room size',
                              value:
                                  '${RoomEditorController.roomWidth} x ${RoomEditorController.roomDepth}',
                              tint: const Color(0xFFF6E2C3),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),
                      _PreviewPanel(
                        definition: _previewed,
                        bakeKinds: _catalogKinds,
                      ),
                      const SizedBox(height: 28),
                      const SectionHeader(
                        title: 'Categories',
                        subtitle:
                            'Statement pieces first, then small fillers for empty tiles.',
                      ),
                      const SizedBox(height: 14),
                      const Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          TopicChip(
                            label: 'Statement',
                            icon: Icons.bed_rounded,
                            highlight: true,
                          ),
                          TopicChip(
                            label: 'Storage',
                            icon: Icons.inventory_2_rounded,
                          ),
                          TopicChip(
                            label: 'Lighting',
                            icon: Icons.light_rounded,
                          ),
                          TopicChip(
                            label: 'Decor',
                            icon: Icons.local_florist_rounded,
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      _ShopCatalogGrid(
                        controller: widget.controller,
                        previewedId: _previewed?.id,
                        onPreview: _preview,
                        onBuy: (definitionId) => _buy(context, definitionId),
                        onPlaceOwnedAndEdit: (definitionId) => _openEditor(
                          context,
                          initialDefinitionId: definitionId,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showResult(BuildContext context, RoomActionResult result) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(result.message)));
  }

  void _buy(BuildContext context, String definitionId) {
    final result = widget.controller.purchaseItem(definitionId);
    _showResult(context, result);
  }

  Future<void> _openEditor(
    BuildContext context, {
    String? initialDefinitionId,
  }) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RoomEditScreen(
          controller: widget.controller,
          initialDefinitionId: initialDefinitionId,
        ),
      ),
    );
  }
}

/// The live turntable. This is the app's one GL context while the shop is open,
/// and it also bakes the thumbnails the cards below use.
class _PreviewPanel extends StatelessWidget {
  const _PreviewPanel({required this.definition, required this.bakeKinds});

  final RoomItemDefinition? definition;
  final List<RoomItemVisualKind> bakeKinds;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tint = definition?.tint ?? const Color(0xFFF1E4D6);

    return SoftCard(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      definition?.title ?? 'Preview',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      definition?.typeLabel ?? 'Pick a piece below',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              const InfoPill(
                icon: Icons.threed_rotation_rounded,
                label: 'Preview',
                value: 'Tap to spin',
                tint: Color(0xFFEADFCF),
              ),
            ],
          ),
          const SizedBox(height: 14),
          DecoratedBox(
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(20),
            ),
            child: FurniturePreviewStage(
              definition: definition,
              bakeKinds: bakeKinds,
            ),
          ),
          if (definition != null) ...[
            const SizedBox(height: 12),
            Text(
              definition!.description,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.muted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ShopCatalogGrid extends StatelessWidget {
  const _ShopCatalogGrid({
    required this.controller,
    required this.previewedId,
    required this.onPreview,
    required this.onBuy,
    required this.onPlaceOwnedAndEdit,
  });

  final RoomEditorController controller;
  final String? previewedId;
  final ValueChanged<RoomItemDefinition> onPreview;
  final ValueChanged<String> onBuy;
  final ValueChanged<String> onPlaceOwnedAndEdit;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 12.0;
        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width - 40;
        final columnCount = availableWidth < 560
            ? 1
            : availableWidth >= 960
            ? 3
            : 2;
        final itemWidth =
            (availableWidth - spacing * (columnCount - 1)) / columnCount;
        final itemHeight = switch (columnCount) {
          1 => math.max(430.0, itemWidth * 0.82),
          2 => math.max(430.0, itemWidth * 1.16),
          _ => math.max(414.0, itemWidth * 1.2),
        };

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final item in controller.catalog)
              SizedBox(
                width: itemWidth,
                height: itemHeight,
                child: _ShopItemCard(
                  definition: item,
                  likesBalance: controller.likesBalance,
                  ownedCount: controller.ownedCount(item.id),
                  availableToPlace: controller.availableToPlace(item.id),
                  isPreviewed: previewedId == item.id,
                  onPreview: () => onPreview(item),
                  onBuy: () => onBuy(item.id),
                  onPlaceOwned: controller.availableToPlace(item.id) > 0
                      ? () => onPlaceOwnedAndEdit(item.id)
                      : null,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ShopItemCard extends StatelessWidget {
  const _ShopItemCard({
    required this.definition,
    required this.likesBalance,
    required this.ownedCount,
    required this.availableToPlace,
    required this.isPreviewed,
    required this.onPreview,
    required this.onBuy,
    this.onPlaceOwned,
  });

  final RoomItemDefinition definition;
  final int likesBalance;
  final int ownedCount;
  final int availableToPlace;
  final bool isPreviewed;
  final VoidCallback onPreview;
  final VoidCallback onBuy;
  final VoidCallback? onPlaceOwned;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canAfford = likesBalance >= definition.price;
    final canEdit = availableToPlace > 0;

    return GestureDetector(
      onTap: onPreview,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: isPreviewed ? AppColors.clay : Colors.transparent,
            width: 2,
          ),
        ),
        child: SoftCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _FurnitureModelPreview(definition: definition),
              const SizedBox(height: 16),
              Text(
                definition.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(
                    Icons.favorite_rounded,
                    size: 18,
                    color: AppColors.clay,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${definition.price}',
                    style: theme.textTheme.labelLarge,
                  ),
                  const Spacer(),
                  Text(
                    '$ownedCount bought',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: canAfford ? onBuy : null,
                  child: Text(canAfford ? 'Buy' : 'Need more likes'),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: canEdit ? onPlaceOwned : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.ink,
                    disabledBackgroundColor: Colors.white.withValues(
                      alpha: 0.58,
                    ),
                    disabledForegroundColor: AppColors.muted.withValues(
                      alpha: 0.54,
                    ),
                    side: const BorderSide(color: AppColors.stroke),
                  ),
                  child: const Text('Edit'),
                ),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'You have: $availableToPlace',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FurnitureModelPreview extends StatelessWidget {
  const _FurnitureModelPreview({required this.definition});

  final RoomItemDefinition definition;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 154,
      width: double.infinity,
      decoration: BoxDecoration(
        color: definition.tint.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            bottom: 22,
            child: Container(
              width: 116,
              height: 18,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          FurnitureThumbnail(definition: definition, size: 132),
        ],
      ),
    );
  }
}
