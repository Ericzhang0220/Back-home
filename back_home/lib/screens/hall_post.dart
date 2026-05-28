import 'package:cloud_firestore/cloud_firestore.dart';

class HallComment {
  const HallComment({
    required this.author,
    required this.message,
    required this.sentAt,
    this.isMe = false,
    this.authorUid,
    this.authorPhotoUrl,
    this.createdAtMillis,
  });

  final String author;
  final String message;
  final String sentAt;
  final bool isMe;
  final String? authorUid;
  final String? authorPhotoUrl;
  final int? createdAtMillis;

  HallComment copyWith({
    String? author,
    String? message,
    String? sentAt,
    bool? isMe,
    String? authorUid,
    String? authorPhotoUrl,
    int? createdAtMillis,
  }) {
    return HallComment(
      author: author ?? this.author,
      message: message ?? this.message,
      sentAt: sentAt ?? this.sentAt,
      isMe: isMe ?? this.isMe,
      authorUid: authorUid ?? this.authorUid,
      authorPhotoUrl: authorPhotoUrl ?? this.authorPhotoUrl,
      createdAtMillis: createdAtMillis ?? this.createdAtMillis,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'author': author,
      'message': message,
      'authorUid': authorUid,
      'authorPhotoUrl': authorPhotoUrl,
      'createdAtMillis': createdAtMillis,
    };
  }

  factory HallComment.fromMap(Map<String, dynamic> map, {String? currentUid}) {
    final authorUid = map['authorUid'] as String?;
    final createdAtMillis = (map['createdAtMillis'] as num?)?.toInt();
    return HallComment(
      author: (map['author'] as String?) ?? 'Someone',
      message: (map['message'] as String?) ?? '',
      sentAt: createdAtMillis != null
          ? hallRelativeTime(createdAtMillis)
          : (map['sentAt'] as String? ?? ''),
      isMe: authorUid != null && authorUid == currentUid,
      authorUid: authorUid,
      authorPhotoUrl: map['authorPhotoUrl'] as String?,
      createdAtMillis: createdAtMillis,
    );
  }
}

class HallPost {
  const HallPost({
    required this.author,
    required this.mood,
    required this.topic,
    required this.message,
    required this.likes,
    this.id,
    this.thread = const [],
    this.canEdit = false,
    this.likedByMe = false,
    this.authorUid,
    this.authorPhotoUrl,
  });

  final String? id;
  final String author;
  final String mood;
  final String topic;
  final String message;
  final int likes;
  final List<HallComment> thread;
  final bool canEdit;
  final bool likedByMe;
  final String? authorUid;
  final String? authorPhotoUrl;

  int get comments => thread.length;

  HallPost copyWith({
    String? id,
    String? author,
    String? mood,
    String? topic,
    String? message,
    int? likes,
    List<HallComment>? thread,
    bool? canEdit,
    bool? likedByMe,
    String? authorUid,
    String? authorPhotoUrl,
  }) {
    return HallPost(
      id: id ?? this.id,
      author: author ?? this.author,
      mood: mood ?? this.mood,
      topic: topic ?? this.topic,
      message: message ?? this.message,
      likes: likes ?? this.likes,
      thread: thread ?? this.thread,
      canEdit: canEdit ?? this.canEdit,
      likedByMe: likedByMe ?? this.likedByMe,
      authorUid: authorUid ?? this.authorUid,
      authorPhotoUrl: authorPhotoUrl ?? this.authorPhotoUrl,
    );
  }

  /// Content fields for a new document. Server-managed fields (`likedBy`,
  /// `createdAt`) are added by the caller at write time.
  Map<String, dynamic> toMap() {
    return {
      'author': author,
      'authorUid': authorUid,
      'authorPhotoUrl': authorPhotoUrl,
      'mood': mood,
      'topic': topic,
      'message': message,
      'likes': likes,
      'thread': thread.map((comment) => comment.toMap()).toList(),
    };
  }

  factory HallPost.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc, {
    String? currentUid,
  }) {
    final data = doc.data() ?? const {};
    final authorUid = data['authorUid'] as String?;
    final likedBy =
        (data['likedBy'] as List?)?.whereType<String>().toList() ??
        const <String>[];
    final threadRaw = (data['thread'] as List?) ?? const [];

    return HallPost(
      id: doc.id,
      author: (data['author'] as String?) ?? 'Someone',
      authorUid: authorUid,
      authorPhotoUrl: data['authorPhotoUrl'] as String?,
      mood: (data['mood'] as String?) ?? '',
      topic: (data['topic'] as String?) ?? '',
      message: (data['message'] as String?) ?? '',
      likes: (data['likes'] as num?)?.toInt() ?? 0,
      likedByMe: currentUid != null && likedBy.contains(currentUid),
      canEdit: authorUid != null && authorUid == currentUid,
      thread: threadRaw
          .whereType<Map>()
          .map(
            (raw) => HallComment.fromMap(
              Map<String, dynamic>.from(raw),
              currentUid: currentUid,
            ),
          )
          .toList(growable: false),
    );
  }
}

/// Short relative label (e.g. `Now`, `24m`, `2h 5m`, `3d`) from an epoch ms.
String hallRelativeTime(int createdAtMillis) {
  final nowMillis = DateTime.now().millisecondsSinceEpoch;
  final minutes = ((nowMillis - createdAtMillis) ~/ 60000).clamp(0, 1 << 31);
  if (minutes < 1) {
    return 'Now';
  }
  if (minutes < 60) {
    return '${minutes}m';
  }
  final hours = minutes ~/ 60;
  if (hours < 24) {
    final remainderMinutes = minutes % 60;
    return remainderMinutes == 0 ? '${hours}h' : '${hours}h ${remainderMinutes}m';
  }
  return '${hours ~/ 24}d';
}
