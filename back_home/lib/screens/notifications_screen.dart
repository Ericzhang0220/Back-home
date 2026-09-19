import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../chat/human_friends_repository.dart';
import '../notifications/notifications_repository.dart';
import '../widgets/app_ui.dart';
import '../widgets/profile_avatar.dart';

/// The inbox behind the profile screen's mail button.
///
/// Merges two sources: friend requests, which are answered here, and the
/// notification feed (likes, comments, conduct warnings, system updates, and
/// Hall moderation results), which is read and cleared.
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

class _InboxList extends StatefulWidget {
  const _InboxList({
    required this.friendsRepository,
    required this.notificationsRepository,
  });

  final HumanFriendsRepository friendsRepository;
  final NotificationsRepository notificationsRepository;

  @override
  State<_InboxList> createState() => _InboxListState();
}

class _InboxListState extends State<_InboxList> {
  final GlobalKey _viewportKey = GlobalKey();
  final Map<String, GlobalKey> _itemKeys = {};
  final Set<String> _markingRead = {};
  late final Stream<List<IncomingFriendRequest>> _requestsStream;
  late final Stream<List<AppNotification>> _notificationsStream;
  List<IncomingFriendRequest> _requests = const [];
  List<AppNotification> _notifications = const [];
  bool _visibilityCheckScheduled = false;
  bool _isBulkActionRunning = false;

