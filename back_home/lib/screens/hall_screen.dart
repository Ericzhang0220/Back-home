import 'package:flutter/material.dart';

import '../widgets/app_ui.dart';
import '../widgets/hall_post_card.dart';
import 'create_post_screen.dart';
import 'hall_post.dart';
import 'hall_post_thread_screen.dart';

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
      HallPost(
        author: 'You',
        mood: 'Hopeful',
        topic: 'Daily Life',
        message:
            'Trying to make my room softer tonight. I picked the light green smile today and I want to keep that feeling going.',
        likes: 16,
        thread: _seedThread(
          count: 4,
          samples: const [
            HallComment(
              author: 'Jamie',
              message: 'That sounds like a really good reset.',
              sentAt: '24m',
            ),
            HallComment(
              author: 'Rin',
              message: 'The light green mood always feels gentle to me too.',
              sentAt: '18m',
            ),
            HallComment(
              author: 'Harper',
              message: 'Soft rooms help more than people give them credit for.',
              sentAt: '11m',
            ),
            HallComment(
              author: 'You',
              message: 'I think I am going to keep leaning into that tonight.',
              sentAt: '6m',
              isMe: true,
            ),
          ],
        ),
        canEdit: true,
      ),
      HallPost(
        author: 'Jamie',
        mood: 'Hopeful',
        topic: 'Room setup123',
        message:
            'If today felt heavy, try making your room brighter than your thoughts. It helped me more than I expected.',
        likes: 42,
        thread: _seedThread(
          count: 12,
          samples: const [
            HallComment(
              author: 'You',
              message: 'I needed this reminder today.',
              sentAt: '2h',
              isMe: true,
            ),
            HallComment(
              author: 'Rin',
              message:
                  'Changing the lamp color really does shift the whole mood.',
              sentAt: '95m',
            ),
            HallComment(
              author: 'Harper',
              message: 'I open the curtains first and it helps every time.',
              sentAt: '78m',
            ),
          ],
        ),
      ),
      HallPost(
        author: 'Rin',
        mood: 'Calm',
        topic: 'Kind note',
        message:
            'Left a new encouragement message near the window prompt. The sunset version is my favorite.',
        likes: 27,
        thread: _seedThread(
          count: 9,
          samples: const [
            HallComment(
              author: 'Jamie',
              message: 'That is such a sweet little detail.',
              sentAt: '88m',
            ),
            HallComment(
              author: 'You',
              message: 'The sunset version felt surprisingly emotional.',
              sentAt: '52m',
              isMe: true,
            ),
            HallComment(
              author: 'Harper',
              message: 'Now I want a whole set of notes around the room.',
              sentAt: '34m',
            ),
          ],
        ),
      ),
      HallPost(
        author: 'Harper',
        mood: 'Proud',
        topic: 'Bottle reward',
        message:
            'Answered three bottles this week and finally bought the cat bed. The reward loop feels good.',
        likes: 19,
        thread: _seedThread(
          count: 6,
          samples: const [
            HallComment(
              author: 'Jamie',
              message: 'Three bottles in one week is impressive.',
              sentAt: '73m',
            ),
            HallComment(
              author: 'Rin',
              message: 'The cat bed is one of the cutest rewards in the shop.',
              sentAt: '51m',
            ),
            HallComment(
              author: 'You',
              message: 'Okay that convinced me to save up for it too.',
              sentAt: '16m',
              isMe: true,
            ),
          ],
        ),
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
                    hintText: 'Search posts, moods, or topics',
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
            HallPostCard(
              post: post,
              onLikeTap: () => _toggleLike(post),
              onCommentTap: () => _openPostThread(post),
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
              post.topic.toLowerCase().contains(needle) ||
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

  Future<void> _openPostThread(HallPost post) async {
    final updatedPost = await Navigator.of(context).push<HallPost>(
      MaterialPageRoute<HallPost>(
        builder: (_) => HallPostThreadScreen(post: post),
      ),
    );

    if (updatedPost == null) {
      return;
    }

    final index = _posts.indexOf(post);
    if (index == -1) {
      return;
    }

    setState(() {
      _posts[index] = updatedPost;
    });
  }

  void _toggleLike(HallPost post) {
    final index = _posts.indexOf(post);
    if (index == -1) {
      return;
    }

    setState(() {
      _posts[index] = post.copyWith(
        likedByMe: !post.likedByMe,
        likes: post.likes + (post.likedByMe ? -1 : 1),
      );
    });
  }

  List<HallComment> _seedThread({
    required int count,
    required List<HallComment> samples,
  }) {
    return List<HallComment>.generate(count, (index) {
      final sample = samples[index % samples.length];
      return sample.copyWith(sentAt: _seedTimeLabel(index, count));
    }, growable: false);
  }

  String _seedTimeLabel(int index, int count) {
    final minutesAgo = (count - index) * 9 + 3;
    if (minutesAgo < 60) {
      return '${minutesAgo}m';
    }

    final hoursAgo = minutesAgo ~/ 60;
    final remainderMinutes = minutesAgo % 60;
    if (remainderMinutes == 0) {
      return '${hoursAgo}h';
    }
    return '${hoursAgo}h ${remainderMinutes}m';
  }
}
