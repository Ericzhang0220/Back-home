import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../auth/app_auth_controller.dart';
import '../chat/tutor_llm_client.dart';
import '../widgets/app_ui.dart';
import '../widgets/profile_avatar.dart';

enum _ChatPage { ai, human, tutor }

String _publicUserIdForUid(String uid) {
  var hash = 0;
  for (final unit in uid.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  return (100000000 + (hash % 900000000)).toString();
}

Color _tintForUid(String uid) {
  const colors = [
    AppColors.blush,
    AppColors.peach,
    Color(0xFFDDE8DD),
    Color(0xFFFFE3B4),
    Color(0xFFEAD3BB),
  ];
  if (uid.isEmpty) {
    return colors.first;
  }
  return colors[uid.codeUnitAt(0) % colors.length];
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.authController});

  final AppAuthController authController;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _aiSearchController = TextEditingController();
  final _humanSearchController = TextEditingController();
  final _tutorSearchController = TextEditingController();
  final _messageController = TextEditingController();
  final _imagePicker = ImagePicker();
  final _tutorClient = TutorLlmClient();

  _ChatPage _selectedPage = _ChatPage.ai;
  int _selectedTutorSession = 0;
  int _nextGeneratedUserId = 500000000;
  bool _isTutorSidebarOpen = true;

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
                  onOpenCharacter: _openAiConversation,
                ),
                _ChatPage.human => _HumanContactsPage(
                  key: const ValueKey(_ChatPage.human),
                  searchController: _humanSearchController,
                  onSearchChanged: (_) => setState(() {}),
                  currentUid: widget.authController.currentUser?.uid,
                  onOpenContact: _openHumanConversation,
                ),
                _ChatPage.tutor => _TutorChatPage(
                  key: const ValueKey(_ChatPage.tutor),
                  searchController: _tutorSearchController,
                  messageController: _messageController,
                  sessions: _filteredTutorSessions,
                  selectedSession: _selectedVisibleTutorSession,
                  isSidebarOpen: _isTutorSidebarOpen,
                  onSearchChanged: (_) => setState(() {}),
                  onSessionSelected: _selectTutorSession,
                  onSendMessage: _sendTutorMessage,
                  onSidebarChanged: (isOpen) {
                    setState(() {
                      _isTutorSidebarOpen = isOpen;
                    });
                  },
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
        _showHumanDirectoryHint();
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
    if (!_selectedVisibleTutorSession.isDirty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Ask something in this new chat before starting another.',
          ),
        ),
      );
      return;
    }

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
      _isTutorSidebarOpen = false;
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

  Future<void> _sendTutorMessage() async {
    final message = _messageController.text.trim();
    if (message.isEmpty) {
      return;
    }

    final session = _selectedVisibleTutorSession;
    final index = _tutorSessions.indexOf(session);
    if (index < 0) {
      return;
    }

    final requestMessages = [
      ...session.messages,
      _TutorMessage(isUser: true, text: message),
    ];

    setState(() {
      _tutorSessions[index] = session.copyWith(
        subtitle: message,
        messages: [
          ...requestMessages,
          const _TutorMessage(
            isUser: false,
            text: 'Thinking...',
            isPending: true,
          ),
        ],
      );
      _selectedTutorSession = index;
      _messageController.clear();
    });

    final reply = await _tutorClient.ask(
      sessionTitle: session.title,
      messages: requestMessages
          .map(
            (message) => TutorChatMessage(
              role: message.isUser ? 'user' : 'assistant',
              text: message.text,
            ),
          )
          .toList(),
    );

    if (!mounted) {
      return;
    }

    final latestIndex = _tutorSessions.indexWhere(
      (candidate) => candidate.title == session.title,
    );
    if (latestIndex < 0) {
      return;
    }

    final latestSession = _tutorSessions[latestIndex];
    final updatedMessages = [...latestSession.messages];
    final pendingIndex = updatedMessages.lastIndexWhere(
      (message) => message.isPending,
    );
    final replyText = reply.usedFallback
        ? '${reply.text}\n\nBackend: local fallback'
        : reply.text;
    if (pendingIndex >= 0) {
      updatedMessages[pendingIndex] = _TutorMessage(
        isUser: false,
        text: replyText,
      );
    } else {
      updatedMessages.add(_TutorMessage(isUser: false, text: replyText));
    }

    setState(() {
      _tutorSessions[latestIndex] = latestSession.copyWith(
        subtitle: message,
        messages: updatedMessages,
      );
      _selectedTutorSession = latestIndex;
    });
  }

  String _generateUserId() {
    final id = _nextGeneratedUserId;
    _nextGeneratedUserId += 1;
    return id.toString().padLeft(9, '0');
  }

  void _showHumanDirectoryHint() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Human chats come from Firebase users.')),
    );
  }

  Future<void> _openAiConversation(_AiCharacter character) async {
    final peer = _ChatPeer.ai(
      id: character.userId,
      displayName: character.name,
      subtitle: character.personality,
      photoUrl: null,
      tint: character.tint,
      icon: character.icon,
      avatarBytes: character.avatarBytes,
    );
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _DirectChatScreen(
          peer: peer,
          currentUid: widget.authController.currentUser?.uid,
        ),
      ),
    );
  }

  Future<void> _openHumanConversation(_HumanContact contact) async {
    final peer = _ChatPeer.human(
      id: contact.uid,
      displayName: contact.name,
      subtitle: contact.handle,
      publicUserId: contact.userId,
      photoUrl: contact.photoUrl,
      tint: contact.tint,
    );
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _DirectChatScreen(
          peer: peer,
          currentUid: widget.authController.currentUser?.uid,
        ),
      ),
    );
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
    required this.onOpenCharacter,
  });

  final TextEditingController searchController;
  final List<_AiCharacter> characters;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<_AiCharacter> onPickAvatar;
  final ValueChanged<_AiCharacter> onOpenCharacter;

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
          _AiCharacterTile(
            character: character,
            onPickAvatar: onPickAvatar,
            onOpen: () => onOpenCharacter(character),
          ),
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
    required this.onSearchChanged,
    required this.currentUid,
    required this.onOpenContact,
  });

  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final String? currentUid;
  final ValueChanged<_HumanContact> onOpenContact;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('users').snapshots(),
      builder: (context, snapshot) {
        final query = searchController.text.trim().toLowerCase();
        final contacts =
            snapshot.data?.docs
                .where((doc) => doc.id != currentUid)
                .map(_HumanContact.fromUserDoc)
                .where((contact) => contact.matches(query))
                .toList() ??
            <_HumanContact>[];
        contacts.sort((a, b) => a.name.compareTo(b.name));

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
              text: snapshot.hasError
                  ? 'Could not load Firebase users.'
                  : 'Regular chats with other Back Home users',
            ),
            const SizedBox(height: 8),
            if (snapshot.connectionState == ConnectionState.waiting)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 30),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              for (final contact in contacts)
                _HumanContactTile(
                  contact: contact,
                  onOpen: () => onOpenContact(contact),
                ),
              if (contacts.isEmpty)
                const _EmptySearchResult(text: 'No people match this search.'),
            ],
          ],
        );
      },
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
    required this.isSidebarOpen,
    required this.onSearchChanged,
    required this.onSessionSelected,
    required this.onSendMessage,
    required this.onSidebarChanged,
  });

  final TextEditingController searchController;
  final TextEditingController messageController;
  final List<_TutorSession> sessions;
  final _TutorSession selectedSession;
  final bool isSidebarOpen;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<_TutorSession> onSessionSelected;
  final VoidCallback onSendMessage;
  final ValueChanged<bool> onSidebarChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 430;
        final sidebarWidth = compact ? 122.0 : 168.0;

        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragEnd: (details) {
            final velocity = details.primaryVelocity ?? 0;
            if (velocity > 300) {
              onSidebarChanged(true);
            } else if (velocity < -300) {
              onSidebarChanged(false);
            }
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 122),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  width: isSidebarOpen ? sidebarWidth : 38,
                  child: isSidebarOpen
                      ? _TutorSidebar(
                          searchController: searchController,
                          sessions: sessions,
                          selectedSession: selectedSession,
                          compact: compact,
                          onSearchChanged: onSearchChanged,
                          onSessionSelected: onSessionSelected,
                          onCollapse: () => onSidebarChanged(false),
                        )
                      : _CollapsedTutorSidebar(
                          onExpand: () => onSidebarChanged(true),
                        ),
                ),
                SizedBox(width: isSidebarOpen ? 10 : 8),
                Expanded(
                  child: _TutorConversation(
                    session: selectedSession,
                    messageController: messageController,
                    onSendMessage: onSendMessage,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _TutorSidebar extends StatelessWidget {
  const _TutorSidebar({
    required this.searchController,
    required this.sessions,
    required this.selectedSession,
    required this.compact,
    required this.onSearchChanged,
    required this.onSessionSelected,
    required this.onCollapse,
  });

  final TextEditingController searchController;
  final List<_TutorSession> sessions;
  final _TutorSession selectedSession;
  final bool compact;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<_TutorSession> onSessionSelected;
  final VoidCallback onCollapse;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _SearchField(
                controller: searchController,
                hintText: compact ? 'History' : 'Search history',
                onChanged: onSearchChanged,
              ),
            ),
            const SizedBox(width: 6),
            IconButton(
              tooltip: 'Hide history',
              onPressed: onCollapse,
              icon: const Icon(Icons.chevron_left_rounded),
            ),
          ],
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
    );
  }
}

