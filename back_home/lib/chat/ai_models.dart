import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Icons are stored as stable string keys rather than raw code points so the
/// `IconData` values stay const — dynamic `IconData` breaks Flutter's icon
/// tree-shaking on release builds.
const Map<String, IconData> kAiCharacterIcons = {
  'basketball': Icons.sports_basketball_rounded,
  'skateboard': Icons.skateboarding_rounded,
  'code': Icons.code_rounded,
  'camping': Icons.forest_rounded,
  'swimming': Icons.pool_rounded,
  'baseball': Icons.sports_baseball_rounded,
  'music': Icons.music_note_rounded,
  'tennis': Icons.sports_tennis_rounded,
  'soccer': Icons.sports_soccer_rounded,
  'volleyball': Icons.sports_volleyball_rounded,
  'book': Icons.menu_book_rounded,
  'dance': Icons.music_note_rounded,
  'camera': Icons.camera_alt_rounded,
  'plants': Icons.local_florist_rounded,
  'palette': Icons.palette_rounded,
  'hiking': Icons.hiking_rounded,
  'guitar': Icons.queue_music_rounded,
  'heart': Icons.favorite_rounded,
};

IconData aiIconForKey(String key) {
  return kAiCharacterIcons[key] ?? Icons.favorite_rounded;
}

class AiCharacter {
  const AiCharacter({
    required this.id,
    required this.name,
    required this.personality,
    required this.preview,
    required this.colorValue,
    required this.iconCodePoint,
    this.isCustom = false,
    this.avatarUrl,
  });

  final String id;
  final String name;
  final String personality;
  final String preview;
  final int colorValue;

  /// Stored icon key. Named for the field it maps to in Firestore.
  final String iconCodePoint;

  final bool isCustom;

  /// Firebase Storage download URL, set once the user picks a picture.
  final String? avatarUrl;

  static const String customIconCodePoint = 'heart';
  static const int customColorValue = 0xFFF6C7C7;

  Color get tint => Color(colorValue);
  IconData get icon => aiIconForKey(iconCodePoint);

