import 'dart:io';

import 'package:flutter/material.dart';

import '../chat/chat_background_store.dart';
import 'app_ui.dart';
import 'character_portrait.dart';

class ChatBackground extends StatelessWidget {
  const ChatBackground({
    super.key,
    required this.choice,
    this.photoUrl,
    this.portraitAsset,
  });
  final ChatBackgroundChoice choice;
  final String? photoUrl;
  final String? portraitAsset;

  @override
  Widget build(BuildContext context) {
    const fallback = AmbientBackground(showSideGlow: false);
    return switch (choice.mode) {
      ChatBackgroundMode.plain => fallback,
      ChatBackgroundMode.portrait => CharacterPortrait(
        photoUrl: photoUrl,
        assetPath: portraitAsset,
        assetAlignment: const Alignment(0, -0.75),
        fallback: fallback,
      ),
      ChatBackgroundMode.photo =>
        choice.photoPath == null
            ? fallback
            : Image.file(
                File(choice.photoPath!),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => fallback,
              ),
    };
  }
}

enum ChatBackgroundAction { portrait, choosePhoto }

Future<ChatBackgroundAction?> showChatBackgroundPicker(
  BuildContext context, {
  required ChatBackgroundMode selected,
  required bool isAi,
  required bool hasPortrait,
}) => showModalBottomSheet<ChatBackgroundAction>(
  context: context,
  backgroundColor: AppColors.cream,
  showDragHandle: true,
  builder: (context) => SafeArea(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            'Chat background',
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        if (hasPortrait)
          ListTile(
            leading: const Icon(Icons.person_outline_rounded),
            title: Text(isAi ? 'Character photo' : 'Contact photo'),
            trailing: selected == ChatBackgroundMode.portrait
                ? const Icon(Icons.check_rounded)
                : null,
            onTap: () =>
                Navigator.of(context).pop(ChatBackgroundAction.portrait),
          ),
        ListTile(
          leading: const Icon(Icons.photo_library_outlined),
          title: const Text('Choose from Photos'),
          trailing: selected == ChatBackgroundMode.photo
              ? const Icon(Icons.check_rounded)
              : null,
          onTap: () =>
              Navigator.of(context).pop(ChatBackgroundAction.choosePhoto),
        ),
        const SizedBox(height: 8),
      ],
    ),
  ),
);