class _CollapsedTutorSidebar extends StatelessWidget {
  const _CollapsedTutorSidebar({required this.onExpand});

  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: Tooltip(
        message: 'Show history',
        child: IconButton.filledTonal(
          onPressed: onExpand,
          icon: const Icon(Icons.chevron_right_rounded),
          style: IconButton.styleFrom(
            backgroundColor: Colors.white.withValues(alpha: 0.78),
            foregroundColor: AppColors.ink,
            side: const BorderSide(color: AppColors.stroke),
          ),
        ),
      ),
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
  const _AiCharacterTile({
    required this.character,
    required this.onPickAvatar,
    required this.onOpen,
  });

  final _AiCharacter character;
  final ValueChanged<_AiCharacter> onPickAvatar;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return _ChatRow(
      onTap: onOpen,
      avatar: _EditableAvatar(character: character, onPickAvatar: onPickAvatar),
      title: character.name,
      subtitle: character.preview,
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
  const _HumanContactTile({required this.contact, required this.onOpen});

  final _HumanContact contact;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return _ChatRow(
      onTap: onOpen,
      avatar: _AvatarBox(
        color: contact.tint,
        icon: Icons.person_rounded,
        photoUrl: contact.photoUrl,
      ),
      title: contact.name,
      subtitle: contact.preview,
      meta: contact.handle,
      trailing: Text(
        'Profile',
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.right,
        style: const TextStyle(color: AppColors.muted, fontSize: 12),
      ),
    );
  }
}