  /// Stable 9-digit display id, matching the look of the human user ids shown
  /// elsewhere in the chat UI.
  String get publicId {
    var hash = 0;
    for (final unit in id.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return (100000000 + (hash % 900000000)).toString();
  }

  /// Increment this whenever the built-in catalog changes. It lets existing
  /// accounts receive a one-time catalog update without restoring presets a
  /// person intentionally removed later.
  static const int presetCatalogVersion = 2;

  static const List<String> legacyPresetIds = ['ari', 'noah', 'mentor-lin'];

  static const List<AiCharacter> presets = [
    AiCharacter(
      id: 'ethan-miller',
      name: 'Ethan Miller',
      personality:
          'Outgoing and competitive. He loves playing basketball, video '
          'games, and taking photos, and he is usually the one making jokes '
          'when he hangs out with friends.',
      preview: 'Always up for a game, a joke, or a good photo.',
      colorValue: 0xFFF2C6A8,
      iconCodePoint: 'basketball',
    ),
    AiCharacter(
      id: 'noah-carter',
      name: 'Noah Carter',
      personality:
          'Laid-back and independent. He spends a lot of his free time '
          'skateboarding, listening to rock music, and drawing, and he likes '
          'doing things his own way.',
      preview: 'Laid-back, independent, and always doing things his way.',
      colorValue: 0xFFDDE8DD,
      iconCodePoint: 'skateboard',
    ),
    AiCharacter(
      id: 'liam-anderson',
      name: 'Liam Anderson',
      personality:
          'Quiet, curious, and thoughtful. He enjoys programming, building '
          'things with LEGO, and playing soccer, and he can spend hours '
          'focused on something that interests him.',
      preview: 'Curious, thoughtful, and ready to dig into an idea.',
      colorValue: 0xFFFFE3B4,
      iconCodePoint: 'code',
    ),
    AiCharacter(
      id: 'mason-williams',
      name: 'Mason Williams',
      personality:
          'Patient and easygoing, although he can be a little shy around new '
          'people. He enjoys fishing, camping, and playing video games, '
          'especially with his friends.',
      preview: 'Easygoing company for a quiet conversation.',
      colorValue: 0xFFEAD3BB,
      iconCodePoint: 'camping',
    ),
    AiCharacter(
      id: 'caleb-johnson',
      name: 'Caleb Johnson',
      personality:
          'Confident, funny, and social. He loves playing basketball, '
          'watching movies, and practicing guitar, and he enjoys meeting and '
          'talking with new people.',
      preview: 'Funny, social, and ready to talk about anything.',
      colorValue: 0xFFF6C7C7,
      iconCodePoint: 'basketball',
    ),
    AiCharacter(
      id: 'ryan-thompson',
      name: 'Ryan Thompson',
      personality:
          'Curious, responsible, and serious about the things he cares '
          'about. He enjoys swimming, reading, and doing science experiments, '
          'and he likes learning how things work.',
      preview: 'Curious about how things work and why.',
      colorValue: 0xFFDCE8F5,
      iconCodePoint: 'swimming',
    ),
    AiCharacter(
      id: 'tyler-brown',
      name: 'Tyler Brown',
      personality:
          'Energetic, talkative, and always looking for something fun to do. '
          'He loves baseball, arcade games, and cars, and he has a hard time '
          'sitting still for too long.',
      preview: 'High energy and always looking for the next fun thing.',
      colorValue: 0xFFFFE3B4,
      iconCodePoint: 'baseball',
    ),
    AiCharacter(
      id: 'alex-davis',
      name: 'Alex Davis',
      personality:
          'Creative, observant, and a little reserved. He enjoys photography, '
          'riding his bike, and experimenting with music production, and he '
          'tends to notice small details that other people overlook.',
      preview: 'Creative, observant, and tuned in to the details.',
      colorValue: 0xFFD9E8E1,
      iconCodePoint: 'music',
    ),
    AiCharacter(
      id: 'jake-wilson',
      name: 'Jake Wilson',
      personality:
          'Friendly, easygoing, and always willing to help his friends. He '
          'enjoys tennis, anime, and cooking, although he can be a little '
          'forgetful sometimes.',
      preview: 'Friendly, helpful, and easy to talk to.',
      colorValue: 0xFFF2C6A8,
      iconCodePoint: 'tennis',
    ),
    AiCharacter(
      id: 'daniel-martinez',
      name: 'Daniel Martinez',
      personality:
          'Calm, independent, and open-minded. He enjoys playing soccer, '
          'making street art, and learning about history, and he is always '
          'curious about new experiences.',
      preview: 'Calm, open-minded, and curious about new experiences.',
      colorValue: 0xFFDDE8DD,
      iconCodePoint: 'soccer',
    ),
    AiCharacter(
      id: 'emma-wilson',
      name: 'Emma Wilson',
      personality:
          'Friendly, energetic, and easy to talk to. She enjoys playing '
          'volleyball, listening to pop music, and taking pictures with her '
          'friends, and she loves trying new things.',
      preview: 'Friendly energy and always open to trying something new.',
      colorValue: 0xFFF6C7C7,
      iconCodePoint: 'volleyball',
    ),
    AiCharacter(
      id: 'olivia-parker',
      name: 'Olivia Parker',
      personality:
          'Calm, thoughtful, and a little introverted. She enjoys reading '
          'novels, drawing, and listening to music, and she often prefers '
          'spending time in smaller groups.',
      preview: 'Thoughtful conversation for a quieter moment.',
      colorValue: 0xFFDCE8F5,
      iconCodePoint: 'book',
    ),
    AiCharacter(
      id: 'sophia-martinez',
      name: 'Sophia Martinez',
      personality:
          'Confident, outgoing, and very social. She loves dancing, watching '
          'movies, and going shopping with her friends, and she is usually '
          'the person who organizes group activities.',
      preview: 'Social, confident, and ready to get everyone together.',
      colorValue: 0xFFEAD3BB,
      iconCodePoint: 'dance',
    ),
    AiCharacter(
      id: 'ava-thompson',
      name: 'Ava Thompson',
      personality:
          'Curious, creative, and independent. She enjoys photography, '
          'baking, and learning about different cultures, and she likes '
          'having projects that let her express herself.',
      preview: 'Creative ideas, projects, and a fresh perspective.',
      colorValue: 0xFFFFE3B4,
      iconCodePoint: 'camera',
    ),
    AiCharacter(
      id: 'mia-anderson',
      name: 'Mia Anderson',
      personality:
          'Cheerful, caring, and sometimes a little shy around new people. '
          'She enjoys playing tennis, watching anime, and taking care of '
          'plants, and she is very supportive of her friends.',
      preview: 'A caring, supportive friend when you need one.',
      colorValue: 0xFFD9E8E1,
      iconCodePoint: 'plants',
    ),
    AiCharacter(
      id: 'chloe-johnson',
      name: 'Chloe Johnson',
      personality:
          'Funny, confident, and competitive. She enjoys playing basketball, '
          'video games, and listening to hip-hop, and she loves turning '
          'almost anything into a friendly competition.',
      preview: 'Funny, confident, and up for a friendly challenge.',
      colorValue: 0xFFF2C6A8,
      iconCodePoint: 'basketball',
    ),
    AiCharacter(
      id: 'isabella-brown',
      name: 'Isabella Brown',
      personality:
          'Artistic, patient, and observant. She enjoys painting, playing '
          'the piano, and visiting museums, and she often spends a lot of '
          'time working on small creative details.',
      preview: 'Patient, artistic, and attentive to the small details.',
      colorValue: 0xFFDCE8F5,
      iconCodePoint: 'palette',
    ),
    AiCharacter(
      id: 'grace-miller',
      name: 'Grace Miller',
      personality:
          'Kind, organized, and responsible. She enjoys reading, swimming, '
          'and volunteering at school events, and she usually likes having a '
          'clear plan before doing something.',
      preview: 'Kind, organized support for making a clear plan.',
      colorValue: 0xFFDDE8DD,
      iconCodePoint: 'swimming',
    ),
    AiCharacter(
      id: 'lily-davis',
      name: 'Lily Davis',
      personality:
          'Adventurous, talkative, and optimistic. She loves hiking, '
          'traveling, trying different foods, and hanging out with friends, '
          'and she rarely turns down an opportunity to try something new.',
      preview: 'Optimistic, adventurous, and ready to try something new.',
      colorValue: 0xFFFFE3B4,
      iconCodePoint: 'hiking',
    ),
    AiCharacter(
      id: 'hannah-carter',
      name: 'Hannah Carter',
      personality:
          'Quiet, witty, and independent. She enjoys playing guitar, '
          'watching science-fiction movies, and coding, and although she '
          'does not always talk a lot, she has a strong sense of humor.',
      preview: 'Quietly witty, independent, and full of sharp ideas.',
      colorValue: 0xFFEAD3BB,
      iconCodePoint: 'guitar',
    ),
  ];

  factory AiCharacter.fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    return AiCharacter(
      id: doc.id,
      name: _readString(data['name']) ?? 'Companion',
      personality: _readString(data['personality']) ?? 'A warm, steady friend',
      preview: _readString(data['preview']) ?? 'Tap to start a conversation',
      colorValue: data['colorValue'] is int
          ? data['colorValue'] as int
          : customColorValue,
      iconCodePoint: _readString(data['iconKey']) ?? customIconCodePoint,
      isCustom: data['isCustom'] == true,
      avatarUrl: _readString(data['avatarUrl']),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'personality': personality,
      'preview': preview,
      'colorValue': colorValue,
      'iconKey': iconCodePoint,
      'isCustom': isCustom,
    };
  }

