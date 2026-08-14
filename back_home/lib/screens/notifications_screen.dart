import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../chat/human_friends_repository.dart';
import '../notifications/notifications_repository.dart';
import '../widgets/app_ui.dart';
import '../widgets/profile_avatar.dart';

/// The inbox behind the profile screen's mail button.
///
/// Merges two sources: friend requests, which are answered here, and the
/// notification feed (likes, comments, conduct warnings, system updates),
/// which is read and cleared.
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({
    super.key,
    required this.friendsRepository,
    required this.notificationsRepository,
  });

  /// Both null when signed out, which leaves nothing to show.
  final HumanFriendsRepository? friendsRepository;
  final NotificationsRepository? notificationsRepository;

  @override
  Widget build(BuildContext context) {
    final friendsRepository = this.friendsRepository;
    final notificationsRepository = this.notificationsRepository;

    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: AppBar(
        backgroundColor: AppColors.cream.withValues(alpha: 0.94),
        foregroundColor: AppColors.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          'Notifications',
          style: Theme.of(context).textTheme.titleLarge,
        ),
      ),
      body: Stack(
        children: [
          const AmbientBackground(showSideGlow: true),
          SafeArea(
            top: false,
            child: friendsRepository == null || notificationsRepository == null
                ? const _InboxMessage(
                    text: 'Sign in to see your notifications.',
                  )
                : _InboxList(
                    friendsRepository: friendsRepository,
                    notificationsRepository: notificationsRepository,
                  ),
          ),
        ],
      ),
    );
  }
}

class _InboxList extends StatelessWidget {
  const _InboxList({
    required this.friendsRepository,
    required this.notificationsRepository,
  });

  final HumanFriendsRepository friendsRepository;
  final NotificationsRepository notificationsRepository;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<String>>(
      stream: friendsRepository.watchIncomingRequestUids(),
      builder: (context, requestsSnapshot) {
        return StreamBuilder<List<AppNotification>>(
          stream: notificationsRepository.watchNotifications(),
          builder: (context, notificationsSnapshot) {
            final isLoading =
                requestsSnapshot.connectionState == ConnectionState.waiting &&
                notificationsSnapshot.connectionState ==
                    ConnectionState.waiting;
            if (isLoading) {
              return const Center(child: CircularProgressIndicator());
            }

            final requesterUids = requestsSnapshot.data ?? const <String>[];
            final notifications =
                notificationsSnapshot.data ?? const <AppNotification>[];

            if (requesterUids.isEmpty && notifications.isEmpty) {
              return const _InboxMessage(
                text:
                    'Nothing new right now.\nFriend requests, likes, replies '
                    'and updates will show up here.',
              );
            }

            return AppPage(
              title: '',
              subtitle: '',
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 140),
              children: [
                if (requesterUids.isNotEmpty) ...[
                  SectionHeader(
                    title: requesterUids.length == 1
                        ? '1 friend request'
                        : '${requesterUids.length} friend requests',
                    subtitle: 'Accepting saves them to your people too.',
                  ),
                  const SizedBox(height: 14),
                  for (final requesterUid in requesterUids) ...[
                    _FriendRequestCard(
                      requesterUid: requesterUid,
                      repository: friendsRepository,
                    ),
                    const SizedBox(height: 12),
                  ],
                  const SizedBox(height: 16),
                ],
                if (notifications.isNotEmpty) ...[
                  const SectionHeader(title: 'Recent'),
                  const SizedBox(height: 14),
                  for (final notification in notifications) ...[
                    _NotificationCard(
                      notification: notification,
                      onDismiss: () => notificationsRepository.dismiss(
                        notification.id,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ],
              ],
            );
          },
        );
      },
    );
  }
}

class _InboxMessage extends StatelessWidget {
  const _InboxMessage({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }
}

/// Read-only row for everything that is not a friend request. The icon and
/// tint carry the type, since a warning should not look like a like.
class _NotificationCard extends StatelessWidget {
  const _NotificationCard({required this.notification, required this.onDismiss});

  final AppNotification notification;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final isWarning = notification.type == AppNotificationType.warning;
    final theme = Theme.of(context);

