import 'package:flutter/material.dart';

import '../widgets/app_ui.dart';

class ChatScreen extends StatelessWidget {
  const ChatScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final recentChats = [
      (
        name: 'Ari',
        role: 'Beautiful girl AI',
        lastLine:
            'Want me to keep the room quiet tonight or help you unpack the day?',
      ),
      (
        name: 'Noah',
        role: 'Handsome boy AI',
        lastLine:
            'You sounded tired earlier. I saved a lighter playlist for you.',
      ),
      (
        name: 'Mentor Lin',
        role: 'Mentor',
        lastLine: 'Let’s turn that stress into three smaller tasks before bed.',
      ),
    ];

    return AppPage(
      eyebrow: 'Connection',
      title: 'Chat space',
      subtitle:
          'Talk with AI personalities, other people, or send a message in a bottle when you want help from the wider community.',
      trailing: const TagChip(
        label: 'AI + Human',
        icon: Icons.hub_rounded,
        highlight: true,
      ),
      children: [
        SoftCard(
          gradient: const LinearGradient(
            colors: [Color(0xFFFFF7EF), Color(0xFFF4DED0)],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Choose a voice',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 14),
              const Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  TagChip(
                    label: 'Beautiful girl',
                    icon: Icons.auto_awesome_rounded,
                    highlight: true,
                  ),
                  TagChip(
                    label: 'Handsome boy',
                    icon: Icons.psychology_alt_rounded,
                  ),
                  TagChip(label: 'Mentor', icon: Icons.school_rounded),
                  TagChip(label: 'Real people', icon: Icons.people_alt_rounded),
                ],
              ),
              const SizedBox(height: 18),
              const _Bubble(
                alignment: CrossAxisAlignment.start,
                color: AppColors.card,
                sender: 'Ari (AI)',
                text:
                    'Hi. You made it back. Want to settle in with music, a short reflection, or just silence for a minute?',
              ),
              const SizedBox(height: 10),
              const _Bubble(
                alignment: CrossAxisAlignment.end,
                color: Color(0xFFEAD3BB),
                sender: 'You',
                text: 'Music first. Then help me sort through the day.',
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        const SectionHeader(
          title: 'Message in a Bottle',
          subtitle:
              'A lightweight prompt flow inside chat for sending or receiving help requests.',
        ),
        const SizedBox(height: 14),
        SoftCard(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 54,
                width: 54,
                decoration: BoxDecoration(
                  color: AppColors.blush.withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(Icons.liquor_rounded, color: AppColors.clay),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Message in a Bottle',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Tapping the bottle icon should open a popup with two clear actions: send one out, or receive one from someone else.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        FilledButton(
                          onPressed: () {},
                          child: const Text('Send bottle'),
                        ),
                        OutlinedButton(
                          onPressed: () {},
                          child: const Text('Receive request'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        const SectionHeader(
          title: 'Recent conversations',
          subtitle: 'The list should make AI versus human immediately obvious.',
        ),
        const SizedBox(height: 14),
        for (final chat in recentChats) ...[
          _ChatListTile(
            name: chat.name,
            role: chat.role,
            lastLine: chat.lastLine,
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.alignment,
    required this.color,
    required this.sender,
    required this.text,
  });

  final CrossAxisAlignment alignment;
  final Color color;
  final String sender;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: alignment,
      children: [
        Text(sender, style: theme.textTheme.bodySmall),
        const SizedBox(height: 6),
        Container(
          constraints: const BoxConstraints(maxWidth: 300),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AppColors.stroke),
          ),
          child: Text(text, style: theme.textTheme.bodyLarge),
        ),
      ],
    );
  }
}

class _ChatListTile extends StatelessWidget {
  const _ChatListTile({
    required this.name,
    required this.role,
    required this.lastLine,
  });

  final String name;
  final String role;
  final String lastLine;

  @override
  Widget build(BuildContext context) {
    final isAi = role.contains('AI') || role == 'Mentor';
    final theme = Theme.of(context);

    return SoftCard(
      padding: const EdgeInsets.all(18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: isAi ? AppColors.blush : const Color(0xFFDDE8DD),
            child: Icon(
              isAi ? Icons.auto_awesome_rounded : Icons.person_rounded,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(name, style: theme.textTheme.titleMedium),
                    ),
                    TagChip(
                      label: role,
                      icon: isAi ? Icons.memory_rounded : Icons.people_rounded,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(lastLine, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
