import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../chat/human_friends_repository.dart';
import '../widgets/app_ui.dart';
import '../widgets/profile_avatar.dart';

/// The inbox behind the profile screen's mail button: people who saved you and
/// are waiting to be saved back.
class FriendRequestsScreen extends StatelessWidget {
  const FriendRequestsScreen({super.key, required this.repository});

  /// Null when signed out, which leaves nothing to answer.
  final HumanFriendsRepository? repository;

  @override
  Widget build(BuildContext context) {
    final repository = this.repository;

    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: AppBar(
        backgroundColor: AppColors.cream.withValues(alpha: 0.94),
        foregroundColor: AppColors.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          'Friend requests',
          style: Theme.of(context).textTheme.titleLarge,
        ),
      ),
      body: Stack(
        children: [
          const AmbientBackground(showSideGlow: true),
          SafeArea(
            top: false,
            child: repository == null
                ? const _RequestsMessage(
                    text: 'Sign in to see your friend requests.',
                  )
                : StreamBuilder<List<String>>(
                    stream: repository.watchIncomingRequestUids(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final requesterUids = snapshot.data ?? const <String>[];
                      if (requesterUids.isEmpty) {
                        return const _RequestsMessage(
                          text:
                              'No friend requests right now.\nWhen someone '
                              'saves you from the Human tab, they will show '
                              'up here.',
                        );
                      }

                      return AppPage(
                        title: '',
                        subtitle: '',
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 140),
                        children: [
                          SectionHeader(
                            title: requesterUids.length == 1
                                ? '1 person wants to connect'
                                : '${requesterUids.length} people want to '
                                      'connect',
                            subtitle:
                                'Accepting saves them to your people too.',
                          ),
                          const SizedBox(height: 14),
                          for (final requesterUid in requesterUids) ...[
                            _FriendRequestTile(
                              requesterUid: requesterUid,
                              repository: repository,
                            ),
                            const SizedBox(height: 12),
                          ],
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _RequestsMessage extends StatelessWidget {
  const _RequestsMessage({required this.text});

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

class _FriendRequestTile extends StatefulWidget {
  const _FriendRequestTile({
    required this.requesterUid,
    required this.repository,
  });

  final String requesterUid;
  final HumanFriendsRepository repository;

  @override
  State<_FriendRequestTile> createState() => _FriendRequestTileState();
}

class _FriendRequestTileState extends State<_FriendRequestTile> {
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
      // The stream drops the tile on success, so there is nothing to reset.
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
