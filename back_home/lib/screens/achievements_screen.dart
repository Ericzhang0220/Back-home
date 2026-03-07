import 'package:flutter/material.dart';

import '../widgets/app_ui.dart';

class AchievementsScreen extends StatelessWidget {
  const AchievementsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final achievements = [
      (
        title: 'Comfort starter',
        detail: 'Send 20 total messages across AI and community chats.',
        progress: '14 / 20',
      ),
      (
        title: 'Hall helper',
        detail: 'Solve 5 bottle requests from other users.',
        progress: '3 / 5',
      ),
      (
        title: 'Room curator',
        detail: 'Place 10 decorations in your room.',
        progress: '7 / 10',
      ),
    ];

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          const AmbientBackground(),
          SafeArea(
            child: AppPage(
              eyebrow: 'Milestones',
              title: 'Achievements',
              subtitle:
                  'Progress should reinforce healthy engagement without turning the app into a grind.',
              trailing: IconButton.filledTonal(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
              children: [
                SoftCard(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFFF8F0), Color(0xFFEEDCCD)],
                  ),
                  child: Row(
                    children: const [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'This month',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: AppColors.muted,
                              ),
                            ),
                            SizedBox(height: 8),
                            Text(
                              '4 unlocked',
                              style: TextStyle(
                                fontSize: 34,
                                fontWeight: FontWeight.w700,
                                color: AppColors.ink,
                              ),
                            ),
                            SizedBox(height: 6),
                            Text(
                              'Next badge at 5 achievements',
                              style: TextStyle(
                                fontSize: 14,
                                color: AppColors.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(width: 12),
                      InfoPill(
                        icon: Icons.workspace_premium_rounded,
                        label: 'Best streak',
                        value: '11 days',
                        tint: Color(0xFFF6E2C3),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                for (final item in achievements) ...[
                  _AchievementCard(
                    title: item.title,
                    detail: item.detail,
                    progress: item.progress,
                  ),
                  const SizedBox(height: 12),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AchievementCard extends StatelessWidget {
  const _AchievementCard({
    required this.title,
    required this.detail,
    required this.progress,
  });

  final String title;
  final String detail;
  final String progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SoftCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 52,
            width: 52,
            decoration: BoxDecoration(
              color: AppColors.blush.withValues(alpha: 0.75),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              Icons.workspace_premium_rounded,
              color: AppColors.clay,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                const SizedBox(height: 6),
                Text(detail, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 12),
                Text(progress, style: theme.textTheme.labelLarge),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