class _ChatRow extends StatelessWidget {
  const _ChatRow({
    required this.onTap,
    required this.avatar,
    required this.title,
    required this.subtitle,
    required this.meta,
    required this.trailing,
  });

  final VoidCallback onTap;
  final Widget avatar;
  final String title;
  final String subtitle;
  final String meta;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 82),
          decoration: const BoxDecoration(
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
        ),
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
    this.photoUrl,
  });

  final Color color;
  final IconData icon;
  final Uint8List? imageBytes;
  final String? photoUrl;

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
          child: imageBytes != null
              ? Image.memory(imageBytes!, fit: BoxFit.cover)
              : (photoUrl != null && photoUrl!.isNotEmpty)
              ? Image.network(photoUrl!, fit: BoxFit.cover)
              : Icon(icon, color: AppColors.ink, size: 29),
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

class _DirectChatScreen extends StatefulWidget {
  const _DirectChatScreen({required this.peer, required this.currentUid});

  final _ChatPeer peer;
  final String? currentUid;

  @override
  State<_DirectChatScreen> createState() => _DirectChatScreenState();
}

class _DirectChatScreenState extends State<_DirectChatScreen> {
  final _controller = TextEditingController();
  late final List<_DirectMessage> _aiMessages = [
    _DirectMessage(
      isMine: false,
      text: widget.peer.isAi
          ? 'Hi, I am ${widget.peer.displayName}. What do you want to talk through?'
          : '',
      sentAt: DateTime.now(),
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: AppBar(
        backgroundColor: AppColors.card.withValues(alpha: 0.94),
        foregroundColor: AppColors.ink,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 0,
        title: Row(
          children: [
            _PeerAvatar(peer: widget.peer, size: 36),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                widget.peer.displayName,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Profile',
            onPressed: _showPeerProfile,
            icon: const Icon(Icons.info_outline_rounded),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(child: _buildMessages()),
            _MessageComposer(controller: _controller, onSend: _sendMessage),
          ],
        ),
      ),
    );
  }

