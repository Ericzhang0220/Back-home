import 'package:flutter/material.dart';

import '../widgets/app_ui.dart';
import '../widgets/hall_post_card.dart';
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

  @override
  void initState() {
    super.initState();
    _post = widget.post;
    _commentController = TextEditingController();
    _commentFocusNode = FocusNode();
    _threadScrollController = ScrollController();
  }

  @override
  void dispose() {
    _commentController.dispose();
    _commentFocusNode.dispose();
    _threadScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final bottomInset = mediaQuery.viewInsets.bottom;
    final composerBottomPadding = mediaQuery.padding.bottom + bottomInset + 16;

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
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
                      child: Row(
                        children: [
                          BackButton(onPressed: _close),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Post thread',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.headlineMedium,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Join the conversation below.',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                        child: SoftCard(
                          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                          child: Column(
                            children: [
                              HallPostCard(
                                post: _post,
                                onLikeTap: _toggleLike,
                                onCommentTap: _focusComposer,
                                embedded: true,
                              ),
                              const SizedBox(height: 18),
                              const Divider(height: 1),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  0,
                                  16,
                                  0,
                                  12,
                                ),
                                child: Row(
                                  children: [
                                    Text(
                                      'Comments',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleLarge,
                                    ),
                                    const SizedBox(width: 8),
                                    TopicChip(
                                      label:
                                          '${_post.comments} ${_post.comments == 1 ? 'reply' : 'replies'}',
                                      icon: Icons.chat_bubble_outline_rounded,
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: _post.thread.isEmpty
                                    ? _EmptyThread(onReplyTap: _focusComposer)
                                    : ListView.separated(
                                        controller: _threadScrollController,
                                        keyboardDismissBehavior:
                                            ScrollViewKeyboardDismissBehavior
                                                .onDrag,
                                        padding: const EdgeInsets.fromLTRB(
                                          0,
                                          4,
                                          0,
                                          24,
                                        ),
                                        itemCount: _post.thread.length,
                                        separatorBuilder: (_, _) =>
                                            const SizedBox(height: 16),
                                        itemBuilder: (context, index) {
                                          final comment = _post.thread[index];
                                          return _CommentBubble(
                                            comment: comment,
                                          );
                                        },
                                      ),
                              ),
                            ],
                          ),
                        ),
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
                      child: _CommentComposer(
                        controller: _commentController,
                        focusNode: _commentFocusNode,
                        onChanged: (_) => setState(() {}),
                        onSubmitted: (_) => _submitComment(),
                        onSend: _submitComment,
                        onTapOutside: (_) => _dismissKeyboard(),
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

class _CommentBubble extends StatelessWidget {
  const _CommentBubble({required this.comment});

  final HallComment comment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isMe = comment.isMe;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: [
        if (!isMe) ...[
          CircleAvatar(
            radius: 18,
            backgroundColor: AppColors.blush.withValues(alpha: 0.85),
            child: Text(comment.author.characters.first),
          ),
          const SizedBox(width: 10),
        ],
        Flexible(
          child: Column(
            crossAxisAlignment: isMe
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              Text(
                '${comment.author}  ${comment.sentAt}',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 6),
              Container(
                constraints: const BoxConstraints(maxWidth: 280),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: isMe
                      ? const Color(0xFFE7D0BD)
                      : Colors.white.withValues(alpha: 0.82),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.stroke),
                ),
                child: Text(comment.message, style: theme.textTheme.bodyLarge),
              ),
            ],
          ),
        ),
        if (isMe) ...[
          const SizedBox(width: 10),
          CircleAvatar(
            radius: 18,
            backgroundColor: const Color(0xFFE7D0BD),
            child: Text(comment.author.characters.first),
          ),
        ],
      ],
    );
  }
}

class _CommentComposer extends StatelessWidget {
  const _CommentComposer({
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
