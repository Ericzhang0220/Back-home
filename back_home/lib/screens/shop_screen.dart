import 'package:flutter/material.dart';

import '../widgets/app_ui.dart';

class ShopScreen extends StatelessWidget {
  const ShopScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final items = [
      (
        title: 'Sunset bed',
        type: 'Furniture',
        price: 120,
        icon: Icons.bed_rounded,
        tint: AppColors.peach,
      ),
      (
        title: 'Window cat',
        type: 'Pet',
        price: 85,
        icon: Icons.pets_rounded,
        tint: const Color(0xFFDDE8DD),
      ),
      (
        title: 'Tea radio',
        type: 'Object',
        price: 60,
        icon: Icons.radio_rounded,
        tint: const Color(0xFFF2DFC0),
      ),
      (
        title: 'Hanging fern',
        type: 'Plant',
        price: 40,
        icon: Icons.local_florist_rounded,
        tint: const Color(0xFFDDE8DD),
      ),
    ];

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          const AmbientBackground(),
          SafeArea(
            child: AppPage(
              eyebrow: 'Store',
              title: 'Comfort shop',
              subtitle:
                  'Spend likes on furniture, pets, plants, and objects that make the room feel more alive.',
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
                    children: const [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Likes balance',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: AppColors.muted,
                              ),
                            ),
                            SizedBox(height: 8),
                            Text(
                              '238',
                              style: TextStyle(
                                fontSize: 34,
                                fontWeight: FontWeight.w700,
                                color: AppColors.ink,
                              ),
                            ),
                            SizedBox(height: 6),
                            Text(
                              'Daily login bonus: +15',
                              style: TextStyle(
                                fontSize: 14,
                                color: AppColors.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(width: 14),
                      InfoPill(
                        icon: Icons.favorite_rounded,
                        label: 'Earn more',
                        value: 'Answer bottles',
                        tint: Color(0xFFF6E2C3),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                const SectionHeader(
                  title: 'Categories',
                  subtitle: 'A simple first-pass layout for room rewards.',
                ),
                const SizedBox(height: 14),
                const Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    TagChip(
                      label: 'Furniture',
                      icon: Icons.chair_rounded,
                      highlight: true,
                    ),
                    TagChip(label: 'Pets', icon: Icons.pets_rounded),
                    TagChip(label: 'Plants', icon: Icons.local_florist_rounded),
                    TagChip(label: 'Objects', icon: Icons.coffee_rounded),
                  ],
                ),
                const SizedBox(height: 20),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: items.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.9,
                  ),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return _ShopItemCard(
                      title: item.title,
                      type: item.type,
                      price: item.price,
                      icon: item.icon,
                      tint: item.tint,
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ShopItemCard extends StatelessWidget {
  const _ShopItemCard({
    required this.title,
    required this.type,
    required this.price,
    required this.icon,
    required this.tint,
  });

  final String title;
  final String type;
  final int price;
  final IconData icon;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SoftCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 78,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Center(child: Icon(icon, size: 36, color: AppColors.ink)),
          ),
          const Spacer(),
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(type, style: theme.textTheme.bodySmall),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(
                Icons.favorite_rounded,
                size: 18,
                color: AppColors.clay,
              ),
              const SizedBox(width: 6),
              Text('$price', style: theme.textTheme.labelLarge),
            ],
          ),
        ],
      ),
    );
  }
}
