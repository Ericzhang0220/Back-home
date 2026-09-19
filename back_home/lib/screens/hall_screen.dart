import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../auth/app_auth_controller.dart';
import '../notifications/notifications_repository.dart';
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
      child: Scaffold(
        // appBar: AppBar(
        //   surfaceTintColor: Colors.transparent,
        //   backgroundColor: Colors.transparent,
        //   title: Row(
        //     children: [
        //       Expanded(
        //         child: TextField(
        //           controller: _searchController,
        //           onChanged: (value) {
        //             setState(() {
        //               _searchQuery = value.trim();
        //             });
        //           },
        //           decoration: InputDecoration(
        //             hintText: 'Search posts, moods, or topics',
        //             prefixIcon: const Icon(Icons.search_rounded),
        //             suffixIcon: _searchQuery.isEmpty
        //                 ? null
        //                 : IconButton(
        //                     onPressed: () {
        //                       _searchController.clear();
        //                       setState(() {
        //                         _searchQuery = '';
        //                       });
        //                     },
        //                     icon: const Icon(Icons.close_rounded),
        //                   ),
        //             border: OutlineInputBorder(
        //               borderRadius: BorderRadius.circular(22),
        //               borderSide: BorderSide.none,
        //             ),
        //             filled: true,
        //             fillColor: Colors.white.withValues(alpha: 0.8),
        //             contentPadding: const EdgeInsets.symmetric(
        //               horizontal: 16,
        //               vertical: 0,
        //             ),
        //           ),
        //         ),
        //       ),
        //       const SizedBox(width: 12),
        //       IconButton.filled(
        //         onPressed: _openCreatePost,
        //         icon: const Icon(Icons.edit_rounded),
        //         tooltip: 'Create new post',
        //       ),
        //     ],
        //   ),
        // ),
        body: Stack(
          children: [
            AppPage(
              title: '',
              subtitle: '',
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                const SizedBox(height: 20),
                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _postsRef
                      .orderBy('createdAt', descending: true)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return _MessageCard(
                        title: 'Could not load the Hall.',
                        body:
                            'Check your connection and pull down to try again.',
                      );
                    }

                    if (snapshot.connectionState == ConnectionState.waiting &&
                        !snapshot.hasData) {
                      return const Padding(
                        padding: EdgeInsets.only(top: 24),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }

                    final visibleDocs = (snapshot.data?.docs ?? const []).where(
                      (doc) {
                        final status = doc.data()['moderationStatus'];
                        // Existing seed/legacy posts have no moderation field.
                        // Every newly submitted poster must be explicitly
                        // approved by the server before it appears here.
                        return status == null || status == 'approved';
                      },
                    );
                    final allPosts = visibleDocs
                        .map(
                          (doc) =>
                              HallPost.fromDoc(doc, currentUid: currentUid),
                        )
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
                        for (var index = 0; index < posts.length; index++) ...[
                          StaggeredFadeIn(
                            key: ValueKey(_postAnimationKey(posts[index])),
                            delay: _postFadeDelay(index),
                            child: HallPostCard(
                              post: posts[index],
                              onLikeTap: () => _toggleLike(posts[index]),
                              onCommentTap: () => _openPostThread(posts[index]),
                              onAuthorTap: () => _openUserProfile(posts[index]),
                              onEdit: posts[index].canEdit
                                  ? () => _openCreatePost(
                                      existingPost: posts[index],
                                    )
                                  : null,
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                      ],
                    );
                  },
                ),
              ],
            ),
            Positioned(
              top: 0,
              left: MediaQuery.of(context).size.width * 0.05,
              child: SizedBox(
                width: MediaQuery.of(context).size.width * 0.9,
                height: 72,
                child: Row(
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
              ),
            ),
          ],
        ),
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

  String _postAnimationKey(HallPost post) {
    final id = post.id;
    if (id != null) {
      return 'hall-post-$id';
    }

    return 'hall-post-${post.author}-${post.lastUpdatedAt.millisecondsSinceEpoch}-${post.message.hashCode}';
  }

  Duration _postFadeDelay(int index) {
    return Duration(milliseconds: (55 * index).clamp(0, 420));
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

    if (createdPost == null || !mounted) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Checking your poster against the safety guidelines…'),
          duration: Duration(minutes: 1),
        ),
      );

    try {
      final payload = <String, dynamic>{
        'topic': createdPost.topic,
        'message': createdPost.message,
        'mood': createdPost.mood,
      };
      final existingPostId = existingPost?.id;
      if (existingPostId != null) {
        payload['postId'] = existingPostId;
      }
      final response = await FirebaseFunctions.instance
          .httpsCallable('submitHallPost')
          .call<dynamic>(payload);
      if (!mounted) {
        return;
      }

      final data = response.data;
      final status = data is Map ? data['status'] : null;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              status == 'approved'
                  ? existingPost == null
                        ? 'Poster approved and published.'
                        : 'Poster update approved and published.'
                  : 'This poster was not published. Check Notifications for the review details.',
            ),
          ),
        );
    } on FirebaseFunctionsException catch (error) {
      if (!mounted) {
        return;
      }
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              error.message ??
                  'Your poster could not be reviewed. Please try again.',
            ),
          ),
        );
    } catch (_) {
      if (!mounted) {
        return;
      }
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Could not reach the safety review. Please try again.',
            ),
          ),
        );
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
      await _notifyPostLike(post, willLike: willLike);
    } catch (_) {
      _showError('Could not update that like. Please try again.');
    }
  }

  /// Tells the post's author who liked it, and takes the notification back if
  /// the like is undone. Best effort: a failure here must not read as a failed
  /// like, which already landed.
  Future<void> _notifyPostLike(HallPost post, {required bool willLike}) async {
    final postId = post.id;
    final recipientUid = post.authorUid;
    final uid = widget.authController.currentUser?.uid;
    if (postId == null || recipientUid == null || uid == null) {
      return;
    }

    final notifications = NotificationsRepository(uid: uid);
    try {
      if (willLike) {
        await notifications.notifyLiked(
          recipientUid: recipientUid,
          postId: postId,
          topic: post.topic,
          actorName: _currentUserName(),
        );
      } else {
        await notifications.clearLike(
          recipientUid: recipientUid,
          postId: postId,
        );
      }
    } catch (_) {
      // Ignored on purpose — see above.
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