    return SoftCard(
      padding: const EdgeInsets.all(18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 42,
            width: 42,
            decoration: BoxDecoration(
              color: isWarning
                  ? const Color(0xFFF7DEDA)
                  : AppColors.blush.withValues(alpha: 0.75),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              _icon,
              size: 20,
              color: isWarning ? const Color(0xFFC34A3F) : AppColors.clay,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: isWarning ? const Color(0xFFC34A3F) : null,
                  ),
                ),
                if (_body != null) ...[
                  const SizedBox(height: 6),
                  Text(_body!, style: theme.textTheme.bodyMedium),
                ],
                if (_timestamp != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    _timestamp!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            tooltip: 'Dismiss',
            visualDensity: VisualDensity.compact,
            onPressed: onDismiss,
            icon: const Icon(Icons.close_rounded, size: 18),
            color: AppColors.muted,
          ),
        ],
      ),
    );
  }

  IconData get _icon {
    switch (notification.type) {
      case AppNotificationType.like:
        return Icons.favorite_rounded;
      case AppNotificationType.comment:
        return Icons.mode_comment_rounded;
      case AppNotificationType.warning:
        return Icons.report_gmailerrorred_rounded;
      case AppNotificationType.system:
        return Icons.campaign_rounded;
    }
  }

  String get _title {
    final actor = notification.actorName ?? 'Someone';
    switch (notification.type) {
      case AppNotificationType.like:
        return '$actor liked your post';
      case AppNotificationType.comment:
        return notification.count == 1
            ? 'A new comment in $_topic'
            : '${notification.count} new comments in $_topic';
      case AppNotificationType.warning:
        return notification.title ?? 'Community guidelines warning';
      case AppNotificationType.system:
        return notification.title ?? 'Back Home update';
    }
  }

  String? get _body {
    switch (notification.type) {
      case AppNotificationType.like:
        return notification.topic == null ? null : 'In ${notification.topic}';
      case AppNotificationType.comment:
        final actor = notification.actorName;
        if (actor == null) {
          return null;
        }
        return notification.count == 1
            ? '$actor replied to you.'
            : 'Most recently from $actor.';
      case AppNotificationType.warning:
      case AppNotificationType.system:
        return notification.body;
    }
  }

  String get _topic => notification.topic ?? 'your post';

  String? get _timestamp {
    final createdAt = notification.createdAt;
    if (createdAt == null) {
      return null;
    }

    final elapsed = DateTime.now().difference(createdAt);
    if (elapsed.inMinutes < 1) {
      return 'Just now';
    }
    if (elapsed.inHours < 1) {
      return '${elapsed.inMinutes}m ago';
    }
    if (elapsed.inDays < 1) {
      return '${elapsed.inHours}h ago';
    }
    if (elapsed.inDays < 7) {
      return '${elapsed.inDays}d ago';
    }
    return '${createdAt.month}/${createdAt.day}/${createdAt.year}';
  }
}

class _FriendRequestCard extends StatefulWidget {
  const _FriendRequestCard({
    required this.requesterUid,
    required this.repository,
  });

  final String requesterUid;
  final HumanFriendsRepository repository;

  @override
  State<_FriendRequestCard> createState() => _FriendRequestCardState();
}

class _FriendRequestCardState extends State<_FriendRequestCard> {
  /// Set while a write is in flight so a double tap cannot answer twice.
  bool _isAnswering = false;

  Future<void> _answer({required bool accept}) async {
    if (_isAnswering) {
      return;
    }
    setState(() => _isAnswering = true);
    try {
      if (accept) {
        await widget.repository.acceptRequest(widget.requesterUid);
      } else {
        await widget.repository.rejectRequest(widget.requesterUid);
      }
      // The stream drops the card on success, so there is nothing to reset.
    } catch (_) {
      if (mounted) {
        setState(() => _isAnswering = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not answer that request.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // The requester's profile is read live rather than copied into the request,
    // so a name changed since it was sent still shows correctly.
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(widget.requesterUid)
          .snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data();
        final name =
            _stringValue(data?['displayName']) ??
            _stringValue(data?['email']) ??
            _stringValue(data?['phoneNumber']) ??
            'Back Home user';
        final handle =
            _stringValue(data?['email']) ??
            _stringValue(data?['phoneNumber']) ??
            '@${widget.requesterUid.substring(0, 6)}';

        return SoftCard(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ProfileAvatar(
                    displayName: name,
                    photoUrl: _stringValue(data?['photoUrl']),
                    radius: 24,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          handle,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isAnswering
                          ? null
                          : () => _answer(accept: false),
                      child: const Text('Reject'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _isAnswering
                          ? null
                          : () => _answer(accept: true),
                      child: const Text('Accept'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

String? _stringValue(Object? value) {
  if (value is! String || value.trim().isEmpty) {
    return null;
  }
  return value.trim();
}
