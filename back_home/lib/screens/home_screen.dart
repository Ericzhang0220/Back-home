import 'package:flutter/material.dart';

import '../widgets/app_ui.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.onOpenRoom,
    required this.onOpenHall,
    required this.onOpenChat,
    required this.onOpenShop,
    required this.onOpenAchievements,
  });

  final VoidCallback onOpenRoom;
  final VoidCallback onOpenHall;
  final VoidCallback onOpenChat;
  final VoidCallback onOpenShop;
  final VoidCallback onOpenAchievements;

  @override
  Widget build(BuildContext context) {
    final quickActions = [
      (
        icon: Icons.weekend_rounded,
        title: 'Room',
        subtitle: 'Edit furniture, weather, and cozy details.',
        tint: AppColors.peach,
        action: onOpenRoom,
      ),
      (
        icon: Icons.chat_bubble_rounded,
        title: 'Chat',
        subtitle: 'Talk with AI companions or real people.',
        tint: AppColors.blush,
        action: onOpenChat,
      ),
      (
        icon: Icons.forum_rounded,
        title: 'Hall',
        subtitle: 'Read supportive posts from the community.',
        tint: const Color(0xFFD7E4D7),
        action: onOpenHall,
      ),
      (
        icon: Icons.shopping_bag_rounded,
        title: 'Shop',
        subtitle: 'Spend likes on decor, pets, and plants.',
        tint: const Color(0xFFF2DFC0),
        action: onOpenShop,
      ),
    ];

    final notes = [
      (
        author: 'Mina',
        message:
            'Your room looks calmer every day. Keep building the space you want to come back to.',
        likes: '18',
      ),
      (
        author: 'Theo',
        message:
            'I left a new playlist idea for rainy nights in the hall. It might fit your room mood.',
        likes: '12',
      ),
    ];

    return AppPage(
      eyebrow: 'Evening Reset',
      title: 'Back Home',
      subtitle:
          'A softer landing after a long day at school, work, or everywhere in between.',
      trailing: const InfoPill(
        icon: Icons.favorite_rounded,
        label: 'Likes',
        value: '238',
      ),
      children: [
        SoftCard(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFFF8F1), Color(0xFFF4D8C7)],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Your comfort room is glowing.',
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'The window is open, the music is low, and your next gentle check-in is ready.',
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                        const SizedBox(height: 18),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: const [
                            InfoPill(
                              icon: Icons.local_fire_department_rounded,
                              label: 'Streak',
                              value: '11 days',
                              tint: Color(0xFFF7DFC8),
                            ),
                            InfoPill(
                              icon: Icons.self_improvement_rounded,
                              label: 'Mood',
                              value: '82%',
                              tint: Color(0xFFDDE8DD),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  const _HomeIllustration(),
                ],
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  FilledButton.icon(
                    onPressed: onOpenRoom,
                    icon: const Icon(Icons.arrow_outward_rounded),
                    label: const Text('Open room'),
                  ),
                  OutlinedButton.icon(
                    onPressed: onOpenAchievements,
                    icon: const Icon(Icons.workspace_premium_rounded),
                    label: const Text('Achievements'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        const SectionHeader(
          title: 'Quick doors',
          subtitle: 'Jump into the core spaces of the app.',
        ),
        const SizedBox(height: 14),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: quickActions.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.98,
          ),
          itemBuilder: (context, index) {
            final item = quickActions[index];
            return ActionTile(
              icon: item.icon,
              title: item.title,
              subtitle: item.subtitle,
              tint: item.tint,
              onTap: item.action,
            );
          },
        ),
        const SizedBox(height: 28),
        const SectionHeader(
          title: 'Tonight\'s plan',
          subtitle: 'A calm, guided rhythm for the rest of the evening.',
        ),
        const SizedBox(height: 14),
        SoftCard(
          child: Column(
            children: const [
              _PlanStep(
                time: '7:30 PM',
                title: 'Bedtime message',
                detail:
                    'Tap the bed for a short reflection and a gentle prompt to exhale.',
              ),
              Divider(),
              _PlanStep(
                time: '8:00 PM',
                title: 'Table view + radio',
                detail:
                    'Open the table, tune the radio, and swap to your own playlist if you want.',
              ),
              Divider(),
              _PlanStep(
                time: '8:30 PM',
                title: 'Bottle request',
                detail:
                    'Send a message in a bottle or answer someone else\'s request for extra likes.',
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        SectionHeader(
          title: 'Warm notes from the hall',
          subtitle: 'Community encouragement worth saving for later.',
          actionLabel: 'Open hall',
          onAction: onOpenHall,
        ),
        const SizedBox(height: 14),
        for (final note in notes) ...[
          _NoteCard(
            author: note.author,
            message: note.message,
            likes: note.likes,
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _HomeIllustration extends StatelessWidget {
  const _HomeIllustration();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 124,
      height: 154,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(26),
      ),
      child: Stack(
        children: [
          Positioned(
            top: 18,
            left: 24,
            right: 24,
            child: Container(
              height: 46,
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3C7),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.stroke),
              ),
            ),
          ),
          Positioned(
            top: 28,
            left: 34,
            child: Container(
              height: 26,
              width: 22,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.75),
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          Positioned(
            top: 28,
            right: 34,
            child: Container(
              height: 26,
              width: 22,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.75),
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          Positioned(
            bottom: 28,
            left: 18,
            right: 18,
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFFD89D7F),
                borderRadius: BorderRadius.circular(22),
              ),
            ),
          ),
          Positioned(
            bottom: 44,
            left: 30,
            child: Container(
              height: 24,
              width: 54,
              decoration: BoxDecoration(
                color: const Color(0xFFFCEEDF),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          Positioned(
            bottom: 22,
            right: 22,
            child: Container(
              width: 20,
              height: 32,
              decoration: BoxDecoration(
                color: const Color(0xFF8CB094),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanStep extends StatelessWidget {
  const _PlanStep({
    required this.time,
    required this.title,
    required this.detail,
  });

  final String time;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.blush.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(time, style: theme.textTheme.labelLarge),
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

class _NoteCard extends StatelessWidget {
  const _NoteCard({
    required this.author,
    required this.message,
    required this.likes,
  });

  final String author;
  final String message;
  final String likes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SoftCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: AppColors.blush,
                child: Text(
                  author.characters.first,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(author, style: theme.textTheme.titleMedium)),
              const TagChip(label: 'Kind note', icon: Icons.favorite_rounded),
            ],
          ),
          const SizedBox(height: 16),
          Text(message, style: theme.textTheme.bodyLarge),
          const SizedBox(height: 14),
          Row(
            children: [
              const Icon(
                Icons.favorite_rounded,
                color: AppColors.clay,
                size: 18,
              ),
              const SizedBox(width: 6),
              Text('$likes likes', style: theme.textTheme.bodyMedium),
            ],
          ),
        ],
      ),
    );
  }
}
