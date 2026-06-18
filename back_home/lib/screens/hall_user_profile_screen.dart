import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../mood/mood_repository.dart';
import '../widgets/app_ui.dart';
import '../widgets/profile_avatar.dart';

class HallUserProfileScreen extends StatelessWidget {
  const HallUserProfileScreen({
    super.key,
    required this.displayName,
    this.uid,
    this.photoUrl,
    this.mood,
  });

  final String displayName;
  final String? uid;
  final String? photoUrl;
  final String? mood;

  @override
  Widget build(BuildContext context) {
    final uid = this.uid;
    if (uid == null || uid.isEmpty) {
      return _HallUserProfileView(
        displayName: displayName,
        photoUrl: photoUrl,
        mood: mood,
      );
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data();
        return _HallUserProfileView(
          displayName: _stringValue(data?['displayName']) ?? displayName,
          photoUrl: _stringValue(data?['photoUrl']) ?? photoUrl,
          mood: mood,
          uid: uid,
          visibility: _PublicProfileVisibility.fromData(data),
        );
      },
    );
  }

  static String? _stringValue(Object? value) {
    if (value is! String || value.trim().isEmpty) {
      return null;
    }
    return value.trim();
  }
}

class _HallUserProfileView extends StatelessWidget {
  const _HallUserProfileView({
    required this.displayName,
    this.uid,
    this.photoUrl,
    this.mood,
    this.visibility = const _PublicProfileVisibility(),
  });

