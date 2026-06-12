import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../widgets/app_ui.dart';

enum _ChatPage { ai, human, tutor }

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _aiSearchController = TextEditingController();
  final _humanSearchController = TextEditingController();
  final _tutorSearchController = TextEditingController();
  final _messageController = TextEditingController();
  final _imagePicker = ImagePicker();

  _ChatPage _selectedPage = _ChatPage.ai;
  int _selectedTutorSession = 0;
  int _nextGeneratedUserId = 500000000;

  final List<_AiCharacter> _aiCharacters = [
    const _AiCharacter(
      userId: '128406731',
      name: 'Ari',
      personality: 'Gentle nightly companion',
      preview: 'Want music first, or a quiet unpacking of the day?',
      tint: Color(0xFFF2C6A8),
      icon: Icons.auto_awesome_rounded,
    ),
    const _AiCharacter(
      userId: '273914608',
      name: 'Noah',
      personality: 'Warm routine coach',
      preview: 'I saved a calmer plan for getting through tonight.',
      tint: Color(0xFFDDE8DD),
      icon: Icons.psychology_alt_rounded,
    ),
    const _AiCharacter(
      userId: '349805172',
      name: 'Mentor Lin',
      personality: 'Practical mentor',
      preview: 'Let us turn that stress into three smaller tasks.',
      tint: Color(0xFFFFE3B4),
      icon: Icons.school_rounded,
    ),
  ];

  final List<_HumanContact> _humanContacts = [
    _HumanContact(
      userId: '482015739',
      name: 'Maya',
      handle: '@maya-room',
      preview: 'Your room setup looks calmer already.',
      time: '12:04 PM',
      tint: Color(0xFFEAD3BB),
      unreadCount: 2,
    ),
    _HumanContact(
      userId: '615938204',
      name: 'Jordan',
      handle: '@jordan',
      preview: 'I can join the study timer after dinner.',
      time: '10:35 AM',
      tint: Color(0xFFDDE8DD),
    ),
    _HumanContact(
      userId: '790462318',
      name: 'Sam',
      handle: '@sam-care',
      preview: 'Try the softer lamp from the shop.',
      time: 'Yesterday',
      tint: Color(0xFFF4D7C5),
    ),
    _HumanContact(
      userId: '904136527',
      name: 'Community help',
      handle: 'Back Home users',
      preview: 'A new bottle reply is waiting for you.',
      time: 'Mon',
      tint: Color(0xFFFFDDAF),
      unreadCount: 1,
    ),
  ];

  final List<_TutorSession> _tutorSessions = [
    _TutorSession(
      title: 'Weekly reset',
      subtitle: 'Breaking Sunday prep into smaller pieces',
      messages: const [
        _TutorMessage(
          isUser: false,
          text: 'What would make this week feel easier by just ten percent?',
        ),
        _TutorMessage(
          isUser: true,
          text: 'I need help planning school work without getting overwhelmed.',
        ),
        _TutorMessage(
          isUser: false,
          text:
              'Start with the closest deadline, then choose one task that takes under 20 minutes.',
        ),
      ],
    ),
    _TutorSession(
      title: 'Room focus',
      subtitle: 'Choosing a calm setup for homework',
      messages: const [
        _TutorMessage(
          isUser: false,
          text: 'Tell me what usually distracts you when you study.',
        ),
      ],
    ),
    _TutorSession(
      title: 'Sleep question',
      subtitle: 'A shorter routine for late nights',
      messages: const [
        _TutorMessage(
          isUser: false,
          text: 'We can make the routine tiny: water, lights, one note, bed.',
        ),
      ],
    ),
  ];

  @override
  void dispose() {
    _aiSearchController.dispose();
    _humanSearchController.dispose();
    _tutorSearchController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.cream.withValues(alpha: 0.88),
      child: Column(
        children: [
          _ChatHeader(
            selectedPage: _selectedPage,
            onAddPressed: _handleAddPressed,
          ),
          _TopTabs(
            selectedPage: _selectedPage,
            onChanged: (page) {
              setState(() {
                _selectedPage = page;
              });
            },
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: switch (_selectedPage) {
                _ChatPage.ai => _AiContactsPage(
                  key: const ValueKey(_ChatPage.ai),
                  searchController: _aiSearchController,
                  characters: _filteredAiCharacters,
                  onSearchChanged: (_) => setState(() {}),
                  onPickAvatar: _pickAiAvatar,
                ),
                _ChatPage.human => _HumanContactsPage(
                  key: const ValueKey(_ChatPage.human),
                  searchController: _humanSearchController,
                  contacts: _filteredHumanContacts,
                  onSearchChanged: (_) => setState(() {}),
                ),
                _ChatPage.tutor => _TutorChatPage(
                  key: const ValueKey(_ChatPage.tutor),
                  searchController: _tutorSearchController,
                  messageController: _messageController,
                  sessions: _filteredTutorSessions,
                  selectedSession: _selectedVisibleTutorSession,
                  onSearchChanged: (_) => setState(() {}),
                  onSessionSelected: _selectTutorSession,
                  onSendMessage: _sendTutorMessage,
                ),
              },
            ),
          ),
        ],
      ),
    );
  }

  List<_AiCharacter> get _filteredAiCharacters {
    final query = _aiSearchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      return _aiCharacters;
    }

    return _aiCharacters.where((character) {
      return character.name.toLowerCase().contains(query) ||
          character.userId.contains(query) ||
          character.personality.toLowerCase().contains(query);
    }).toList();
  }

  List<_HumanContact> get _filteredHumanContacts {
    final query = _humanSearchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      return _humanContacts;
    }

    return _humanContacts.where((contact) {
      return contact.name.toLowerCase().contains(query) ||
          contact.userId.contains(query) ||
          contact.handle.toLowerCase().contains(query) ||
          contact.preview.toLowerCase().contains(query);
    }).toList();
  }

  List<_TutorSession> get _filteredTutorSessions {
    final query = _tutorSearchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      return _tutorSessions;
    }

    return _tutorSessions.where((session) {
      return session.title.toLowerCase().contains(query) ||
          session.subtitle.toLowerCase().contains(query);
    }).toList();
  }

  _TutorSession get _selectedVisibleTutorSession {
    final filtered = _filteredTutorSessions;
    if (filtered.isEmpty) {
      return _tutorSessions[_selectedTutorSession];
    }
    final current = _tutorSessions[_selectedTutorSession];
    if (filtered.contains(current)) {
      return current;
    }
    return filtered.first;
  }

  void _handleAddPressed() {
    switch (_selectedPage) {
      case _ChatPage.ai:
        _showAddAiCharacterDialog();
      case _ChatPage.human:
        _showAddHumanContactDialog();
      case _ChatPage.tutor:
        _addTutorSession();
    }
  }

  Future<void> _showAddAiCharacterDialog() async {
    final nameController = TextEditingController();
    final personalityController = TextEditingController();
    final userId = _generateUserId();

    try {
      final character = await showDialog<_AiCharacter>(
        context: context,
        builder: (context) {
          return _AddCharacterDialog(
            userId: userId,
            nameController: nameController,
            personalityController: personalityController,
          );
        },
      );

      if (character == null || !mounted) {
        return;
      }

      setState(() {
        _aiCharacters.insert(0, character);
      });
    } finally {
      nameController.dispose();
      personalityController.dispose();
    }
  }

  Future<void> _showAddHumanContactDialog() async {
    final nameController = TextEditingController();
    final handleController = TextEditingController();
    final userId = _generateUserId();

    try {
      final contact = await showDialog<_HumanContact>(
        context: context,
        builder: (context) {
          return _AddHumanDialog(
            userId: userId,
            nameController: nameController,
            handleController: handleController,
          );
        },
      );

      if (contact == null || !mounted) {
        return;
      }

      setState(() {
        _humanContacts.insert(0, contact);
      });
    } finally {
      nameController.dispose();
      handleController.dispose();
    }
  }

  Future<void> _pickAiAvatar(_AiCharacter character) async {
    final image = await _imagePicker.pickImage(source: ImageSource.gallery);
    if (image == null || !mounted) {
      return;
    }

    final bytes = await image.readAsBytes();
    if (!mounted) {
      return;
    }

    final index = _aiCharacters.indexOf(character);
    if (index < 0) {
      return;
    }

    setState(() {
      _aiCharacters[index] = character.copyWith(avatarBytes: bytes);
    });
  }

  void _addTutorSession() {
    setState(() {
      final sessionNumber = _tutorSessions.length + 1;
      _tutorSessions.insert(
        0,
        _TutorSession(
          title: 'New question $sessionNumber',
          subtitle: 'Ask anything you want help thinking through',
          messages: const [
            _TutorMessage(
              isUser: false,
              text: 'What would you like to work through right now?',
            ),
          ],
        ),
      );
      _selectedTutorSession = 0;
      _selectedPage = _ChatPage.tutor;
      _tutorSearchController.clear();
    });
  }

  void _selectTutorSession(_TutorSession session) {
    final index = _tutorSessions.indexOf(session);
    if (index < 0) {
      return;
    }

    setState(() {
      _selectedTutorSession = index;
    });
  }

  void _sendTutorMessage() {
    final message = _messageController.text.trim();
    if (message.isEmpty) {
      return;
    }

    final session = _selectedVisibleTutorSession;
    final index = _tutorSessions.indexOf(session);
    if (index < 0) {
      return;
    }

    setState(() {
      _tutorSessions[index] = session.copyWith(
        subtitle: message,
        messages: [
          ...session.messages,
          _TutorMessage(isUser: true, text: message),
          const _TutorMessage(
            isUser: false,
            text:
                'Let us make that concrete. What is the first small step you can take in the next ten minutes?',
          ),
        ],
      );
      _selectedTutorSession = index;
      _messageController.clear();
    });
  }

  String _generateUserId() {
    final id = _nextGeneratedUserId;
    _nextGeneratedUserId += 1;
    return id.toString().padLeft(9, '0');
  }
}