  Widget _buildMessages() {
    if (widget.peer.isAi) {
      return _MessageList(messages: _aiMessages);
    }

    final currentUid = widget.currentUid;
    if (currentUid == null) {
      return const Center(child: Text('Sign in to start chatting.'));
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('chats')
          .doc(_chatIdFor(currentUid, widget.peer.id))
          .collection('messages')
          .orderBy('createdAt')
          .snapshots(),
      builder: (context, snapshot) {
        final messages =
            snapshot.data?.docs
                .map((doc) {
                  final data = doc.data();
                  return _DirectMessage(
                    isMine: data['senderUid'] == currentUid,
                    text: _stringValue(data['text']) ?? '',
                    sentAt: (data['createdAt'] as Timestamp?)?.toDate(),
                  );
                })
                .where((message) => message.text.isNotEmpty)
                .toList() ??
            <_DirectMessage>[];

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (messages.isEmpty) {
          return Center(
            child: Text(
              'Start a conversation with ${widget.peer.displayName}.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          );
        }

        return _MessageList(messages: messages);
      },
    );
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      return;
    }

    _controller.clear();

    if (widget.peer.isAi) {
      setState(() {
        _aiMessages.add(
          _DirectMessage(isMine: true, text: text, sentAt: DateTime.now()),
        );
        _aiMessages.add(
          _DirectMessage(
            isMine: false,
            text:
                'I hear you. Let us break that into one feeling, one fact, and one next step.',
            sentAt: DateTime.now(),
          ),
        );
      });
      return;
    }

    final currentUid = widget.currentUid;
    if (currentUid == null) {
      return;
    }

    final chatId = _chatIdFor(currentUid, widget.peer.id);
    final chatRef = FirebaseFirestore.instance.collection('chats').doc(chatId);
    await chatRef.set({
      'participantUids': [currentUid, widget.peer.id]..sort(),
      'updatedAt': FieldValue.serverTimestamp(),
      'lastMessage': text,
    }, SetOptions(merge: true));
    await chatRef.collection('messages').add({
      'senderUid': currentUid,
      'text': text,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  void _showPeerProfile() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.cream,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => _PeerProfileSheet(peer: widget.peer),
    );
  }

  static String _chatIdFor(String a, String b) {
    final ids = [a, b]..sort();
    return '${ids[0]}_${ids[1]}';
  }

  static String? _stringValue(Object? value) {
    if (value is! String || value.trim().isEmpty) {
      return null;
    }
    return value.trim();
  }
}

class _MessageList extends StatelessWidget {
  const _MessageList({required this.messages});

  final List<_DirectMessage> messages;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final message = messages[index];
        return Align(
          alignment: message.isMine
              ? Alignment.centerRight
              : Alignment.centerLeft,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 290),
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: message.isMine ? AppColors.blush : Colors.white,
              borderRadius: BorderRadius.circular(17),
              border: Border.all(color: AppColors.stroke),
            ),
            child: Text(message.text),
          ),
        );
      },
    );
  }
}

class _MessageComposer extends StatelessWidget {
  const _MessageComposer({required this.controller, required this.onSend});

