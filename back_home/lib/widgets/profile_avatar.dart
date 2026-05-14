import 'dart:io';

import 'package:flutter/material.dart';

import 'app_ui.dart';

class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({
    super.key,
    required this.displayName,
    this.photoUrl,
    this.localPhotoPath,
    this.radius = 28,
    this.onTap,
    this.showEditBadge = false,
    this.heroTag,
  });

  final String displayName;
  final String? photoUrl;
  final String? localPhotoPath;
  final double radius;
  final VoidCallback? onTap;
  final bool showEditBadge;
  final Object? heroTag;

  @override
  Widget build(BuildContext context) {
    final avatar = Stack(
      clipBehavior: Clip.none,
      children: [
        CircleAvatar(
          radius: radius,
          backgroundColor: AppColors.blush,
          foregroundImage: _imageProvider(),
          child: Text(
            _initial,
            style: TextStyle(
              color: AppColors.ink,
              fontSize: radius * 0.72,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (showEditBadge)
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              height: radius * 0.72,
              width: radius * 0.72,
              decoration: BoxDecoration(
                color: AppColors.clay,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: Icon(
                Icons.camera_alt_rounded,
                size: radius * 0.36,
                color: Colors.white,
              ),
            ),
          ),
      ],
    );

    final wrappedAvatar = heroTag == null
        ? avatar
        : Hero(tag: heroTag!, child: avatar);

    if (onTap == null) {
      return wrappedAvatar;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(padding: const EdgeInsets.all(2), child: wrappedAvatar),
      ),
    );
  }

  ImageProvider? _imageProvider() {
    final localPath = localPhotoPath?.trim();
    if (localPath != null && localPath.isNotEmpty) {
      final localFile = File(localPath);
      if (localFile.existsSync()) {
        return FileImage(localFile);
      }
    }

    final remoteUrl = photoUrl?.trim();
    if (remoteUrl != null && remoteUrl.isNotEmpty) {
      return NetworkImage(remoteUrl);
    }

    return null;
  }

  String get _initial {
    final trimmedName = displayName.trim();
    if (trimmedName.isEmpty) {
      return '?';
    }
    return trimmedName.characters.first.toUpperCase();
  }
}
