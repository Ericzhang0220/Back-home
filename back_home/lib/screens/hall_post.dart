class HallComment {
  const HallComment({
    required this.author,
    required this.message,
    required this.sentAt,
    this.isMe = false,
    this.authorUid,
    this.authorPhotoUrl,
  });

  final String author;
  final String message;
  final String sentAt;
  final bool isMe;
  final String? authorUid;
  final String? authorPhotoUrl;

  HallComment copyWith({
    String? author,
    String? message,
    String? sentAt,
    bool? isMe,
    String? authorUid,
    String? authorPhotoUrl,
  }) {
    return HallComment(
      author: author ?? this.author,
      message: message ?? this.message,
      sentAt: sentAt ?? this.sentAt,
      isMe: isMe ?? this.isMe,
      authorUid: authorUid ?? this.authorUid,
      authorPhotoUrl: authorPhotoUrl ?? this.authorPhotoUrl,
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
    this.thread = const [],
    this.canEdit = false,
    this.likedByMe = false,
    this.authorUid,
    this.authorPhotoUrl,
  });

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
}
