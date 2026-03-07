import 'package:flutter/material.dart';

import '../widgets/app_ui.dart';

class RoomScreen extends StatelessWidget {
  const RoomScreen({super.key, required this.onOpenShop});

  final VoidCallback onOpenShop;

  @override
  Widget build(BuildContext context) {
    final objects = [
      (
        icon: Icons.bed_rounded,
        title: 'Bed',
        detail: 'Shows a bedtime message and reflection prompt.',
      ),
      (
        icon: Icons.table_restaurant_rounded,
        title: 'Table',
        detail: 'Opens table view for music and objects.',
      ),
      (
        icon: Icons.radio_rounded,
        title: 'Radio',
        detail: 'Swap between built-in tracks and your own library.',
      ),
      (
        icon: Icons.window_rounded,
        title: 'Window',
        detail: 'Open, close, and change how light falls into the room.',
      ),
      (
        icon: Icons.pets_rounded,
        title: 'Pet',
        detail: 'Tap to trigger a small animation and comfort reaction.',
      ),
      (
        icon: Icons.local_florist_rounded,
        title: 'Plant',
        detail: 'Animated leaves make the space feel alive.',
      ),
    ];

    return AppPage(
      eyebrow: 'Personal Space',
      title: 'Your room',
      subtitle:
          'Build a soft, interactive environment that changes with time, weather, and the things you collect.',
      trailing: IconButton.filledTonal(
        onPressed: onOpenShop,
        icon: const Icon(Icons.shopping_bag_rounded),
      ),
      children: [
        SoftCard(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFFF8EE), Color(0xFFF0D2BF)],
          ),
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _RoomPreview(),
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: const [
                  TagChip(
                    label: 'Evening light',
                    icon: Icons.wb_twilight_rounded,
                  ),
                  TagChip(label: 'Soft rain', icon: Icons.water_drop_rounded),
                  TagChip(
                    label: 'Window open',
                    icon: Icons.air_rounded,
                    highlight: true,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        const SectionHeader(
          title: 'Ambience controls',
          subtitle: 'Weather and room state should feel easy to tune.',
        ),
        const SizedBox(height: 14),
        SoftCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text(
                'Weather',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
              SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  TagChip(label: 'Sunny', icon: Icons.wb_sunny_rounded),
                  TagChip(
                    label: 'Rainy',
                    icon: Icons.umbrella_rounded,
                    highlight: true,
                  ),
                  TagChip(label: 'Snowy', icon: Icons.ac_unit_rounded),
                ],
              ),
              SizedBox(height: 20),
              Text(
                'Time mood',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
              SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  TagChip(label: 'Morning'),
                  TagChip(label: 'Afternoon'),
                  TagChip(label: 'Evening', highlight: true),
                  TagChip(label: 'Night'),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        SectionHeader(
          title: 'Interactive corners',
          subtitle:
              'Every major object should do something meaningful when tapped.',
          actionLabel: 'Open shop',
          onAction: onOpenShop,
        ),
        const SizedBox(height: 14),
        for (final object in objects) ...[
          _ObjectCard(
            icon: object.icon,
            title: object.title,
            detail: object.detail,
          ),
          const SizedBox(height: 12),
        ],
        const SizedBox(height: 16),
        SoftCard(
          gradient: const LinearGradient(
            colors: [Color(0xFFF4E8D8), Color(0xFFEAD3BB)],
          ),
          child: Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Decorate with intention',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Furniture, pets, plants, and small keepsakes should all feel like emotional rewards.',
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.45,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              FilledButton(onPressed: onOpenShop, child: const Text('Browse')),
            ],
          ),
        ),
      ],
    );
  }
}

class _RoomPreview extends StatelessWidget {
  const _RoomPreview();

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1.1,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFFF4E7), Color(0xFFDDB9A3)],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              top: 18,
              right: 22,
              child: Container(
                width: 88,
                height: 96,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF2C4),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: AppColors.stroke),
                ),
              ),
            ),
            Positioned(
              top: 32,
              right: 36,
              child: Container(
                width: 24,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            Positioned(
              top: 32,
              right: 64,
              child: Container(
                width: 24,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            Positioned(
              left: 28,
              bottom: 36,
              child: Container(
                width: 150,
                height: 78,
                decoration: BoxDecoration(
                  color: const Color(0xFFC28162),
                  borderRadius: BorderRadius.circular(28),
                ),
              ),
            ),
            Positioned(
              left: 42,
              bottom: 64,
              child: Container(
                width: 66,
                height: 26,
                decoration: BoxDecoration(
                  color: const Color(0xFFFDF2E4),
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
            Positioned(
              left: 176,
              bottom: 58,
              child: Container(
                width: 42,
                height: 52,
                decoration: BoxDecoration(
                  color: const Color(0xFF7D5A4C),
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
            ),
            Positioned(
              left: 182,
              bottom: 94,
              child: Container(
                width: 28,
                height: 18,
                decoration: BoxDecoration(
                  color: const Color(0xFFF7E78E),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            Positioned(
              right: 36,
              bottom: 28,
              child: Column(
                children: [
                  Container(
                    width: 34,
                    height: 38,
                    decoration: BoxDecoration(
                      color: const Color(0xFF89A284),
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  Container(
                    width: 10,
                    height: 22,
                    color: const Color(0xFF8F6E5D),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 22,
              right: 22,
              bottom: 14,
              child: Container(
                height: 10,
                decoration: BoxDecoration(
                  color: const Color(0x4DFFFFFF),
                  borderRadius: BorderRadius.circular(100),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ObjectCard extends StatelessWidget {
  const _ObjectCard({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SoftCard(
      padding: const EdgeInsets.all(18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 48,
            width: 48,
            decoration: BoxDecoration(
              color: AppColors.blush.withValues(alpha: 0.75),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: AppColors.clay),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                const SizedBox(height: 6),
                Text(detail, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
