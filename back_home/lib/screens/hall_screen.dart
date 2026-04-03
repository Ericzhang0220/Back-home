import 'package:flutter/material.dart';

import '../widgets/app_ui.dart';
import 'create_post_screen.dart';
import 'hall_post.dart';

class HallScreen extends StatefulWidget {
  const HallScreen({super.key});

  @override
  State<HallScreen> createState() => _HallScreenState();
}

class _HallScreenState extends State<HallScreen> {
  late final TextEditingController _searchController;
  late final List<HallPost> _posts;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _posts = [
      const HallPost(
        author: 'You',
        mood: 'Hopeful',
        tag: 'Daily check-in',
        message:
            'Trying to make my room softer tonight. I picked the light green smile today and I want to keep that feeling going.',
        likes: 16,
        comments: 4,
        canEdit: true,
      ),
      const HallPost(
        author: 'Jamie',
        mood: 'Hopeful',
        tag: 'Room setup',
        message:
            'If today felt heavy, try making your room brighter than your thoughts. It helped me more than I expected.',
        likes: 42,
        comments: 12,
      ),
      const HallPost(
        author: 'Rin',
        mood: 'Calm',
        tag: 'Kind note',
        message:
            'Left a new encouragement message near the window prompt. The sunset version is my favorite.',
        likes: 27,
        comments: 9,
      ),
      const HallPost(
        author: 'Harper',
        mood: 'Proud',
        tag: 'Bottle reward',
        message:
            'Answered three bottles this week and finally bought the cat bed. The reward loop feels good.',
        likes: 19,
        comments: 6,
      ),
    ];
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filteredPosts = _filteredPosts();

    return RefreshIndicator(
      onRefresh: _refreshPosts,
      color: AppColors.clay,
      child: AppPage(
        title: '',
        subtitle: '',
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value.trim();
                    });
                  },
                  decoration: InputDecoration(
                    hintText: 'Search posts, moods, or tags',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _searchQuery.isEmpty
                        ? null
                        : IconButton(
                            onPressed: () {
                              _searchController.clear();
                              setState(() {
                                _searchQuery = '';
                              });
                            },
                            icon: const Icon(Icons.close_rounded),
                          ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.8),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 0,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              IconButton.filled(
                onPressed: _openCreatePost,
                icon: const Icon(Icons.edit_rounded),
                tooltip: 'Create new post',
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (filteredPosts.isEmpty)
            SoftCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'No posts match that search yet.',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Try a different word or create the first post for that mood.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          for (final post in filteredPosts) ...[
            _HallPostCard(
              post: post,
              onEdit: post.canEdit
                  ? () => _openCreatePost(existingPost: post)
                  : null,
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  Future<void> _refreshPosts() async {
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  List<HallPost> _filteredPosts() {
    if (_searchQuery.isEmpty) {
      return List<HallPost>.unmodifiable(_posts);
    }

    final needle = _searchQuery.toLowerCase();
    return _posts
        .where((post) {
          return post.author.toLowerCase().contains(needle) ||
              post.mood.toLowerCase().contains(needle) ||
              post.tag.toLowerCase().contains(needle) ||
              post.message.toLowerCase().contains(needle);
        })
        .toList(growable: false);
  }

  Future<void> _openCreatePost({HallPost? existingPost}) async {
    final createdPost = await Navigator.of(context).push<HallPost>(
      MaterialPageRoute<HallPost>(
        builder: (_) => CreatePostScreen(existingPost: existingPost),
      ),
    );

    if (createdPost == null) {
      return;
    }

    setState(() {
      if (existingPost != null) {
        final index = _posts.indexOf(existingPost);
        if (index != -1) {
          _posts[index] = createdPost;
          return;
        }
      }
      _posts.insert(0, createdPost);
    });
  }
}

class _HallPostCard extends StatelessWidget {
  const _HallPostCard({required this.post, this.onEdit});

  final HallPost post;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SoftCard(
      child: Column(
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
              TagChip(label: post.tag, icon: Icons.sell_rounded),
              // if (onEdit != null) ...[
              //   const SizedBox(width: 8),
              //   IconButton.filledTonal(
              //     onPressed: onEdit,
              //     icon: const Icon(Icons.edit_rounded),
              //     tooltip: 'Edit post',
              //   ),
              // ],
            ],
          ),
          const SizedBox(height: 16),
          Text(post.message, style: theme.textTheme.bodyLarge),
          const SizedBox(height: 16),
          Row(
            children: [
              const Icon(
                Icons.favorite_rounded,
                size: 18,
                color: AppColors.clay,
              ),
              const SizedBox(width: 6),
              Text('${post.likes} likes', style: theme.textTheme.bodyMedium),
              const Spacer(),
              const Icon(
                Icons.mode_comment_outlined,
                size: 18,
                color: AppColors.muted,
              ),
              const SizedBox(width: 4),
              Text('${post.comments}', style: theme.textTheme.bodyMedium),
            ],
          ),
        ],
      ),
    );
  }
}
