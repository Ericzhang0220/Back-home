import 'package:flutter/material.dart';

import '../widgets/app_ui.dart';
import 'hall_post.dart';

class HallPostThreadScreen extends StatefulWidget {
  const HallPostThreadScreen({required this.post, super.key});

  final HallPost post;

  @override
  State<HallPostThreadScreen> createState() => _HallPostThreadScreenState();
}

class _HallPostThreadScreenState extends State<HallPostThreadScreen> {
  late HallPost _post;
  late final TextEditingController _commentController;
  late final FocusNode _commentFocusNode;
  late final ScrollController _threadScrollController;
  bool _composerExpanded = false;

  @override
  void initState() {
    super.initState();
    _post = widget.post;
    _commentController = TextEditingController();
    _commentFocusNode = FocusNode();
    _commentFocusNode.addListener(_handleComposerFocusChanged);
    _threadScrollController = ScrollController();
  }

  @override
  void dispose() {
    _commentController.dispose();
    _commentFocusNode.removeListener(_handleComposerFocusChanged);
    _commentFocusNode.dispose();
    _threadScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final bottomInset = mediaQuery.viewInsets.bottom;
    final composerHeight = _composerExpanded ? 88.0 : 62.0;
    final composerBottomPadding = mediaQuery.padding.bottom + bottomInset + 16;
    final scrollBottomPadding = composerHeight + composerBottomPadding + 20;

    return PopScope<HallPost>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          return;
        }
        _close();
      },
      child: Scaffold(
        backgroundColor: AppColors.cream,
        resizeToAvoidBottomInset: false,
        body: Stack(
          children: [
            const AmbientBackground(),
            SafeArea(
              bottom: false,
              child: GestureDetector(
                onTap: _dismissKeyboard,
                behavior: HitTestBehavior.translucent,
                child: Column(
                  children: [
                    Expanded(
                      child: CustomScrollView(
                        controller: _threadScrollController,
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        slivers: [
                          SliverToBoxAdapter(
                            child: _ThreadHeader(post: _post, onBack: _close),
                          ),
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
                              child: _ThreadPostSummary(
                                post: _post,
                                onLikeTap: _toggleLike,
                                onCommentTap: _focusComposer,
                              ),
                            ),
                          ),
                          if (_post.thread.isEmpty)
                            SliverFillRemaining(
                              hasScrollBody: false,
                              child: Padding(
                                padding: EdgeInsets.only(
                                  left: 18,
                                  right: 18,
                                  bottom: scrollBottomPadding,
                                ),
                                child: _EmptyThread(onReplyTap: _focusComposer),
                              ),
                            )
                          else
                            SliverPadding(
                              padding: EdgeInsets.fromLTRB(
                                18,
                                4,
                                18,
                                scrollBottomPadding,
                              ),
                              sliver: SliverList.separated(
                                itemCount: _post.thread.length,
                                itemBuilder: (context, index) {
                                  final comment = _post.thread[index];
                                  return _CommentListItem(comment: comment);
                                },
                                separatorBuilder: (_, _) => const Divider(
                                  height: 24,
                                  color: Colors.transparent,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    AnimatedPadding(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOut,
                      padding: EdgeInsets.fromLTRB(
                        20,
                        12,
                        20,
                        composerBottomPadding,
                      ),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        switchInCurve: Curves.easeOut,
                        switchOutCurve: Curves.easeIn,
                        child: _composerExpanded
                            ? _CommentComposer(
                                key: const ValueKey('expanded-composer'),
                                controller: _commentController,
                                focusNode: _commentFocusNode,
                                onChanged: (_) => setState(() {}),
                                onSubmitted: (_) => _submitComment(),
                                onSend: _submitComment,
                                onTapOutside: (_) => _dismissKeyboard(),
                              )
                            : _CommentComposerTrigger(
                                key: const ValueKey('collapsed-composer'),
                                onTap: _focusComposer,
                              ),
                      ),
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

  void _toggleLike() {
    setState(() {
      _post = _post.copyWith(
        likedByMe: !_post.likedByMe,
        likes: _post.likes + (_post.likedByMe ? -1 : 1),
      );
    });
  }

  void _focusComposer() {
    if (!_composerExpanded) {
      setState(() {
        _composerExpanded = true;
      });
    }
    FocusScope.of(context).requestFocus(_commentFocusNode);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  void _submitComment() {
    final message = _commentController.text.trim();
    if (message.isEmpty) {
      return;
    }

    setState(() {
      _post = _post.copyWith(
        thread: [
          ..._post.thread,
          const HallComment(
            author: 'You',
            message: '',
            sentAt: 'Now',
            isMe: true,
          ).copyWith(message: message),
        ],
      );
      _commentController.clear();
    });

    _commentFocusNode.unfocus();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  void _scrollToBottom() {
    if (!_threadScrollController.hasClients) {
      return;
    }
    _threadScrollController.animateTo(
      _threadScrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  void _dismissKeyboard() {
    final focusScope = FocusScope.of(context);
    if (!focusScope.hasPrimaryFocus && focusScope.focusedChild != null) {
      focusScope.unfocus();
    }
  }

  void _handleComposerFocusChanged() {
    if (!mounted) {
      return;
    }

    if (_commentFocusNode.hasFocus) {
      if (!_composerExpanded) {
        setState(() {
          _composerExpanded = true;
        });
      }
      return;
    }

    if (_composerExpanded && _commentController.text.trim().isEmpty) {
      setState(() {
        _composerExpanded = false;
      });
    }
  }

  void _close() {
    Navigator.of(context).pop(_post);
  }
}

class _EmptyThread extends StatelessWidget {
  const _EmptyThread({required this.onReplyTap});

  final VoidCallback onReplyTap;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.forum_outlined, size: 34, color: AppColors.muted),
            const SizedBox(height: 14),
            Text(
              'No replies yet.',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Say something kind and start the thread.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onReplyTap,
              child: const Text('Write a comment'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThreadHeader extends StatelessWidget {
  const _ThreadHeader({required this.post, required this.onBack});

  final HallPost post;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 18, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
          ),
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
                Text(
                  post.topic,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${post.author}  ·  ${post.mood}',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.muted,
                        ),
                      ),
                    ),
                    Text(
                      'All comments ${post.comments}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.clay,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ThreadPostSummary extends StatelessWidget {
  const _ThreadPostSummary({
    required this.post,
    required this.onLikeTap,
    required this.onCommentTap,
  });

  final HallPost post;
  final VoidCallback onLikeTap;
  final VoidCallback onCommentTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.84),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.stroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              TopicChip(label: post.topic, icon: Icons.sell_rounded),
              const Spacer(),
              Text(post.mood, style: theme.textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            post.message,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _ThreadAction(
                icon: post.likedByMe
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                label: '${post.likes}',
                onTap: onLikeTap,
                active: post.likedByMe,
              ),
              const SizedBox(width: 18),
              _ThreadAction(
                icon: Icons.mode_comment_outlined,
                label: '${post.comments}',
                onTap: onCommentTap,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ThreadAction extends StatelessWidget {
  const _ThreadAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 18,
            color: active ? AppColors.clay : AppColors.muted,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: active ? AppColors.ink : AppColors.muted,
            ),
          ),
        ],
      ),
    );
  }
}

class _CommentListItem extends StatelessWidget {
  const _CommentListItem({required this.comment});

  final HallComment comment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: comment.isMe
              ? const Color(0xFFE7D0BD)
              : AppColors.blush.withValues(alpha: 0.85),
          child: Text(comment.author.characters.first),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      comment.author,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(comment.sentAt, style: theme.textTheme.bodySmall),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                comment.message,
                style: theme.textTheme.bodyLarge?.copyWith(height: 1.4),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CommentComposer extends StatelessWidget {
  const _CommentComposer({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onSubmitted,
    required this.onSend,
    required this.onTapOutside,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onSend;
  final TapRegionCallback onTapOutside;

  @override
  Widget build(BuildContext context) {
    final canSend = controller.text.trim().isNotEmpty;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.84),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: AppColors.stroke),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onChanged: onChanged,
              onSubmitted: onSubmitted,
              onTapOutside: onTapOutside,
              decoration: const InputDecoration(
                hintText: 'Write a comment...',
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 10),
          IconButton.filled(
            onPressed: canSend ? onSend : null,
            icon: const Icon(Icons.arrow_upward_rounded),
            tooltip: 'Send comment',
          ),
        ],
      ),
    );
  }
}

class _CommentComposerTrigger extends StatelessWidget {
  const _CommentComposerTrigger({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(26),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.84),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: AppColors.stroke),
            boxShadow: const [
              BoxShadow(
                color: Color(0x12000000),
                blurRadius: 24,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: [
              Text(
                'Write a comment...',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
              ),
              const Spacer(),
              const Icon(Icons.edit_outlined, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}
