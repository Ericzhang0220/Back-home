import 'package:flutter/material.dart';

import '../screens/hall_post.dart';
import 'app_ui.dart';

class HallPostCard extends StatelessWidget {
  const HallPostCard({
    super.key,
    required this.post,
    this.onLikeTap,
    this.onCommentTap,
    this.onEdit,
    this.embedded = false,
  });

  final HallPost post;
  final VoidCallback? onLikeTap;
  final VoidCallback? onCommentTap;
  final VoidCallback? onEdit;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: AppColors.blush,
              child: Text(post.author.characters.first),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(post.author, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 2),
                  Text(post.mood, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: MediaQuery.of(context).size.width * 0.42,
              child: TopicChip(label: post.topic, icon: Icons.sell_rounded),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(post.message, style: theme.textTheme.bodyLarge),
        const SizedBox(height: 16),
        Row(
          children: [
            _PostActionButton(
              icon: post.likedByMe
                  ? Icons.favorite_rounded
                  : Icons.favorite_rounded,
              label: _likesLabel(post.likes),
              isActive: post.likedByMe,
              onTap: onLikeTap,
            ),
            const Spacer(),
            _PostActionButton(
              icon: Icons.mode_comment_outlined,
              label: _commentsLabel(post.comments),
              onTap: onCommentTap,
            ),
          ],
        ),
      ],
    );

    if (embedded) {
      return content;
    }

    return SoftCard(child: content);
  }

  String _likesLabel(int likes) => '$likes ${likes == 1 ? 'like' : 'likes'}';

  String _commentsLabel(int comments) =>
      '$comments ${comments == 1 ? 'comment' : 'comments'}';
}

class _PostActionButton extends StatelessWidget {
  const _PostActionButton({
    required this.icon,
    required this.label,
    this.onTap,
    this.isActive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 18,
                color: isActive ? AppColors.clay : AppColors.muted,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: isActive ? AppColors.ink : AppColors.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