class _ChatHeader extends StatelessWidget {
  const _ChatHeader({required this.selectedPage, required this.onAddPressed});

  final _ChatPage selectedPage;
  final VoidCallback onAddPressed;

  @override
  Widget build(BuildContext context) {
    final title = switch (selectedPage) {
      _ChatPage.ai => 'AI chats',
      _ChatPage.human => 'Human chats',
      _ChatPage.tutor => 'Tutor',
    };
    final addLabel = selectedPage == _ChatPage.tutor
        ? 'Start new tutor chat'
        : 'Add chat';

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      decoration: BoxDecoration(
        color: AppColors.card.withValues(alpha: 0.86),
        border: const Border(bottom: BorderSide(color: AppColors.stroke)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 44),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontSize: 20,
                color: AppColors.ink,
              ),
            ),
          ),
          Tooltip(
            message: addLabel,
            child: IconButton.filledTonal(
              onPressed: onAddPressed,
              icon: const Icon(Icons.add_rounded),
              color: AppColors.ink,
              style: IconButton.styleFrom(
                backgroundColor: Colors.white.withValues(alpha: 0.76),
                side: const BorderSide(color: AppColors.stroke),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopTabs extends StatelessWidget {
  const _TopTabs({required this.selectedPage, required this.onChanged});

  final _ChatPage selectedPage;
  final ValueChanged<_ChatPage> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.card.withValues(alpha: 0.62),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Row(
        children: [
          for (final page in _ChatPage.values) ...[
            Expanded(
              child: _TabButton(
                label: switch (page) {
                  _ChatPage.ai => 'AI',
                  _ChatPage.human => 'Human',
                  _ChatPage.tutor => 'Tutor',
                },
                icon: switch (page) {
                  _ChatPage.ai => Icons.auto_awesome_rounded,
                  _ChatPage.human => Icons.people_alt_rounded,
                  _ChatPage.tutor => Icons.school_rounded,
                },
                isSelected: selectedPage == page,
                onTap: () => onChanged(page),
              ),
            ),
            if (page != _ChatPage.values.last) const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected ? AppColors.clay : Colors.white.withValues(alpha: 0.7),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected ? AppColors.clay : AppColors.stroke,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 18,
                color: isSelected ? Colors.white : AppColors.muted,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isSelected ? Colors.white : AppColors.ink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.hintText,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: hintText,
        prefixIcon: const Icon(Icons.search_rounded, color: AppColors.muted),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.88),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

class _AiContactsPage extends StatelessWidget {
  const _AiContactsPage({
    super.key,
    required this.searchController,
    required this.characters,
    required this.onSearchChanged,
    required this.onPickAvatar,
  });

  final TextEditingController searchController;
  final List<_AiCharacter> characters;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<_AiCharacter> onPickAvatar;

  @override
  Widget build(BuildContext context) {
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 122),
      children: [
        _SearchField(
          controller: searchController,
          hintText: 'Search AI characters or ID',
          onChanged: onSearchChanged,
        ),
        const SizedBox(height: 12),
        _DeviceStatusBanner(
          icon: Icons.memory_rounded,
          text: 'Preset characters and custom personalities',
        ),
        const SizedBox(height: 8),
        for (final character in characters)
          _AiCharacterTile(character: character, onPickAvatar: onPickAvatar),
        if (characters.isEmpty)
          const _EmptySearchResult(text: 'No AI characters match this search.'),
      ],
    );
  }
}

class _HumanContactsPage extends StatelessWidget {
  const _HumanContactsPage({
    super.key,
    required this.searchController,
    required this.contacts,
    required this.onSearchChanged,
  });

  final TextEditingController searchController;
  final List<_HumanContact> contacts;
  final ValueChanged<String> onSearchChanged;

  @override
  Widget build(BuildContext context) {
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 122),
      children: [
        _SearchField(
          controller: searchController,
          hintText: 'Search app users or ID',
          onChanged: onSearchChanged,
        ),
        const SizedBox(height: 12),
        _DeviceStatusBanner(
          icon: Icons.phone_iphone_rounded,
          text: 'Regular chats with other Back Home users',
        ),
        const SizedBox(height: 8),
        for (final contact in contacts) _HumanContactTile(contact: contact),
        if (contacts.isEmpty)
          const _EmptySearchResult(text: 'No people match this search.'),
      ],
    );
  }
}

class _TutorChatPage extends StatelessWidget {
  const _TutorChatPage({
    super.key,
    required this.searchController,
    required this.messageController,
    required this.sessions,
    required this.selectedSession,
    required this.onSearchChanged,
    required this.onSessionSelected,
    required this.onSendMessage,
  });

  final TextEditingController searchController;
  final TextEditingController messageController;
  final List<_TutorSession> sessions;
  final _TutorSession selectedSession;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<_TutorSession> onSessionSelected;
  final VoidCallback onSendMessage;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 430;
        final sidebarWidth = compact ? 122.0 : 168.0;

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 122),
          child: Row(
            children: [
              SizedBox(
                width: sidebarWidth,
                child: Column(
                  children: [
                    _SearchField(
                      controller: searchController,
                      hintText: compact ? 'History' : 'Search history',
                      onChanged: onSearchChanged,
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.58),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: AppColors.stroke),
                        ),
                        child: ListView(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          children: [
                            for (final session in sessions)
                              _TutorHistoryTile(
                                session: session,
                                isSelected: session == selectedSession,
                                onTap: () => onSessionSelected(session),
                              ),
                            if (sessions.isEmpty)
                              const Padding(
                                padding: EdgeInsets.all(12),
                                child: Text(
                                  'No saved chats',
                                  style: TextStyle(
                                    color: AppColors.muted,
                                    fontSize: 12,
                                    height: 1.3,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _TutorConversation(
                  session: selectedSession,
                  messageController: messageController,
                  onSendMessage: onSendMessage,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DeviceStatusBanner extends StatelessWidget {
  const _DeviceStatusBanner({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.card.withValues(alpha: 0.72),
        border: const Border(bottom: BorderSide(color: AppColors.stroke)),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.muted, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.muted,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AiCharacterTile extends StatelessWidget {
  const _AiCharacterTile({required this.character, required this.onPickAvatar});

  final _AiCharacter character;
  final ValueChanged<_AiCharacter> onPickAvatar;

  @override
  Widget build(BuildContext context) {
    return _ChatRow(
      avatar: _EditableAvatar(character: character, onPickAvatar: onPickAvatar),
      title: character.name,
      subtitle: 'ID ${character.userId} • ${character.preview}',
      meta: character.personality,
      trailing: character.isCustom
          ? const Icon(Icons.image_outlined, color: AppColors.muted, size: 20)
          : const Icon(
              Icons.lock_outline_rounded,
              color: AppColors.muted,
              size: 18,
            ),
    );
  }
}

class _HumanContactTile extends StatelessWidget {
  const _HumanContactTile({required this.contact});

  final _HumanContact contact;

  @override
  Widget build(BuildContext context) {
    return _ChatRow(
      avatar: _AvatarBox(
        color: contact.tint,
        icon: Icons.person_rounded,
        badgeCount: contact.unreadCount,
      ),
      title: contact.name,
      subtitle: 'ID ${contact.userId} • ${contact.preview}',
      meta: contact.time,
      trailing: Text(
        contact.handle,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.right,
        style: const TextStyle(color: AppColors.muted, fontSize: 12),
      ),
    );
  }
}

class _ChatRow extends StatelessWidget {
  const _ChatRow({
    required this.avatar,
    required this.title,
    required this.subtitle,
    required this.meta,
    required this.trailing,
  });

  final Widget avatar;
  final String title;
  final String subtitle;
  final String meta;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      constraints: const BoxConstraints(minHeight: 82),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.stroke)),
      ),
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 12, 12, 12),
            child: avatar,
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontSize: 18,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          meta,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: const Color(0xFF9A8B83),
                            fontSize: 15,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 76,
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: trailing,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EditableAvatar extends StatelessWidget {
  const _EditableAvatar({required this.character, required this.onPickAvatar});

  final _AiCharacter character;
  final ValueChanged<_AiCharacter> onPickAvatar;

  @override
  Widget build(BuildContext context) {
    final avatar = _AvatarBox(
      color: character.tint,
      icon: character.icon,
      imageBytes: character.avatarBytes,
    );

    if (!character.isCustom) {
      return avatar;
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        avatar,
        Positioned(
          right: -4,
          bottom: -4,
          child: Tooltip(
            message: 'Add picture',
            child: InkWell(
              onTap: () => onPickAvatar(character),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                height: 24,
                width: 24,
                decoration: BoxDecoration(
                  color: AppColors.clay,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: const Icon(
                  Icons.add_a_photo_rounded,
                  color: Colors.white,
                  size: 13,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AvatarBox extends StatelessWidget {
  const _AvatarBox({
    required this.color,
    required this.icon,
    this.imageBytes,
    this.badgeCount = 0,
  });

  final Color color;
  final IconData icon;
  final Uint8List? imageBytes;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          height: 58,
          width: 58,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(14),
          ),
          child: imageBytes == null
              ? Icon(icon, color: AppColors.ink, size: 29)
              : Image.memory(imageBytes!, fit: BoxFit.cover),
        ),
        if (badgeCount > 0)
          Positioned(
            right: -5,
            top: -5,
            child: Container(
              height: 20,
              constraints: const BoxConstraints(minWidth: 20),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFE45757),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: Text(
                '$badgeCount',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _TutorHistoryTile extends StatelessWidget {
  const _TutorHistoryTile({
    required this.session,
    required this.isSelected,
    required this.onTap,
  });

  final _TutorSession session;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      child: Material(
        color: isSelected ? AppColors.blush : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.ink,
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  session.subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 11,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TutorConversation extends StatelessWidget {
  const _TutorConversation({
    required this.session,
    required this.messageController,
    required this.onSendMessage,
  });

  final _TutorSession session;
  final TextEditingController messageController;
  final VoidCallback onSendMessage;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.76),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.stroke),
      ),
      child: Column(
        children: [
          Container(
            height: 54,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.stroke)),
            ),
            child: Row(
              children: [
                const Icon(Icons.school_rounded, color: AppColors.clay),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    session.title,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: session.messages.length,
              itemBuilder: (context, index) {
                return _TutorBubble(message: session.messages[index]);
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: messageController,
                    minLines: 1,
                    maxLines: 3,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => onSendMessage(),
                    decoration: InputDecoration(
                      hintText: 'Ask the tutor',
                      filled: true,
                      fillColor: AppColors.cream,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: onSendMessage,
                  icon: const Icon(Icons.arrow_upward_rounded),
                  tooltip: 'Send',
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.clay,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TutorBubble extends StatelessWidget {
  const _TutorBubble({required this.message});

  final _TutorMessage message;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 230),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: message.isUser ? AppColors.blush : AppColors.cream,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.stroke),
        ),
        child: Text(
          message.text,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: AppColors.ink, fontSize: 13),
        ),
      ),
    );
  }
}

class _AddCharacterDialog extends StatelessWidget {
  const _AddCharacterDialog({
    required this.userId,
    required this.nameController,
    required this.personalityController,
  });

  final String userId;
  final TextEditingController nameController;
  final TextEditingController personalityController;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add AI character'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: nameController,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: personalityController,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Personality'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final name = nameController.text.trim();
            final personality = personalityController.text.trim();
            if (name.isEmpty || personality.isEmpty) {
              return;
            }

            Navigator.of(context).pop(
              _AiCharacter(
                userId: userId,
                name: name,
                personality: personality,
                preview: 'Custom companion ready to chat.',
                tint: AppColors.peach,
                icon: Icons.favorite_rounded,
                isCustom: true,
              ),
            );
          },
          child: const Text('Add'),
        ),
      ],
    );
  }
}

class _AddHumanDialog extends StatelessWidget {
  const _AddHumanDialog({
    required this.userId,
    required this.nameController,
    required this.handleController,
  });

  final String userId;
  final TextEditingController nameController;
  final TextEditingController handleController;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add human chat'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: nameController,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: handleController,
            decoration: const InputDecoration(labelText: 'Handle'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final name = nameController.text.trim();
            final handle = handleController.text.trim();
            if (name.isEmpty || handle.isEmpty) {
              return;
            }

            Navigator.of(context).pop(
              _HumanContact(
                userId: userId,
                name: name,
                handle: handle,
                preview: 'New conversation',
                time: 'Now',
                tint: AppColors.sage.withValues(alpha: 0.35),
              ),
            );
          },
          child: const Text('Add'),
        ),
      ],
    );
  }
}

class _EmptySearchResult extends StatelessWidget {
  const _EmptySearchResult({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Center(
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }
}

class _AiCharacter {
  const _AiCharacter({
    required this.userId,
    required this.name,
    required this.personality,
    required this.preview,
    required this.tint,
    required this.icon,
    this.isCustom = false,
    this.avatarBytes,
  });

  final String userId;
  final String name;
  final String personality;
  final String preview;
  final Color tint;
  final IconData icon;
  final bool isCustom;
  final Uint8List? avatarBytes;

  _AiCharacter copyWith({Uint8List? avatarBytes}) {
    return _AiCharacter(
      userId: userId,
      name: name,
      personality: personality,
      preview: preview,
      tint: tint,
      icon: icon,
      isCustom: isCustom,
      avatarBytes: avatarBytes ?? this.avatarBytes,
    );
  }
}

class _HumanContact {
  const _HumanContact({
    required this.userId,
    required this.name,
    required this.handle,
    required this.preview,
    required this.time,
    required this.tint,
    this.unreadCount = 0,
  });

  final String userId;
  final String name;
  final String handle;
  final String preview;
  final String time;
  final Color tint;
  final int unreadCount;
}

class _TutorSession {
  _TutorSession({
    required this.title,
    required this.subtitle,
    required this.messages,
  });

  final String title;
  final String subtitle;
  final List<_TutorMessage> messages;

  _TutorSession copyWith({String? subtitle, List<_TutorMessage>? messages}) {
    return _TutorSession(
      title: title,
      subtitle: subtitle ?? this.subtitle,
      messages: messages ?? this.messages,
    );
  }
}

class _TutorMessage {
  const _TutorMessage({required this.isUser, required this.text});

  final bool isUser;
  final String text;
}
