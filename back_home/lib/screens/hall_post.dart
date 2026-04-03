class HallPost {
  const HallPost({
    required this.author,
    required this.mood,
    required this.tag,
    required this.message,
    required this.likes,
    required this.comments,
    this.canEdit = false,
  });

  final String author;
  final String mood;
  final String tag;
  final String message;
  final int likes;
  final int comments;
  final bool canEdit;

  HallPost copyWith({
    String? author,
    String? mood,
    String? tag,
    String? message,
    int? likes,
    int? comments,
    bool? canEdit,
  }) {
    return HallPost(
      author: author ?? this.author,
      mood: mood ?? this.mood,
      tag: tag ?? this.tag,
      message: message ?? this.message,
      likes: likes ?? this.likes,
      comments: comments ?? this.comments,
      canEdit: canEdit ?? this.canEdit,
    );
  }
}
