import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

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
  });

  final String displayName;
  final String? uid;
  final String? photoUrl;
  final String? mood;

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
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: const [
                    SizedBox(
                      width: 96,
                      child: InfoPill(
                        icon: Icons.favorite_rounded,
                        label: 'Likes',
                        value: '100',
                      ),
                    ),
                    SizedBox(
                      width: 96,
                      child: InfoPill(
                        icon: Icons.person_rounded,
                        label: 'Friends',
                        value: '100',
                      ),
                    ),
                    SizedBox(
                      width: 96,
                      child: InfoPill(
                        icon: Icons.local_fire_department_rounded,
                        label: 'Active',
                        value: '11 days',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                const SectionHeader(title: 'Recent hall activity'),
                const SizedBox(height: 12),
                SoftCard(
                  child: Text(
                    'Public posts and replies from this user will appear here when the hall is connected to the backend feed.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