  bool matches(String query) {
    if (query.isEmpty) {
      return true;
    }
    return name.toLowerCase().contains(query) ||
        personality.toLowerCase().contains(query) ||
        publicId.contains(query);
  }

  static String? _readString(Object? value) {
    if (value is! String || value.trim().isEmpty) {
      return null;
    }
    return value.trim();
  }
}

class AiMessage {
  const AiMessage({
    required this.id,
    required this.isUser,
    required this.text,
    this.createdAt,
    this.isPending = false,
  });

  final String id;
  final bool isUser;
  final String text;
  final DateTime? createdAt;

  /// True for the local "Thinking..." placeholder shown while the callable is
  /// in flight. Pending messages never exist in Firestore.
  final bool isPending;

  const AiMessage.pending()
    : id = '__pending__',
      isUser = false,
      text = 'Thinking...',
      createdAt = null,
      isPending = true;

  factory AiMessage.fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final text = data['text'];
    return AiMessage(
      id: doc.id,
      isUser: data['role'] != 'assistant',
      text: text is String ? text.trim() : '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}

class TutorSession {
  const TutorSession({
    required this.id,
    required this.title,
    required this.subtitle,
    this.updatedAt,
  });

  final String id;
  final String title;
  final String subtitle;
  final DateTime? updatedAt;

  factory TutorSession.fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final title = data['title'];
    final subtitle = data['subtitle'];
    return TutorSession(
      id: doc.id,
      title: title is String && title.trim().isNotEmpty
          ? title.trim()
          : 'New question',
      subtitle: subtitle is String && subtitle.trim().isNotEmpty
          ? subtitle.trim()
          : 'Ask anything you want help thinking through',
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  bool matches(String query) {
    if (query.isEmpty) {
      return true;
    }
    return title.toLowerCase().contains(query) ||
        subtitle.toLowerCase().contains(query);
  }
}

class AiChatPreview {
  const AiChatPreview({required this.lastMessage, this.updatedAt});

  final String lastMessage;
  final DateTime? updatedAt;
}