  final TextEditingController controller;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(top: BorderSide(color: AppColors.stroke)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 3,
              onSubmitted: (_) => onSend(),
              decoration: InputDecoration(
                hintText: 'Message',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: onSend,
            icon: const Icon(Icons.arrow_upward_rounded),
            style: IconButton.styleFrom(
              backgroundColor: AppColors.clay,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _PeerProfileSheet extends StatelessWidget {
  const _PeerProfileSheet({required this.peer});

  final _ChatPeer peer;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 22, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _PeerAvatar(peer: peer, size: 74),
            const SizedBox(height: 12),
            Text(
              peer.displayName,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            Text(
              peer.subtitle,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 18),
            SoftCard(
              padding: const EdgeInsets.all(14),
              radius: 18,
              child: Row(
                children: [
                  const Icon(Icons.badge_outlined, color: AppColors.clay),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'User ID',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  Text(
                    peer.publicUserId,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PeerAvatar extends StatelessWidget {
  const _PeerAvatar({required this.peer, required this.size});

  final _ChatPeer peer;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (!peer.isAi) {
      return ProfileAvatar(
        displayName: peer.displayName,
        photoUrl: peer.photoUrl,
        radius: size / 2,
        heroTag: 'chat-peer-${peer.id}',
      );
    }

    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: peer.tint,
        borderRadius: BorderRadius.circular(size * 0.24),
      ),
      child: peer.avatarBytes != null
          ? Image.memory(peer.avatarBytes!, fit: BoxFit.cover)
          : Icon(peer.icon, color: AppColors.ink, size: size * 0.48),
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

class _ChatPeer {
  const _ChatPeer._({
    required this.id,
    required this.publicUserId,
    required this.displayName,
    required this.subtitle,
    required this.isAi,
    required this.tint,
    required this.icon,
    this.photoUrl,
    this.avatarBytes,
  });

  factory _ChatPeer.ai({
    required String id,
    required String displayName,
    required String subtitle,
    required Color tint,
    required IconData icon,
    Uint8List? avatarBytes,
    String? photoUrl,
  }) {
    return _ChatPeer._(
      id: id,
      publicUserId: id,
      displayName: displayName,
      subtitle: subtitle,
      isAi: true,
      tint: tint,
      icon: icon,
      photoUrl: photoUrl,
      avatarBytes: avatarBytes,
    );
  }

  factory _ChatPeer.human({
    required String id,
    required String publicUserId,
    required String displayName,
    required String subtitle,
    required Color tint,
    String? photoUrl,
  }) {
    return _ChatPeer._(
      id: id,
      publicUserId: publicUserId,
      displayName: displayName,
      subtitle: subtitle,
      isAi: false,
      tint: tint,
      icon: Icons.person_rounded,
      photoUrl: photoUrl,
    );
  }

  final String id;
  final String publicUserId;
  final String displayName;
  final String subtitle;
  final bool isAi;
  final Color tint;
  final IconData icon;
  final String? photoUrl;
  final Uint8List? avatarBytes;
}

class _DirectMessage {
  const _DirectMessage({
    required this.isMine,
    required this.text,
    required this.sentAt,
  });

  final bool isMine;
  final String text;
  final DateTime? sentAt;
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
    required this.uid,
    required this.userId,
    required this.name,
    required this.handle,
    required this.preview,
    required this.tint,
    this.photoUrl,
  });

  final String uid;
  final String userId;
  final String name;
  final String handle;
  final String preview;
  final Color tint;
  final String? photoUrl;

  factory _HumanContact.fromUserDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final displayName = _readString(data['displayName']);
    final email = _readString(data['email']);
    final phone = _readString(data['phoneNumber']);
    final photoUrl = _readString(data['photoUrl']);
    final name = displayName ?? email ?? phone ?? 'Back Home user';
    final handle = email ?? phone ?? '@${doc.id.substring(0, 6)}';

    return _HumanContact(
      uid: doc.id,
      userId: _publicUserIdForUid(doc.id),
      name: name,
      handle: handle,
      preview: 'Tap to start a conversation',
      tint: _tintForUid(doc.id),
      photoUrl: photoUrl,
    );
  }

  bool matches(String query) {
    if (query.isEmpty) {
      return true;
    }

    return name.toLowerCase().contains(query) ||
        handle.toLowerCase().contains(query) ||
        userId.contains(query);
  }

  static String? _readString(Object? value) {
    if (value is! String || value.trim().isEmpty) {
      return null;
    }
    return value.trim();
  }
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

  bool get isDirty => messages.any((message) => message.isUser);

  _TutorSession copyWith({String? subtitle, List<_TutorMessage>? messages}) {
    return _TutorSession(
      title: title,
      subtitle: subtitle ?? this.subtitle,
      messages: messages ?? this.messages,
    );
  }
}

class _TutorMessage {
  const _TutorMessage({
    required this.isUser,
    required this.text,
    this.isPending = false,
  });

  final bool isUser;
  final String text;
  final bool isPending;
}
