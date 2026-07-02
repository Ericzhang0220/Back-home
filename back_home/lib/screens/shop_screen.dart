import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../rooms/room_state.dart';
import '../rooms/room_visuals.dart';
import '../widgets/app_ui.dart';
import 'room_edit_screen.dart';

class ShopScreen extends StatelessWidget {
  const ShopScreen({super.key, required this.controller});

  final RoomEditorController controller;

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
                animation: controller,
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
                                    '${controller.likesBalance}',
                                    style: const TextStyle(
                                      fontSize: 34,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.ink,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  const Text(
                                    'Purchases drop straight into the bedroom editor.',
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
                              icon: Icons.grid_on_rounded,
                              label: 'Room grid',
                              value:
                                  '${RoomEditorController.roomWidth} x ${RoomEditorController.roomDepth}',
                              tint: const Color(0xFFF6E2C3),
                            ),
                          ],
                        ),
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
                        controller: controller,
                        onBuyAndEdit: (definitionId) =>
                            _buyAndEdit(context, definitionId),
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

  Future<void> _buyAndEdit(BuildContext context, String definitionId) async {
    final result = controller.purchaseItem(definitionId);
    if (!result.isSuccess) {
      _showResult(context, result);
      return;
    }
    await _openEditor(context, initialDefinitionId: definitionId);
  }

  Future<void> _openEditor(
    BuildContext context, {
    String? initialDefinitionId,
  }) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RoomEditScreen(
          controller: controller,
          initialDefinitionId: initialDefinitionId,
        ),
      ),
    );
  }
}

class _ShopCatalogGrid extends StatelessWidget {
  const _ShopCatalogGrid({
    required this.controller,
    required this.onBuyAndEdit,
    required this.onPlaceOwnedAndEdit,
  });

  final RoomEditorController controller;
  final ValueChanged<String> onBuyAndEdit;
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
          1 => math.max(390.0, itemWidth * 0.82),
          2 => math.max(414.0, itemWidth * 1.16),
          _ => math.max(394.0, itemWidth * 1.2),
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
                  onBuyAndPlace: () => onBuyAndEdit(item.id),
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
    required this.onBuyAndPlace,
    this.onPlaceOwned,
  });

  final RoomItemDefinition definition;
  final int likesBalance;
  final int ownedCount;
  final int availableToPlace;
  final VoidCallback onBuyAndPlace;
  final VoidCallback? onPlaceOwned;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canAfford = likesBalance >= definition.price;

    return SoftCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 96,
            decoration: BoxDecoration(
              color: definition.tint.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Center(
              child: RoomSpriteThumbnail(definition: definition, size: 84),
            ),
          ),
          const SizedBox(height: 14),
          Text(definition.title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            definition.description,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          const Spacer(),
          Row(
            children: [
              const Icon(
                Icons.favorite_rounded,
                size: 18,
                color: AppColors.clay,
              ),
              const SizedBox(width: 6),
              Text('${definition.price}', style: theme.textTheme.labelLarge),
              const Spacer(),
              Text('$ownedCount owned', style: theme.textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: canAfford ? onBuyAndPlace : null,
              child: Text(canAfford ? 'Buy + edit' : 'Need more likes'),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: onPlaceOwned,
              child: Text(
                availableToPlace > 0 ? 'Place owned item' : 'Nothing unplaced',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
