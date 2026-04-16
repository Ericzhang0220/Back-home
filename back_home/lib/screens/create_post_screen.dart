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

  late final TextEditingController _messageController;
  late final TextEditingController _topicController;
  late String _selectedMood;

  @override
  void initState() {
    super.initState();
    _messageController = TextEditingController(
      text: widget.existingPost?.message ?? '',
    );
    _topicController = TextEditingController(
      text: widget.existingPost?.topic ?? '',
    );
    _selectedMood = widget.existingPost?.mood ?? _moods[1];
  }

  @override
  void dispose() {
    _messageController.dispose();
    _topicController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existingPost != null;
    final mediaQuery = MediaQuery.of(context);
    final bottomInset = mediaQuery.viewInsets.bottom;
    final bottomPadding = mediaQuery.padding.bottom + bottomInset + 32;
    final topicTextStyle = Theme.of(context).textTheme.headlineMedium?.copyWith(
      color: const Color.fromARGB(255, 0, 0, 0),
      fontSize: 24,
    );
    final textFieldScrollPadding = EdgeInsets.fromLTRB(
      20,
      20,
      20,
      bottomInset + 120,
    );

    return Scaffold(
      backgroundColor: AppColors.cream,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          const AmbientBackground(),
          SafeArea(
            bottom: false,
            child: AppPage(
              title: '',
              subtitle: '',
              leading: BackButton(onPressed: () => Navigator.of(context).pop()),
              // trailing: IconButton.filledTonal(
              //   onPressed: () => Navigator.of(context).pop(),
              //   icon: const Icon(Icons.close_rounded),
              // ),
              physics: const ClampingScrollPhysics(),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
              padding: EdgeInsets.fromLTRB(20, 18, 20, bottomPadding),
              children: [
                Container(
                  width: MediaQuery.of(context).size.width,
                  height: 60,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Row(
                      children: [
                        Text('Topic:', style: topicTextStyle),
                        Expanded(
                          child: SizedBox(
                            height: 40,
                            child: Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _topicController,
                                    maxLength: 13,
                                    style: topicTextStyle,
                                    textAlignVertical: TextAlignVertical.center,
                                    scrollPadding: textFieldScrollPadding,
                                    textInputAction: TextInputAction.next,
                                    onTapOutside: (_) => _dismissKeyboard(),
                                    decoration: InputDecoration(
                                      hintText: 'Write a topic',
                                      hintStyle: topicTextStyle?.copyWith(
                                        color: const Color.fromARGB(
                                          255,
                                          141,
                                          132,
                                          132,
                                        ),
                                        fontSize: 20,
                                      ),
                                      border: InputBorder.none,
                                      counterText: '',
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 11.5,
                                          ),
                                    ),
                                  ),
                                ),
                                ValueListenableBuilder<TextEditingValue>(
                                  valueListenable: _topicController,
                                  builder: (context, value, _) {
                                    return Padding(
                                      padding: const EdgeInsets.only(right: 8),
                                      child: Text(
                                        '${value.text.characters.length}/13',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(color: AppColors.muted),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: MediaQuery.of(context).size.height * 0.60,
                      child: TextField(
                        controller: _messageController,
                        maxLines: 70,
                        scrollPadding: textFieldScrollPadding,
                        textInputAction: TextInputAction.done,
                        onTapOutside: (_) => _dismissKeyboard(),
                        decoration: InputDecoration(
                          hintText:
                              'Try to write something interesting today..',
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.8),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(22),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.all(16),
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 28),
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

  void _dismissKeyboard() {
    final focusScope = FocusScope.of(context);
    if (!focusScope.hasPrimaryFocus && focusScope.focusedChild != null) {
      focusScope.unfocus();
    }
  }

  void _submit() {
    final message = _messageController.text.trim();
    final topic = _topicController.text.trim();

    if (message.isEmpty || topic.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add both a topic and a short message before posting.'),
        ),
      );
      return;
    }

    Navigator.of(context).pop(
      HallPost(
        author: 'You',
        mood: _selectedMood,
        topic: topic,
        message: message,
        likes: widget.existingPost?.likes ?? 0,
        thread: widget.existingPost?.thread ?? const [],
        canEdit: true,
        likedByMe: widget.existingPost?.likedByMe ?? false,
      ),
    );
  }
}