  final String displayName;
  final String? uid;
  final String? photoUrl;
  final String? mood;
  final _PublicProfileVisibility visibility;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cream,
      body: Stack(
        children: [
          const AmbientBackground(showSideGlow: true),
          SafeArea(
            child: AppPage(
              title: '',
              subtitle: '',
              leading: BackButton(onPressed: () => Navigator.of(context).pop()),
              children: [
                Center(
                  child: ProfileAvatar(
                    displayName: displayName,
                    photoUrl: photoUrl,
                    radius: 52,
                    heroTag: 'hall-avatar-${uid ?? displayName}',
                  ),
                ),
                const SizedBox(height: 14),
                Center(
                  child: Text(
                    displayName,
                    textAlign: TextAlign.center,
                    style: Theme.of(
                      context,
                    ).textTheme.headlineMedium?.copyWith(fontSize: 26),
                  ),
                ),
                if (mood != null) ...[
                  const SizedBox(height: 8),
                  Center(
                    child: TopicChip(
                      label: mood!,
                      icon: Icons.mood_rounded,
                      highlight: true,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                _PublicProfileStatsRow(
                  showLikes: visibility.showLikesStat,
                  showFriends: visibility.showFriendsStat,
                  showActive: visibility.showActiveStat,
                ),
                if (visibility.hasVisibleStats) const SizedBox(height: 18),
                _PublicSocialActions(displayName: displayName),
                const SizedBox(height: 12),
                _PublicProfileTimeline(displayName: displayName),
                if (visibility.showHappinessIndex) ...[
                  const SizedBox(height: 28),
                  const SectionHeader(title: 'Happiness index'),
                  const SizedBox(height: 12),
                  _PublicHappinessIndexCard(uid: uid),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PublicProfileVisibility {
  const _PublicProfileVisibility({
    this.showHappinessIndex = true,
    this.showLikesStat = true,
    this.showFriendsStat = true,
    this.showActiveStat = true,
  });

  final bool showHappinessIndex;
  final bool showLikesStat;
  final bool showFriendsStat;
  final bool showActiveStat;

  bool get hasVisibleStats =>
      showLikesStat || showFriendsStat || showActiveStat;

  factory _PublicProfileVisibility.fromData(Map<String, dynamic>? data) {
    final raw = data?['publicProfileVisibility'];
    if (raw is! Map) {
      return const _PublicProfileVisibility();
    }

    return _PublicProfileVisibility(
      showHappinessIndex: _boolValue(raw['showHappinessIndex']),
      showLikesStat: _boolValue(raw['showLikesStat']),
      showFriendsStat: _boolValue(raw['showFriendsStat']),
      showActiveStat: _boolValue(raw['showActiveStat']),
    );
  }

  static bool _boolValue(Object? value) {
    return value is bool ? value : true;
  }
}

class _PublicProfileStatsRow extends StatelessWidget {
  const _PublicProfileStatsRow({
    required this.showLikes,
    required this.showFriends,
    required this.showActive,
  });

  final bool showLikes;
  final bool showFriends;
  final bool showActive;

  @override
  Widget build(BuildContext context) {
    final pills = <Widget>[
      if (showLikes)
        const InfoPill(
          icon: Icons.favorite_rounded,
          label: 'Likes',
          value: '100',
        ),
      if (showFriends)
        const InfoPill(
          icon: Icons.person_rounded,
          label: 'Friends',
          value: '100',
        ),
      if (showActive)
        const InfoPill(
          icon: Icons.local_fire_department_rounded,
          label: 'Active',
          value: '11 days',
        ),
    ];

    if (pills.isEmpty) {
      return const SizedBox.shrink();
    }

    return Row(
      children: [
        for (var index = 0; index < pills.length; index++) ...[
          if (index > 0) const SizedBox(width: 10),
          Expanded(child: pills[index]),
        ],
      ],
    );
  }
}

class _PublicSocialActions extends StatelessWidget {
  const _PublicSocialActions({required this.displayName});

  final String displayName;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: () => _showPendingMessage(context, 'Follow'),
            icon: const Icon(Icons.person_add_alt_1_rounded),
            label: const Text('Follow'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _showPendingMessage(context, 'Message'),
            icon: const Icon(Icons.chat_bubble_outline_rounded),
            label: const Text('Message'),
          ),
        ),
      ],
    );
  }

  void _showPendingMessage(BuildContext context, String action) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$action for $displayName is coming soon.')),
    );
  }
}

enum _PublicProfileTimelineTab { posts, likes }

class _PublicProfileTimeline extends StatefulWidget {
  const _PublicProfileTimeline({required this.displayName});

  final String displayName;

  @override
  State<_PublicProfileTimeline> createState() => _PublicProfileTimelineState();
}

class _PublicProfileTimelineState extends State<_PublicProfileTimeline> {
  _PublicProfileTimelineTab _selectedTab = _PublicProfileTimelineTab.posts;

  @override
  Widget build(BuildContext context) {
    final isPostsSelected = _selectedTab == _PublicProfileTimelineTab.posts;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _TimelineButton(
                label: 'Posts',
                icon: Icons.article_outlined,
                selected: isPostsSelected,
                onTap: () {
                  setState(() {
                    _selectedTab = _PublicProfileTimelineTab.posts;
                  });
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _TimelineButton(
                label: 'Likes',
                icon: Icons.favorite_border_rounded,
                selected: !isPostsSelected,
                onTap: () {
                  setState(() {
                    _selectedTab = _PublicProfileTimelineTab.likes;
                  });
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SoftCard(
          child: Text(
            isPostsSelected
                ? 'Public posts and replies from ${widget.displayName} will appear here when the hall feed is connected to profile timelines.'
                : 'Posts ${widget.displayName} liked will appear here when public liked-post timelines are connected.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }
}

class _TimelineButton extends StatelessWidget {
  const _TimelineButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (selected) {
      return FilledButton.icon(
        onPressed: onTap,
        icon: Icon(icon),
        label: Text(label),
      );
    }

    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon),
      label: Text(label),
    );
  }
}

class _PublicHappinessIndexCard extends StatelessWidget {
  const _PublicHappinessIndexCard({this.uid});

  final String? uid;

  @override
  Widget build(BuildContext context) {
    final uid = this.uid;
    if (uid == null) {
      return _card(
        context,
        WeeklyMoodSummary.fromEntries(const {}, today: DateTime.now()),
      );
    }

    return StreamBuilder<Map<String, MoodEntry>>(
      stream: MoodRepository(uid).watchRecent(),
      builder: (context, snapshot) {
        return _card(
          context,
          WeeklyMoodSummary.fromEntries(
            snapshot.data ?? const {},
            today: DateTime.now(),
          ),
        );
      },
    );
  }

  Widget _card(BuildContext context, WeeklyMoodSummary summary) {
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Weekly happiness index',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 14),
          MoodBarChart(
            values: summary.values,
            labels: summary.labels,
            emoji: summary.emoji,
          ),
          const SizedBox(height: 18),
          Text(
            summary.hasData
                ? 'Average happiness level: ${summary.averagePercent}%'
                : 'No mood check-ins yet this week',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
        ],
      ),
    );
  }
}
