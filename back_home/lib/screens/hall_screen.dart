import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../auth/app_auth_controller.dart';
import '../widgets/app_ui.dart';
import '../widgets/hall_post_card.dart';
import 'create_post_screen.dart';
import 'hall_post.dart';
import 'hall_post_thread_screen.dart';
import 'hall_user_profile_screen.dart';

class HallScreen extends StatefulWidget {
  const HallScreen({required this.authController, super.key});

  final AppAuthController authController;

  @override
  State<HallScreen> createState() => _HallScreenState();
}

class _HallScreenState extends State<HallScreen> {
  late final TextEditingController _searchController;
  late final CollectionReference<Map<String, dynamic>> _postsRef;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _postsRef = FirebaseFirestore.instance.collection('posts');
    unawaited(_seedSamplePostsIfEmpty());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentUid = widget.authController.currentUser?.uid;

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
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _postsRef
                .orderBy('createdAt', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return _MessageCard(
                  title: 'Could not load the Hall.',
                  body: 'Check your connection and pull down to try again.',
                );
              }

              if (snapshot.connectionState == ConnectionState.waiting &&
                  !snapshot.hasData) {
                return const Padding(
                  padding: EdgeInsets.only(top: 24),
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              final allPosts = (snapshot.data?.docs ?? const [])
                  .map((doc) => HallPost.fromDoc(doc, currentUid: currentUid))
                  .toList(growable: false);
              final posts = _filterPosts(allPosts);

              if (posts.isEmpty) {
                return _MessageCard(
                  title: _searchQuery.isEmpty
                      ? 'No posts in the Hall yet.'
                      : 'No posts match that search yet.',
                  body: _searchQuery.isEmpty
                      ? 'Tap the pencil to share the first one.'
                      : 'Try a different word or create the first post for that mood.',
                );
              }

              return Column(
                children: [
                  for (final post in posts) ...[
                    HallPostCard(
                      post: post,
                      onLikeTap: () => _toggleLike(post),
                      onCommentTap: () => _openPostThread(post),
                      onAuthorTap: () => _openUserProfile(post),
                      onEdit: post.canEdit
                          ? () => _openCreatePost(existingPost: post)
                          : null,
                    ),
                    const SizedBox(height: 12),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _refreshPosts() async {
    // The list is backed by a live Firestore stream, so this just lets the
    // pull-to-refresh indicator settle.
    await Future<void>.delayed(const Duration(milliseconds: 400));
  }

  List<HallPost> _filterPosts(List<HallPost> posts) {
    if (_searchQuery.isEmpty) {
      return posts;
    }

    final needle = _searchQuery.toLowerCase();
    return posts
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
        builder: (_) => CreatePostScreen(
          existingPost: existingPost,
          authorName: _currentUserName(),
          authorUid: widget.authController.currentUser?.uid,
          authorPhotoUrl: widget.authController.currentUser?.photoURL,
        ),
      ),
    );

    if (createdPost == null) {
      return;
    }

    try {
      final existingId = existingPost?.id;
      if (existingId != null) {
        await _postsRef.doc(existingId).update({
          'topic': createdPost.topic,
          'message': createdPost.message,
          'mood': createdPost.mood,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        await _postsRef.add({
          ...createdPost.toMap(),
          'likedBy': <String>[],
          'createdAt': Timestamp.now(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (_) {
      _showError('Could not save your post. Please try again.');
    }
  }

  Future<void> _openPostThread(HallPost post) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => HallPostThreadScreen(
          post: post,
          authorName: _currentUserName(),
          authorUid: widget.authController.currentUser?.uid,
          authorPhotoUrl: widget.authController.currentUser?.photoURL,
        ),
      ),
    );
  }

  Future<void> _toggleLike(HallPost post) async {
    final postId = post.id;
    if (postId == null) {
      return;
    }

    final uid = widget.authController.currentUser?.uid;
    final willLike = !post.likedByMe;
    final update = <String, dynamic>{
      'likes': FieldValue.increment(willLike ? 1 : -1),
    };
    if (uid != null) {
      update['likedBy'] = willLike
          ? FieldValue.arrayUnion([uid])
          : FieldValue.arrayRemove([uid]);
    }

    try {
      await _postsRef.doc(postId).update(update);
    } catch (_) {
      _showError('Could not update that like. Please try again.');
    }
  }

  Future<void> _openUserProfile(HallPost post) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => HallUserProfileScreen(
          displayName: post.author,
          uid: post.authorUid,
          photoUrl: post.authorPhotoUrl,
          mood: post.mood,
        ),
      ),
    );
  }

  void _showError(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _currentUserName() {
    final currentUser = widget.authController.currentUser;
    final displayName = currentUser?.displayName?.trim();
    if (displayName != null && displayName.isNotEmpty) {
      return displayName;
    }
    return currentUser?.phoneNumber ?? 'You';
  }

  Future<void> _seedSamplePostsIfEmpty() async {
    try {
      final existing = await _postsRef.limit(1).get();
      if (existing.docs.isNotEmpty) {
        return;
      }

      final batch = FirebaseFirestore.instance.batch();
      _sampleSeedPosts().forEach((id, data) {
        batch.set(_postsRef.doc(id), data);
      });
      await batch.commit();
    } catch (_) {
      // If seeding fails (offline, rules), the empty state is shown instead.
    }
  }

  Map<String, Map<String, dynamic>> _sampleSeedPosts() {
    final now = DateTime.now().millisecondsSinceEpoch;

    Map<String, dynamic> comment(
      String author,
      String message,
      int minutesAgo,
    ) {
      final createdAtMillis = now - minutesAgo * 60000;
      return {
        'id': 'seed_${author}_$createdAtMillis',
        'author': author,
        'message': message,
        'authorUid': null,
        'authorPhotoUrl': null,
        'createdAtMillis': createdAtMillis,
        'likes': 0,
        'likedBy': <String>[],
      };
    }

    Map<String, dynamic> post({
      required String author,
      required String mood,
      required String topic,
      required String message,
      required int likes,
      required List<Map<String, dynamic>> thread,
      required int order,
    }) {
      final createdAt = Timestamp.fromMillisecondsSinceEpoch(
        now - order * 60000,
      );
      return {
        'author': author,
        'authorUid': null,
        'authorPhotoUrl': null,
        'mood': mood,
        'topic': topic,
        'message': message,
        'likes': likes,
        'likedBy': <String>[],
        'thread': thread,
        'createdAt': createdAt,
        'updatedAt': createdAt,
      };
    }

    return {
      'seed_soft_room': post(
        author: 'Sky',
        mood: 'Hopeful',
        topic: 'Daily Life',
        message:
            'Trying to make my room softer tonight. I picked the light green smile today and I want to keep that feeling going.',
        likes: 16,
        order: 1,
        thread: [
          comment('Jamie', 'That sounds like a really good reset.', 24),
          comment(
            'Rin',
            'The light green mood always feels gentle to me too.',
            18,
          ),
          comment(
            'Harper',
            'Soft rooms help more than people give them credit for.',
            11,
          ),
        ],
      ),
      'seed_room_setup': post(
        author: 'Jamie',
        mood: 'Hopeful',
        topic: 'Room setup',
        message:
            'If today felt heavy, try making your room brighter than your thoughts. It helped me more than I expected.',
        likes: 42,
        order: 2,
        thread: [
          comment(
            'Rin',
            'Changing the lamp color really does shift the whole mood.',
            95,
          ),
          comment(
            'Harper',
            'I open the curtains first and it helps every time.',
            78,
          ),
        ],
      ),
      'seed_kind_note': post(
        author: 'Rin',
        mood: 'Calm',
        topic: 'Kind note',
        message:
            'Left a new encouragement message near the window prompt. The sunset version is my favorite.',
        likes: 27,
        order: 3,
        thread: [
          comment('Jamie', 'That is such a sweet little detail.', 88),
          comment(
            'Harper',
            'Now I want a whole set of notes around the room.',
            34,
          ),
        ],
      ),
      'seed_bottle_reward': post(
        author: 'Harper',
        mood: 'Proud',
        topic: 'Bottle reward',
        message:
            'Answered three bottles this week and finally bought the cat bed. The reward loop feels good.',
        likes: 19,
        order: 4,
        thread: [
          comment('Jamie', 'Three bottles in one week is impressive.', 73),
          comment(
            'Rin',
            'The cat bed is one of the cutest rewards in the shop.',
            51,
          ),
        ],
      ),
    };
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(body, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}
