import 'package:flutter/material.dart';

import '../screens/hall_user_profile_screen.dart';
import '../widgets/swipe_back_page_route.dart';

void openHallProfile(
  BuildContext context, {
  required String displayName,
  String? uid,
  String? currentUid,
  String? photoUrl,
  String? mood,
  bool isMe = false,
  VoidCallback? onOwnProfileTap,
}) {
  final hasUid = uid != null && uid.trim().isNotEmpty;
  final isOwnProfile = hasUid ? uid == currentUid : isMe;
  if (isOwnProfile && onOwnProfileTap != null) {
    onOwnProfileTap();
    return;
  }

  Navigator.of(context).push<void>(
    SwipeBackPageRoute(
      builder: (_) => HallUserProfileScreen(
        displayName: displayName,
        uid: uid,
        photoUrl: photoUrl,
        mood: mood,
      ),
    ),
  );
}
