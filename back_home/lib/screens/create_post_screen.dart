import 'package:flutter/material.dart';

import '../widgets/app_ui.dart';
import 'hall_post.dart';

class CreatePostScreen extends StatefulWidget {
  const CreatePostScreen({super.key, this.existingPost});

  final HallPost? existingPost;

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  static const List<String> _moods = [
    'Very happy',
    'Good',
    'Neutral',
    'Low',
    'Overwhelmed',
  ];

  static const List<String> _tags = [
    'Daily check-in',
    'Kind note',
    'Room update',
    'Small win',
    'Need support',
  ];

  late final TextEditingController _messageController;
  late final TextEditingController _tagController;
  late String _selectedMood;

  @override
  void initState() {
    super.initState();
    _messageController = TextEditingController(
      text: widget.existingPost?.message ?? '',
    );
    _tagController = TextEditingController(
      text: widget.existingPost?.tag ?? _tags.first,
    );
    _selectedMood = widget.existingPost?.mood ?? _moods[1];
  }

  @override
  void dispose() {
    _messageController.dispose();
    _tagController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existingPost != null;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          const AmbientBackground(),
          SafeArea(
            child: AppPage(
              title: '',
              subtitle: '',
              leading: BackButton(onPressed: () => Navigator.of(context).pop()),
              // trailing: IconButton.filledTonal(
              //   onPressed: () => Navigator.of(context).pop(),
              //   icon: const Icon(Icons.close_rounded),
              // ),
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(
                      isEditing ? 'Update your note' : 'Topic:',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _messageController,
                      maxLines: 7,
                      decoration: InputDecoration(
                        hintText:
                            'Write a small encouragement, room update, or what you wish someone had said to you today.',
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.8),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(22),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.all(16),
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: _submit,
                        child: Text(isEditing ? 'Save post' : 'Publish post'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _submit() {
    final message = _messageController.text.trim();
    final tag = _tagController.text.trim();

    if (message.isEmpty || tag.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add both a tag and a short message before posting.'),
        ),
      );
      return;
    }

    Navigator.of(context).pop(
      HallPost(
        author: 'You',
        mood: _selectedMood,
        tag: tag,
        message: message,
        likes: widget.existingPost?.likes ?? 0,
        comments: widget.existingPost?.comments ?? 0,
        canEdit: true,
      ),
    );
  }
}
