import 'package:flutter/material.dart';

import '../rooms/room_state.dart';
import '../rooms/room_visuals.dart';
import '../widgets/app_ui.dart';

class ShopScreen extends StatelessWidget {
  const ShopScreen({super.key, required this.controller});

  final RoomEditorController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          const AmbientBackground(),
          SafeArea(
            child: AnimatedBuilder(
              animation: controller,
              builder: (context, _) {
                return AppPage(
                  eyebrow: 'Store',
                  title: 'Comfort shop',
                  subtitle:
                      'Buy more furniture, then place it directly into the room.',
                  trailing: IconButton.filledTonal(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
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
                        TopicChip(label: 'Lighting', icon: Icons.light_rounded),
                        TopicChip(
                          label: 'Decor',
                          icon: Icons.local_florist_rounded,
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: controller.catalog.length,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            childAspectRatio: 0.72,
                          ),
                      itemBuilder: (context, index) {
                        final item = controller.catalog[index];
                        return _ShopItemCard(
                          definition: item,
                          likesBalance: controller.likesBalance,
                          ownedCount: controller.ownedCount(item.id),
                          availableToPlace: controller.availableToPlace(
                            item.id,
                          ),
                          onBuyAndPlace: () => _showResult(
                            context,
                            controller.buyAndAddItem(item.id),
                          ),
                          onPlaceOwned: controller.availableToPlace(item.id) > 0
                              ? () => _showResult(
                                  context,
                                  controller.addOwnedItem(item.id),
                                )
                              : null,
                        );
                      },
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

  void _showResult(BuildContext context, RoomActionResult result) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(result.message)));
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
              child: Text(canAfford ? 'Buy + place' : 'Need more likes'),
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