  @override
  void initState() {
    super.initState();
    _requestsStream = widget.friendsRepository.watchIncomingRequests();
    _notificationsStream = widget.notificationsRepository.watchNotifications();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<IncomingFriendRequest>>(
      stream: _requestsStream,
      builder: (context, requestsSnapshot) {
        return StreamBuilder<List<AppNotification>>(
          stream: _notificationsStream,
          builder: (context, notificationsSnapshot) {
            final isLoading =
                requestsSnapshot.connectionState == ConnectionState.waiting &&
                notificationsSnapshot.connectionState ==
                    ConnectionState.waiting;
            if (isLoading) {
              return const Center(child: CircularProgressIndicator());
            }

            final requests =
                requestsSnapshot.data ?? const <IncomingFriendRequest>[];
            final notifications =
                notificationsSnapshot.data ?? const <AppNotification>[];
            _requests = requests;
            _notifications = notifications;
            _scheduleVisibilityCheck();

            final hasUnread =
                requests.any((request) => !request.isRead) ||
                notifications.any((notification) => !notification.isRead);
            final hasRead =
                requests.any((request) => request.isRead) ||
                notifications.any((notification) => notification.isRead);

            if (requests.isEmpty && notifications.isEmpty) {
              return Column(
                children: [
                  const Expanded(
                    child: _InboxMessage(
                      text:
                          'Nothing new right now.\nNew followers, likes, system '
                          'updates and Hall reviews will show up here.',
                    ),
                  ),
                  _InboxActions(
                    isBusy: _isBulkActionRunning,
                    canMarkAllRead: false,
                    canDeleteRead: false,
                    onMarkAllRead: _markAllRead,
                    onDeleteRead: _deleteRead,
                  ),
                ],
              );
            }

            return Column(
              children: [
                Expanded(
                  child: SizedBox.expand(
                    key: _viewportKey,
                    child: NotificationListener<ScrollNotification>(
                      onNotification: (_) {
                        _scheduleVisibilityCheck();
                        return false;
                      },
                      child: AppPage(
                        title: '',
                        subtitle: '',
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                        children: [
                          if (requests.isNotEmpty) ...[
                            SectionHeader(
                              title: requests.length == 1
                                  ? '1 follower'
                                  : '${requests.length} followers',
                              subtitle:
                                  'Follow them back to add them to your people.',
                            ),
                            const SizedBox(height: 14),
                            for (final request in requests) ...[
                              SizedBox(
                                key: _itemKey(
                                  'request:${request.requesterUid}',
                                ),
                                child: _FriendRequestCard(
                                  requesterUid: request.requesterUid,
                                  isRead: request.isRead,
                                  repository: widget.friendsRepository,
                                ),
                              ),
                              const SizedBox(height: 12),
                            ],
                            const SizedBox(height: 16),
                          ],
                          if (notifications.isNotEmpty) ...[
                            const SectionHeader(title: 'Recent'),
                            const SizedBox(height: 14),
                            for (final notification in notifications) ...[
                              SizedBox(
                                key: _itemKey(
                                  'notification:${notification.id}',
                                ),
                                child: _NotificationCard(
                                  notification: notification,
                                ),
                              ),
                              const SizedBox(height: 12),
                            ],
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                _InboxActions(
                  isBusy: _isBulkActionRunning,
                  canMarkAllRead: hasUnread,
                  canDeleteRead: hasRead,
                  onMarkAllRead: _markAllRead,
                  onDeleteRead: _deleteRead,
                ),
              ],
            );
          },
        );
      },
    );
  }

  GlobalKey _itemKey(String id) => _itemKeys.putIfAbsent(id, GlobalKey.new);

  void _scheduleVisibilityCheck() {
    if (_visibilityCheckScheduled) {
      return;
    }
    _visibilityCheckScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _visibilityCheckScheduled = false;
      if (mounted) {
        _markFullyVisibleItemsRead();
      }
    });
  }

  void _markFullyVisibleItemsRead() {
    for (final request in _requests.where((request) => !request.isRead)) {
      final id = 'request:${request.requesterUid}';
      final isVisible = _isFullyVisible(_itemKeys[id]);
      if (isVisible && _markingRead.add(id)) {
        unawaited(_markRequestRead(request, id));
      } else if (!isVisible) {
        _markingRead.remove(id);
      }
    }
    for (final notification in _notifications.where(
      (notification) => !notification.isRead,
    )) {
      final id = 'notification:${notification.id}';
      final isVisible = _isFullyVisible(_itemKeys[id]);
      if (isVisible && _markingRead.add(id)) {
        unawaited(_markNotificationRead(notification, id));
      } else if (!isVisible) {
        _markingRead.remove(id);
      }
    }
  }

  bool _isFullyVisible(GlobalKey? itemKey) {
    final viewport = _viewportKey.currentContext?.findRenderObject();
    final item = itemKey?.currentContext?.findRenderObject();
    if (viewport is! RenderBox || item is! RenderBox) {
      return false;
    }

    final viewportOrigin = viewport.localToGlobal(Offset.zero);
    final itemOrigin = item.localToGlobal(Offset.zero);
    final viewportRect = viewportOrigin & viewport.size;
    final itemRect = itemOrigin & item.size;
    const tolerance = 0.5;
    return itemRect.top >= viewportRect.top - tolerance &&
        itemRect.bottom <= viewportRect.bottom + tolerance &&
        itemRect.left >= viewportRect.left - tolerance &&
        itemRect.right <= viewportRect.right + tolerance;
  }

  Future<void> _markRequestRead(
    IncomingFriendRequest request,
    String trackingId,
  ) async {
    try {
      await widget.friendsRepository.markRequestRead(request.requesterUid);
    } catch (_) {
      // A request may disappear while it is being marked (for example, if the
      // sender withdraws it). The live stream already reflects that outcome.
    } finally {
      _markingRead.remove(trackingId);
    }
  }

  Future<void> _markNotificationRead(
    AppNotification notification,
    String trackingId,
  ) async {
    try {
      await widget.notificationsRepository.markRead(notification.id);
    } catch (_) {
      // The notification may have been withdrawn while it was on screen.
    } finally {
      _markingRead.remove(trackingId);
    }
  }

  Future<void> _markAllRead() async {
    if (_isBulkActionRunning) {
      return;
    }
    setState(() => _isBulkActionRunning = true);
    try {
      await Future.wait([
        widget.friendsRepository.markAllIncomingRequestsRead(),
        widget.notificationsRepository.markAllRead(),
      ]);
    } catch (_) {
      if (mounted) {
        _showError('Could not mark every notification as read.');
      }
    } finally {
      if (mounted) {
        setState(() => _isBulkActionRunning = false);
      }
    }
  }

  Future<void> _deleteRead() async {
    if (_isBulkActionRunning) {
      return;
    }
    setState(() => _isBulkActionRunning = true);
    try {
      await Future.wait([
        widget.friendsRepository.deleteReadIncomingRequests(),
        widget.notificationsRepository.deleteRead(),
      ]);
    } catch (_) {
      if (mounted) {
        _showError('Could not delete the read notifications.');
      }
    } finally {
      if (mounted) {
        setState(() => _isBulkActionRunning = false);
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _InboxActions extends StatelessWidget {
  const _InboxActions({
    required this.isBusy,
    required this.canMarkAllRead,
    required this.canDeleteRead,
    required this.onMarkAllRead,
    required this.onDeleteRead,
  });

  final bool isBusy;
  final bool canMarkAllRead;
  final bool canDeleteRead;
  final VoidCallback onMarkAllRead;
  final VoidCallback onDeleteRead;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
      decoration: BoxDecoration(
        color: AppColors.cream.withValues(alpha: 0.98),
        border: const Border(top: BorderSide(color: AppColors.stroke)),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: isBusy || !canMarkAllRead ? null : onMarkAllRead,
              icon: const Icon(Icons.done_all_rounded),
              label: const Text('Mark all read'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton.tonalIcon(
              onPressed: isBusy || !canDeleteRead ? null : onDeleteRead,
              icon: const Icon(Icons.delete_sweep_outlined),
              label: const Text('Delete read'),
            ),
          ),
        ],
      ),
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
  const _NotificationCard({required this.notification});

  final AppNotification notification;

  @override
  Widget build(BuildContext context) {
    final isAlert =
        notification.type == AppNotificationType.warning ||
        notification.type == AppNotificationType.postRejected;
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
              color: isAlert
                  ? const Color(0xFFF7DEDA)
                  : AppColors.blush.withValues(alpha: 0.75),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              _icon,
              size: 20,
              color: isAlert ? const Color(0xFFC34A3F) : AppColors.clay,
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
                    color: isAlert ? const Color(0xFFC34A3F) : null,
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
          if (!notification.isRead)
            Container(
              width: 9,
              height: 9,
              margin: const EdgeInsets.only(top: 6),
              decoration: const BoxDecoration(
                color: AppColors.clay,
                shape: BoxShape.circle,
              ),
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
      case AppNotificationType.postRejected:
        return Icons.visibility_off_rounded;
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
      case AppNotificationType.postRejected:
        return notification.title ?? 'Your Hall poster was not approved';
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
      case AppNotificationType.postRejected:
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
    required this.isRead,
    required this.repository,
  });

  final String requesterUid;
  final bool isRead;
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
                          '$name followed you',
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium,
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
                  if (!widget.isRead)
                    Container(
                      width: 9,
                      height: 9,
                      decoration: const BoxDecoration(
                        color: AppColors.clay,
                        shape: BoxShape.circle,
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
                      child: const Text('Not now'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _isAnswering
                          ? null
                          : () => _answer(accept: true),
                      child: const Text('Follow back'),
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
