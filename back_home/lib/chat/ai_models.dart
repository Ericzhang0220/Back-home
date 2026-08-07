import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Icons are stored as stable string keys rather than raw code points so the
/// `IconData` values stay const — dynamic `IconData` breaks Flutter's icon
/// tree-shaking on release builds.
const Map<String, IconData> kAiCharacterIcons = {
  'sparkle': Icons.auto_awesome_rounded,
  'psychology': Icons.psychology_alt_rounded,
  'school': Icons.school_rounded,
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

  static const List<AiCharacter> presets = [
    AiCharacter(
      id: 'ari',
      name: 'Ari',
      personality:
          'A gentle nightly companion. Calm, unhurried, and good at winding '
          'the day down without minimising what happened in it.',
      preview: 'Want music first, or a quiet unpacking of the day?',
      colorValue: 0xFFF2C6A8,
      iconCodePoint: 'sparkle',
    ),
    AiCharacter(
      id: 'noah',
      name: 'Noah',
      personality:
          'A warm routine coach. Practical and encouraging, focused on small '
          'repeatable habits rather than sweeping life overhauls.',
      preview: 'I saved a calmer plan for getting through tonight.',
      colorValue: 0xFFDDE8DD,
      iconCodePoint: 'psychology',
    ),
    AiCharacter(
      id: 'mentor-lin',
      name: 'Mentor Lin',
      personality:
          'A practical mentor. Direct and organised, good at breaking big '
          'vague pressure into a short ordered list of concrete tasks.',
      preview: 'Let us turn that stress into three smaller tasks.',
      colorValue: 0xFFFFE3B4,
      iconCodePoint: 'school',
    ),
  ];

  factory AiCharacter.fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
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
