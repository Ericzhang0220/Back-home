import 'package:flutter/material.dart';

import '../widgets/app_ui.dart';

class HallScreen extends StatelessWidget {
  const HallScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final posts = [
      (
        name: 'Jamie',
        mood: 'Hopeful',
        message:
            'If today felt heavy, try making your room brighter than your thoughts. It helped me more than I expected.',
        likes: 42,
        tag: 'Room setup',
      ),
      (
        name: 'Rin',
        mood: 'Calm',
        message:
            'Left a new encouragement message near the window prompt. The sunset version is my favorite.',
        likes: 27,
        tag: 'Kind note',
      ),
      (
        name: 'Harper',
        mood: 'Proud',
        message:
            'Answered three bottles this week and finally bought the cat bed. The reward loop feels good.',
        likes: 19,
        tag: 'Bottle reward',
      ),
    ];

    return AppPage(
      eyebrow: 'Community',
      title: 'The hall',
      subtitle:
          'A warm, slow feed where people post encouragement and collect likes by showing up for each other.',
      trailing: const InfoPill(
        icon: Icons.celebration_rounded,
        label: 'Daily bonus',
        value: '+15',
        tint: Color(0xFFF6E2C3),
      ),
      children: [
        SoftCard(
          gradient: const LinearGradient(
            colors: [Color(0xFFFFF7EF), Color(0xFFE4EEDC)],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'What kind of energy do you want to leave here tonight?',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 10),
              Text(
                'The composer should support a simple post, mood tag, and image or room snapshot later.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Write a small encouragement, a room update, or something you wish you had heard today.',
                  style: TextStyle(color: AppColors.muted),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.edit_rounded),
                label: const Text('Draft post'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        const SectionHeader(
          title: 'Live feed',
          subtitle:
              'Posts should feel gentle, readable, and worth lingering on.',
        ),
        const SizedBox(height: 14),
        for (final post in posts) ...[
          _HallPostCard(
            name: post.name,
            mood: post.mood,
            message: post.message,
            likes: post.likes,
            tag: post.tag,
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _HallPostCard extends StatelessWidget {
  const _HallPostCard({
    required this.name,
    required this.mood,
    required this.message,
    required this.likes,
    required this.tag,
  });

  final String name;
  final String mood;
  final String message;
  final int likes;
  final String tag;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: AppColors.blush,
                child: Text(name.characters.first),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: theme.textTheme.titleMedium),
                    Text(mood, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              TagChip(label: tag, icon: Icons.sell_rounded),
            ],
          ),
          const SizedBox(height: 16),
          Text(message, style: theme.textTheme.bodyLarge),
          const SizedBox(height: 16),
          Row(
            children: [
              const Icon(
                Icons.favorite_rounded,
                size: 18,
                color: AppColors.clay,
              ),
              const SizedBox(width: 6),
              Text('$likes likes', style: theme.textTheme.bodyMedium),
              const Spacer(),
              const Icon(
                Icons.mode_comment_outlined,
                size: 18,
                color: AppColors.muted,
              ),
              const SizedBox(width: 6),
              Text('Reply', style: theme.textTheme.bodyMedium),
            ],
          ),
        ],
      ),
    );
  }
}
