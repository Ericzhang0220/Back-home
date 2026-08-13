import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../auth/app_auth_controller.dart';
import '../chat/ai_chat_repository.dart';
import '../chat/ai_models.dart';
import '../chat/human_friends_repository.dart';
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

/// Direct chats are keyed by both participants, sorted so either side derives
/// the same document id.
String _chatIdFor(String a, String b) {
  final ids = [a, b]..sort();
  return '${ids[0]}_${ids[1]}';
}

/// Appends a human-to-human message, creating the chat document on first send.
Future<void> _sendDirectMessage({
  required String currentUid,
  required String peerUid,
  required String text,
}) async {
  final chatRef = FirebaseFirestore.instance
      .collection('chats')
      .doc(_chatIdFor(currentUid, peerUid));
  await chatRef.set({
    'participantUids': [currentUid, peerUid]..sort(),
    'updatedAt': FieldValue.serverTimestamp(),
    'lastMessage': text,
  }, SetOptions(merge: true));
  await chatRef.collection('messages').add({
    'senderUid': currentUid,
    'text': text,
    'createdAt': FieldValue.serverTimestamp(),
  });
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

  // Owned here, not by the discovery pages, so a half-typed message survives
  // the tab switch that tears those pages down.
  final _aiDiscoveryMessageController = TextEditingController();
  final _humanDiscoveryMessageController = TextEditingController();

  final _imagePicker = ImagePicker();

  _ChatPage _selectedPage = _ChatPage.ai;
  bool _showAiFriends = false;
  bool _showHumanFriends = false;
  bool _isTutorSidebarOpen = false;

  /// Held here rather than inside the discovery pages so that toggling to a
  /// friends list and back returns to the same profile instead of reshuffling.
  String? _discoveryCharacterId;
  String? _discoveryContactUid;

  AiChatRepository? _repository;
  HumanFriendsRepository? _humanFriends;

  /// Null until the user opens the Tutor tab, at which point the most recent
  /// session (or a freshly created one) is selected.
  String? _selectedTutorSessionId;

  /// Set while `askTutor` is in flight so the conversation can show a pending
  /// bubble that does not exist in Firestore.
  bool _isTutorReplying = false;

  /// Prevents repeated builds of the empty tutor state from creating more than
  /// one initial conversation.
  bool _isCreatingTutorSession = false;

  @override
  void initState() {
    super.initState();
    _syncRepository();
    widget.authController.addListener(_syncRepository);
  }

  @override
  void dispose() {
    widget.authController.removeListener(_syncRepository);
    _aiSearchController.dispose();
    _humanSearchController.dispose();
    _tutorSearchController.dispose();
    _messageController.dispose();
    _aiDiscoveryMessageController.dispose();
    _humanDiscoveryMessageController.dispose();
    super.dispose();
  }

  /// Rebuilds the repository whenever the signed-in account changes, so one
  /// user never sees another's conversations.
  void _syncRepository() {
    final uid = widget.authController.currentUser?.uid;
    if (uid == _repository?.uid) {
      return;
    }

    final repository = uid == null ? null : AiChatRepository(uid: uid);
    final humanFriends = uid == null
        ? null
        : HumanFriendsRepository(uid: uid);
    if (mounted) {
      setState(() {
        _repository = repository;
        _humanFriends = humanFriends;
        _selectedTutorSessionId = null;
        _discoveryContactUid = null;
      });
    } else {
      _repository = repository;
      _humanFriends = humanFriends;
      _selectedTutorSessionId = null;
      _discoveryContactUid = null;
    }

    if (repository != null) {
      // Fire and forget: the character list is a stream, so the seeded docs
      // arrive on their own once written.
      repository.seedPresetCharactersIfNeeded().catchError((Object _) {});
    }
  }

  @override
  Widget build(BuildContext context) {
    // No opaque background here: let the shared AmbientBackground gradient
    // (painted behind every tab) show through, matching the Hall and Profile
    // screens.
    final repository = _repository;
    final humanFriends = _humanFriends;
    final currentUid = widget.authController.currentUser?.uid;
    final isAiDiscovery =
        _selectedPage == _ChatPage.ai && !_showAiFriends && repository != null;
    // The human deck needs an account for the friends list it filters against,
    // so signed out the tab falls back to the plain directory it always was.
    final isHumanDiscovery =
        _selectedPage == _ChatPage.human &&
        !_showHumanFriends &&
        humanFriends != null &&
        currentUid != null;
    final isDiscovery = isAiDiscovery || isHumanDiscovery;

    return Stack(
      children: [
        if (isAiDiscovery)
          Positioned.fill(
            child: _AiDiscoveryPage(
              repository: repository,
              onToggleFriend: _toggleAiFriend,
              messageController: _aiDiscoveryMessageController,
              characterId: _discoveryCharacterId,
              onCharacterChanged: (id) {
                if (_discoveryCharacterId != id) {
                  setState(() => _discoveryCharacterId = id);
                }
              },
            ),
          ),
        if (isHumanDiscovery)
          Positioned.fill(
            child: _HumanDiscoveryPage(
              friendsRepository: humanFriends,
              currentUid: currentUid,
              messageController: _humanDiscoveryMessageController,
              contactUid: _discoveryContactUid,
              onContactChanged: (uid) {
                if (_discoveryContactUid != uid) {
                  setState(() => _discoveryContactUid = uid);
                }
              },
            ),
          ),
        Column(
          children: [
            _TopTabs(
              selectedPage: _selectedPage,
              isAiFriends: _showAiFriends,
              isHumanFriends: _showHumanFriends,
              overlay: true,
              onChanged: _selectPage,
            ),
            if (!isDiscovery)
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  // Only the AI and Tutor pages need an account — the human
                  // directory still renders signed out, as it always has.
                  child: switch (_selectedPage) {
                    _ChatPage.ai =>
                      repository == null
                          ? const _SignedOutNotice(
                              key: ValueKey(_ChatPage.ai),
                              text: 'Sign in to use the AI chats and tutor.',
                            )
                          : _AiContactsPage(
                              key: const ValueKey(_ChatPage.ai),
                              repository: repository,
                              searchController: _aiSearchController,
                              onSearchChanged: (_) => setState(() {}),
                              onPickAvatar: _pickAiAvatar,
                              onOpenCharacter: _openAiConversation,
                              onCreateCharacter: _showAddAiCharacterDialog,
                            ),
                    _ChatPage.human => _HumanContactsPage(
                      key: const ValueKey(_ChatPage.human),
                      searchController: _humanSearchController,
                      onSearchChanged: (_) => setState(() {}),
                      currentUid: currentUid,
                      friendsRepository: humanFriends,
                      onOpenContact: _openHumanConversation,
                    ),
                    _ChatPage.tutor =>
                      repository == null
                          ? const _SignedOutNotice(
                              key: ValueKey(_ChatPage.tutor),
                              text: 'Sign in to use the AI chats and tutor.',
                            )
                          : _TutorChatPage(
                              key: const ValueKey(_ChatPage.tutor),
                              repository: repository,
                              messageController: _messageController,
                              selectedSessionId: _selectedTutorSessionId,
                              isReplying: _isTutorReplying,
                              onSessionResolved: _rememberTutorSession,
                              onSessionNeeded: _ensureTutorSession,
                              onSendMessage: _sendTutorMessage,
                              onOpenHistory: () =>
                                  setState(() => _isTutorSidebarOpen = true),
                              onCloseHistory: () =>
                                  setState(() => _isTutorSidebarOpen = false),
                            ),
                  },
                ),
              ),
          ],
        ),
        // The tutor history drawer overlays the entire chat screen — header,
        // tabs and all — so it dominates the screen rather than sitting beside
        // the conversation card.
        if (_selectedPage == _ChatPage.tutor && repository != null)
          _TutorHistoryDrawer(
            isOpen: _isTutorSidebarOpen,
            repository: repository,
            searchController: _tutorSearchController,
            selectedSessionId: _selectedTutorSessionId,
            onSearchChanged: (_) => setState(() {}),
            onSessionSelected: (session) {
              setState(() {
                _selectedTutorSessionId = session.id;
                _isTutorSidebarOpen = false;
              });
            },
            onDeleteSession: _deleteTutorSession,
            onClose: () => setState(() => _isTutorSidebarOpen = false),
          ),
      ],
    );
  }

  /// The tutor page resolves which session to show from the live stream;
  /// this records that choice so the drawer and send handler agree on it.
  void _rememberTutorSession(String sessionId) {
    if (_selectedTutorSessionId == sessionId) {
      return;
    }
    // Called from a builder, so defer the state write past the current frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _selectedTutorSessionId != sessionId) {
        setState(() => _selectedTutorSessionId = sessionId);
      }
    });
  }

  void _selectPage(_ChatPage page) {
    // Tapping the tab you are already on flips that tab between its discovery
    // deck and its friends list. The AI and Human tabs each keep their own.
    if (page == _selectedPage) {
      if (page == _ChatPage.ai) {
        setState(() => _showAiFriends = !_showAiFriends);
        return;
      }
      if (page == _ChatPage.human) {
        setState(() => _showHumanFriends = !_showHumanFriends);
        return;
      }
    }

    // Those flags are deliberately left alone: leaving a tab and coming back
    // should land on whichever side of the toggle the user was last looking at.
    setState(() => _selectedPage = page);
  }

  Future<void> _showAddAiCharacterDialog() async {
    final repository = _repository;
    if (repository == null) {
      return;
    }

    final nameController = TextEditingController();
    final personalityController = TextEditingController();

    try {
      final draft = await showDialog<_CharacterDraft>(
        context: context,
        builder: (context) {
          return _AddCharacterDialog(
            nameController: nameController,
            personalityController: personalityController,
          );
        },
      );

      if (draft == null) {
        return;
      }

      await repository.createCharacter(
        name: draft.name,
        personality: draft.personality,
        isPublic: draft.isPublic,
      );
    } catch (error) {
      _showError('Could not create that character.');
    } finally {
      nameController.dispose();
      personalityController.dispose();
    }
  }

  Future<void> _pickAiAvatar(AiCharacter character) async {
    final repository = _repository;
    if (repository == null) {
      return;
    }

    final image = await _imagePicker.pickImage(source: ImageSource.gallery);
    if (image == null) {
      return;
    }

    final bytes = await image.readAsBytes();

    try {
      await repository.updateCharacterAvatar(
        characterId: character.id,
        bytes: bytes,
        contentType: image.mimeType ?? 'image/jpeg',
      );
    } catch (error) {
      _showError('Could not upload that picture.');
    }
  }

  Future<void> _toggleAiFriend(
    AiCharacter character, {
    required bool isSharedTemplate,
  }) async {
    final repository = _repository;
    if (repository == null) {
      return;
    }

    final add = !character.isFriend;
    try {
      if (isSharedTemplate) {
        // Nothing to flag yet — take a copy of the shared character first.
        await repository.adoptPublicCharacter(character);
      } else if (add) {
        await repository.addCharacterAsFriend(character.id);
      } else {
        await repository.removeCharacterAsFriend(character.id);
      }
      if (mounted) {
        _showError(
          add
              ? '${character.name} was added to your AI friends.'
              : '${character.name} was removed from your AI friends.',
        );
      }
    } catch (_) {
      _showError('Could not update that AI friend. Please try again.');
    }
  }

  Future<void> _ensureTutorSession() async {
    final repository = _repository;
    if (repository == null || _isCreatingTutorSession) {
      return;
    }

    _isCreatingTutorSession = true;
    try {
      final sessionId = await repository.createTutorSession();
      if (!mounted) {
        return;
      }
      setState(() {
        _selectedTutorSessionId = sessionId;
        _selectedPage = _ChatPage.tutor;
        _isTutorSidebarOpen = false;
        _tutorSearchController.clear();
      });
    } catch (error) {
      _showError('Could not start a new tutor chat.');
    } finally {
      _isCreatingTutorSession = false;
    }
  }

  Future<void> _deleteTutorSession(TutorSession session) async {
    final repository = _repository;
    if (repository == null) {
      return;
    }

    try {
      await repository.deleteTutorSession(session.id);
      if (!mounted) {
        return;
      }
      if (_selectedTutorSessionId == session.id) {
        // Let the stream pick the next most recent session.
        setState(() => _selectedTutorSessionId = null);
      }
    } catch (error) {
      _showError('Could not delete that chat.');
    }
  }

  Future<void> _sendTutorMessage() async {
    final repository = _repository;
    final sessionId = _selectedTutorSessionId;
    final message = _messageController.text.trim();

    if (repository == null || sessionId == null || message.isEmpty) {
      return;
    }
    if (_isTutorReplying) {
      return;
    }

    setState(() {
      _messageController.clear();
      _isTutorReplying = true;
    });

    try {
      await repository.sendToTutor(sessionId: sessionId, text: message);
    } on AiChatException catch (error) {
      _showError(error.message);
    } catch (error) {
      _showError('The tutor could not reply. Please try again.');
    } finally {
      if (mounted) {
        setState(() => _isTutorReplying = false);
      }
    }
  }

  void _showError(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openAiConversation(AiCharacter character) async {
    final repository = _repository;
    if (repository == null) {
      return;
    }

    final peer = _ChatPeer.ai(
      id: character.id,
      publicUserId: character.publicId,
      displayName: character.name,
      subtitle: character.personality,
      photoUrl: character.avatarUrl,
      tint: character.tint,
      icon: character.icon,
    );
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _DirectChatScreen(
          peer: peer,
          currentUid: widget.authController.currentUser?.uid,
          repository: repository,
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
          humanFriends: _humanFriends,
        ),
      ),
    );
  }
}

class _TopTabs extends StatelessWidget {
  const _TopTabs({
    required this.selectedPage,
    required this.isAiFriends,
    required this.isHumanFriends,
    required this.overlay,
    required this.onChanged,
  });

  final _ChatPage selectedPage;
  final bool isAiFriends;
  final bool isHumanFriends;
  final bool overlay;
  final ValueChanged<_ChatPage> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: overlay
          ? Colors.transparent
          : AppColors.card.withValues(alpha: 0.62),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Row(
        children: [
          for (final page in _ChatPage.values) ...[
            Expanded(
              child: _TabButton(
                label: switch (page) {
                  _ChatPage.ai => isAiFriends ? 'Friend' : 'AI',
                  _ChatPage.human => isHumanFriends ? 'Friend' : 'Human',
                  _ChatPage.tutor => 'Tutor',
                },
                icon: switch (page) {
                  _ChatPage.ai => Icons.auto_awesome_rounded,
                  _ChatPage.human => Icons.people_alt_rounded,
                  _ChatPage.tutor => Icons.school_rounded,
                },
                isSelected: selectedPage == page,
                flipLabel: page != _ChatPage.tutor,
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

class _TabButton extends StatefulWidget {
  const _TabButton({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.flipLabel,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool isSelected;
  final bool flipLabel;
  final VoidCallback onTap;

  @override
  State<_TabButton> createState() => _TabButtonState();
}

/// Swaps its label with a quarter turn: the outgoing wording rotates away to
/// edge-on while the next one swings in from the neighbouring face, as if both
/// were printed on the sides of an invisible cube. The faces never pass 90°,
/// so the words are never seen mirrored.
class _TabButtonState extends State<_TabButton>
    with SingleTickerProviderStateMixin {
  /// Half the cube's edge — matched to the button height so the words sit on a
  /// cube the size of the tab itself.
  static const double _halfEdge = 22;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
    value: 1,
  );

  String? _outgoingLabel;

  @override
  void didUpdateWidget(covariant _TabButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.flipLabel && widget.label != oldWidget.label) {
      _outgoingLabel = oldWidget.label;
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Places [child] on a cube face turned [angle] radians about the vertical
  /// axis, offset forward so it rides the cube's surface rather than spinning
  /// through its centre.
  Widget _face(Widget child, double angle) {
    final transform = Matrix4.identity()
      ..setEntry(3, 2, 0.0016)
      ..rotateY(angle)
      ..translateByDouble(0, 0, -_halfEdge, 1);
    return Transform(
      alignment: Alignment.center,
      transform: transform,
      child: child,
    );
  }

  Widget _content(String label) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          widget.icon,
          size: 18,
          color: widget.isSelected ? Colors.white : AppColors.muted,
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: widget.isSelected ? Colors.white : AppColors.ink,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: widget.isSelected
          ? AppColors.clay
          : Colors.white.withValues(alpha: 0.7),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: widget.onTap,
        child: Container(
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: widget.isSelected ? AppColors.clay : AppColors.stroke,
            ),
          ),
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final outgoingLabel = _outgoingLabel;
              if (_controller.isCompleted || outgoingLabel == null) {
                return _content(widget.label);
              }

              // The cube turns a single quarter: the leaving face goes 0 → -90°
              // as the arriving one comes from +90° → 0°.
              final turn =
                  Curves.easeInOut.transform(_controller.value) * math.pi / 2;
              return Stack(
                alignment: Alignment.center,
                children: [
                  _face(_content(outgoingLabel), -turn),
                  _face(_content(widget.label), math.pi / 2 - turn),
                ],
              );
            },
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
    required this.repository,
    required this.searchController,
    required this.onSearchChanged,
    required this.onPickAvatar,
    required this.onOpenCharacter,
    required this.onCreateCharacter,
  });

  final AiChatRepository repository;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<AiCharacter> onPickAvatar;
  final ValueChanged<AiCharacter> onOpenCharacter;
  final VoidCallback onCreateCharacter;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<AiCharacter>>(
      stream: repository.watchCharacters(),
      builder: (context, charactersSnapshot) {
        return StreamBuilder<Map<String, AiChatPreview>>(
          stream: repository.watchCharacterPreviews(),
          builder: (context, previewsSnapshot) {
            final previews =
                previewsSnapshot.data ?? const <String, AiChatPreview>{};
            final query = searchController.text.trim().toLowerCase();
            final characters =
                charactersSnapshot.data
                    ?.where(
                      (character) =>
                          character.isFriend && character.matches(query),
                    )
                    .toList() ??
                const <AiCharacter>[];

            return Stack(
              children: [
                ListView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 122),
                  children: [
                    _SearchField(
                      controller: searchController,
                      hintText: 'Search AI friends or ID',
                      onChanged: onSearchChanged,
                    ),
                    const SizedBox(height: 12),
                    _DeviceStatusBanner(
                      icon: Icons.memory_rounded,
                      text: charactersSnapshot.hasError
                          ? 'Could not load your AI friends.'
                          : 'Your saved AI friends and custom personalities',
                    ),
                    const SizedBox(height: 8),
                    if (charactersSnapshot.connectionState ==
                        ConnectionState.waiting)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 30),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else ...[
                      for (final character in characters)
                        _AiCharacterTile(
                          character: character,
                          // A started conversation replaces the scripted preview
                          // line with the last thing actually said.
                          preview: previews[character.id]?.lastMessage,
                          onPickAvatar: onPickAvatar,
                          onOpen: () => onOpenCharacter(character),
                        ),
                      if (characters.isEmpty)
                        const _EmptySearchResult(
                          text: 'No AI friends match this search.',
                        ),
                    ],
                  ],
                ),
                Positioned(
                  right: 20,
                  bottom: 104,
                  child: FloatingActionButton.small(
                    tooltip: 'Create an AI friend',
                    onPressed: onCreateCharacter,
                    backgroundColor: AppColors.clay,
                    foregroundColor: Colors.white,
                    child: const Icon(Icons.add_rounded),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

/// Full-screen AI friend discovery. Preset portraits can be supplied later by
/// setting `avatarUrl` on their character documents; until then each profile
/// uses its character color and icon as a deliberate visual placeholder.
class _AiDiscoveryPage extends StatefulWidget {
  const _AiDiscoveryPage({
    required this.repository,
    required this.onToggleFriend,
    required this.messageController,
    required this.characterId,
    required this.onCharacterChanged,
  });

  final AiChatRepository repository;

  /// [isSharedTemplate] marks a character that lives only in the public
  /// catalog, which has to be copied into this account rather than flagged.
  final Future<void> Function(
    AiCharacter character, {
    required bool isSharedTemplate,
  })
  onToggleFriend;

  /// Owned by the chat screen, so an unsent draft outlives this page.
  final TextEditingController messageController;

  /// The profile to show. Owned by the chat screen so it survives the
  /// AI ⇄ Friend toggle, which tears this page down and rebuilds it.
  final String? characterId;
  final ValueChanged<String?> onCharacterChanged;

  @override
  State<_AiDiscoveryPage> createState() => _AiDiscoveryPageState();
}

class _AiDiscoveryPageState extends State<_AiDiscoveryPage> {
  final math.Random _random = math.Random();
  bool _isReplying = false;

  String? get _currentCharacterId => widget.characterId;
  TextEditingController get _messageController => widget.messageController;

  void _showNext(List<AiCharacter> characters) {
    if (_isReplying) {
      return;
    }
    final choices = characters
        .where(
          (character) =>
              !character.isCustom &&
              !character.isFriend &&
              character.id != _currentCharacterId,
        )
        .toList();
    if (choices.isEmpty) {
      widget.onCharacterChanged(null);
      return;
    }
    widget.onCharacterChanged(choices[_random.nextInt(choices.length)].id);
  }

  Future<void> _sendMessage(
    AiCharacter character, {
    required bool isSharedTemplate,
  }) async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _isReplying) {
      return;
    }

    setState(() {
      _messageController.clear();
      _isReplying = true;
    });
    try {
      if (isSharedTemplate) {
        // The reply function reads the character from this account, so take a
        // copy first. It stays out of the friends list until the heart is
        // tapped.
        await widget.repository.adoptPublicCharacter(
          character,
          asFriend: false,
        );
      }
      await widget.repository.sendToCharacter(
        characterId: character.id,
        text: text,
      );
    } on AiChatException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not send that message.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isReplying = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<AiCharacter>>(
      stream: widget.repository.watchCharacters(),
      builder: (context, snapshot) {
        return StreamBuilder<List<AiCharacter>>(
          stream: widget.repository.watchPublicCharacters(),
          builder: (context, publicSnapshot) {
            return _buildDeck(
              context,
              snapshot,
              publicSnapshot.data ?? const <AiCharacter>[],
            );
          },
        );
      },
    );
  }

  Widget _buildDeck(
    BuildContext context,
    AsyncSnapshot<List<AiCharacter>> snapshot,
    List<AiCharacter> published,
  ) {
    final owned = snapshot.data ?? const <AiCharacter>[];
    final ownedIds = owned.map((character) => character.id).toSet();
    // Characters other people shared, minus the ones already copied into
    // this account — those are represented by the local copy instead.
    final shared = published
        .where(
          (template) =>
              template.authorUid != widget.repository.uid &&
              !ownedIds.contains(template.id),
        )
        .toList();
    final characters = [...owned, ...shared];
    final discoverable = [
      ...owned.where(
        (character) => !character.isCustom && !character.isFriend,
      ),
      ...shared,
    ];
    final current = characters.where(
      (character) => character.id == _currentCharacterId,
    );
    final selected = current.isNotEmpty
        ? current.first
        : (discoverable.isNotEmpty
              ? discoverable[_random.nextInt(discoverable.length)]
              : null);

    if (selected != null && selected.id != _currentCharacterId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _currentCharacterId != selected.id) {
          widget.onCharacterChanged(selected.id);
        }
      });
    }

    if (snapshot.connectionState == ConnectionState.waiting &&
        selected == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (selected == null) {
      // The tab button shows the side you are on, so the deck is left by
      // tapping the button that currently reads "AI".
      return const _DiscoveryCompleteState(
        title: 'You have met everyone',
        text: 'Tap AI above to chat with your saved AI friends.',
      );
    }

    final isSharedTemplate = shared.any(
      (template) => template.id == selected.id,
    );

    return StreamBuilder<List<AiMessage>>(
      stream: widget.repository.watchCharacterMessages(selected.id),
      builder: (context, messagesSnapshot) {
        final messages = messagesSnapshot.data ?? const <AiMessage>[];
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          // Anywhere on the card that is not the message field itself puts
          // the keyboard away.
          onTap: () => FocusScope.of(context).unfocus(),
          onHorizontalDragEnd: (details) {
            if ((details.primaryVelocity ?? 0) < -250) {
              _showNext(characters);
            }
          },
          child: ClipRect(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 360),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                final isIncoming =
                    child.key == ValueKey(_currentCharacterId);
                final offset = isIncoming
                    ? Tween<Offset>(
                        begin: const Offset(1, 0),
                        end: Offset.zero,
                      ).animate(animation)
                    : Tween<Offset>(
                        begin: const Offset(-1, 0),
                        end: Offset.zero,
                      ).animate(animation);
                return SlideTransition(position: offset, child: child);
              },
              child: _DiscoveryPortrait(
                key: ValueKey(selected.id),
                title: selected.name,
                photoUrl: selected.avatarUrl,
                tint: selected.tint,
                icon: selected.icon,
                isFriend: selected.isFriend,
                friendsLabel: 'AI friends',
                bubbles: [
                  _DiscoveryBubble(text: selected.introduction),
                  for (final message
                      in messages.reversed.take(2).toList().reversed)
                    _DiscoveryBubble(
                      text: message.text,
                      isUser: message.isUser,
                      isPending: message.isPending,
                    ),
                ],
                messageController: _messageController,
                isBusy: _isReplying,
                onToggleFriend: () => widget.onToggleFriend(
                  selected,
                  isSharedTemplate: isSharedTemplate,
                ),
                onSendMessage: () =>
                    _sendMessage(selected, isSharedTemplate: isSharedTemplate),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// One line of the conversation preview printed over a discovery card.
class _DiscoveryBubble {
  const _DiscoveryBubble({
    required this.text,
    this.isUser = false,
    this.isPending = false,
  });

  final String text;
  final bool isUser;
  final bool isPending;
}

/// The full-bleed "meet someone" card. Shared by the AI and Human decks, which
/// differ only in where their portrait, bubbles and friend state come from.
class _DiscoveryPortrait extends StatelessWidget {
  const _DiscoveryPortrait({
    super.key,
    required this.title,
    required this.photoUrl,
    required this.tint,
    required this.icon,
    required this.isFriend,
    required this.friendsLabel,
    required this.bubbles,
    required this.messageController,
    required this.isBusy,
    required this.onToggleFriend,
    required this.onSendMessage,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final String? photoUrl;
  final Color tint;
  final IconData icon;
  final bool isFriend;

  /// Names the list the heart adds to, e.g. 'AI friends'.
  final String friendsLabel;
  final List<_DiscoveryBubble> bubbles;
  final TextEditingController messageController;
  final bool isBusy;
  final VoidCallback onToggleFriend;
  final VoidCallback onSendMessage;

  /// Distance from the bottom of the card to the *top* of the composer. The
  /// composer is anchored by its top edge so a growing message expands down
  /// into the empty band below — the floating nav card hovers over that band
  /// only while it is summoned.
  static const double _composerTop = 152;
  static const double _composerBottomGap = 12;

  @override
  Widget build(BuildContext context) {
    final hasPortrait = photoUrl?.isNotEmpty ?? false;

    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          fit: StackFit.expand,
          children: [
            if (hasPortrait)
              Image.network(photoUrl!, fit: BoxFit.cover)
            else
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      tint.withValues(alpha: 0.98),
                      AppColors.ink.withValues(alpha: 0.96),
                    ],
                  ),
                ),
                child: Center(
                  child: Icon(
                    icon,
                    size: 180,
                    color: Colors.white.withValues(alpha: 0.74),
                  ),
                ),
              ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black26, Colors.transparent, Colors.black87],
                  stops: [0, 0.38, 1],
                ),
              ),
            ),
            Positioned(
              top: MediaQuery.paddingOf(context).top + 76,
              left: 18,
              child: _DiscoveryHeartButton(
                isFriend: isFriend,
                friendsLabel: friendsLabel,
                onPressed: onToggleFriend,
              ),
            ),
            Positioned(
              left: 20,
              right: 20,
              bottom: 166,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      shadows: const [
                        Shadow(color: Colors.black54, blurRadius: 10),
                      ],
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.88),
                        fontWeight: FontWeight.w600,
                        shadows: const [
                          Shadow(color: Colors.black54, blurRadius: 8),
                        ],
                      ),
                    ),
                  for (final bubble in bubbles) ...[
                    const SizedBox(height: 8),
                    _DiscoveryChatBubble(
                      text: bubble.text,
                      isUser: bubble.isUser,
                      isPending: bubble.isPending,
                    ),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    'Swipe left to meet someone new',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            // Anchored by its top edge, with the leftover space below it as
            // headroom, so a long message grows downward instead of climbing
            // over the bio.
            Positioned(
              left: 16,
              right: 16,
              top: math.max(0, constraints.maxHeight - _composerTop),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: math.max(0, _composerTop - _composerBottomGap),
                ),
                child: _DiscoveryComposer(
                  controller: messageController,
                  isReplying: isBusy,
                  onSendMessage: onSendMessage,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DiscoveryChatBubble extends StatelessWidget {
  const _DiscoveryChatBubble({
    required this.text,
    required this.isUser,
    this.isPending = false,
  });

  final String text;
  final bool isUser;
  final bool isPending;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 360),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isUser
              ? AppColors.clay.withValues(alpha: 0.94)
              : Colors.white.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          text,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: isUser ? Colors.white : AppColors.ink,
            height: 1.35,
            fontStyle: isPending ? FontStyle.italic : FontStyle.normal,
          ),
        ),
      ),
    );
  }
}

class _DiscoveryComposer extends StatelessWidget {
  const _DiscoveryComposer({
    required this.controller,
    required this.isReplying,
    required this.onSendMessage,
  });

  final TextEditingController controller;
  final bool isReplying;
  final VoidCallback onSendMessage;

  @override
  Widget build(BuildContext context) {
    return Row(
      // Keep the send button beside the last line as the field grows down.
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            enabled: !isReplying,
            minLines: 1,
            maxLines: 5,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => onSendMessage(),
            decoration: InputDecoration(
              hintText: isReplying ? 'Waiting for reply' : 'Send a message',
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.94),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filled(
          onPressed: isReplying ? null : onSendMessage,
          icon: const Icon(Icons.arrow_upward_rounded),
          tooltip: 'Send',
          style: IconButton.styleFrom(
            backgroundColor: AppColors.clay,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }
}

/// Toggles the card's subject in and out of the matching friends list — a
/// mistaken tap is undone by tapping again rather than by hunting for the
/// person in another screen.
class _DiscoveryHeartButton extends StatelessWidget {
  const _DiscoveryHeartButton({
    required this.isFriend,
    required this.friendsLabel,
    required this.onPressed,
  });

  final bool isFriend;
  final String friendsLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.9),
      borderRadius: BorderRadius.circular(24),
      child: IconButton(
        tooltip: isFriend
            ? 'Remove from $friendsLabel'
            : 'Add to $friendsLabel',
        onPressed: onPressed,
        icon: Icon(
          isFriend ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          color: isFriend ? AppColors.clay : AppColors.ink,
        ),
      ),
    );
  }
}

class _DiscoveryCompleteState extends StatelessWidget {
  const _DiscoveryCompleteState({required this.title, required this.text});

  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: AppColors.ink),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.favorite_rounded,
                color: AppColors.blush,
                size: 46,
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(color: Colors.white),
              ),
              const SizedBox(height: 8),
              Text(
                text,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.82),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SignedOutNotice extends StatelessWidget {
  const _SignedOutNotice({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }
}

/// The Human tab's counterpart to `_AiDiscoveryPage`: one app user at a time,
/// swipe left for the next, heart to save them to your people.
class _HumanDiscoveryPage extends StatefulWidget {
  const _HumanDiscoveryPage({
    required this.friendsRepository,
    required this.currentUid,
    required this.messageController,
    required this.contactUid,
    required this.onContactChanged,
  });

  final HumanFriendsRepository friendsRepository;
  final String currentUid;

  /// Owned by the chat screen, so an unsent draft outlives this page.
  final TextEditingController messageController;

  /// Owned by the chat screen so it survives the Human ⇄ Friend toggle.
  final String? contactUid;
  final ValueChanged<String?> onContactChanged;

  @override
  State<_HumanDiscoveryPage> createState() => _HumanDiscoveryPageState();
}

class _HumanDiscoveryPageState extends State<_HumanDiscoveryPage> {
  final math.Random _random = math.Random();
  bool _isSending = false;

  String? get _currentContactUid => widget.contactUid;
  TextEditingController get _messageController => widget.messageController;

  void _showNext(List<_HumanContact> discoverable) {
    if (_isSending) {
      return;
    }
    final choices = discoverable
        .where((contact) => contact.uid != _currentContactUid)
        .toList();
    if (choices.isEmpty) {
      widget.onContactChanged(null);
      return;
    }
    widget.onContactChanged(choices[_random.nextInt(choices.length)].uid);
  }

  Future<void> _toggleFriend(
    _HumanContact contact, {
    required bool isFriend,
  }) async {
    try {
      if (isFriend) {
        await widget.friendsRepository.removeFriend(contact.uid);
      } else {
        await widget.friendsRepository.addFriend(contact.uid);
      }
      if (mounted && !isFriend) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text('Saved. ${contact.name} was sent a request.'),
            ),
          );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update that person.')),
        );
      }
    }
  }

  Future<void> _sendMessage(_HumanContact contact) async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _isSending) {
      return;
    }

    setState(() {
      _messageController.clear();
      _isSending = true;
    });
    try {
      await _sendDirectMessage(
        currentUid: widget.currentUid,
        peerUid: contact.uid,
        text: text,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not send that message.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Set<String>>(
      stream: widget.friendsRepository.watchFriendUids(),
      builder: (context, friendsSnapshot) {
        final friendUids = friendsSnapshot.data ?? const <String>{};

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance.collection('users').snapshots(),
          builder: (context, usersSnapshot) {
            final contacts =
                usersSnapshot.data?.docs
                    .where((doc) => doc.id != widget.currentUid)
                    .map(_HumanContact.fromUserDoc)
                    .toList() ??
                const <_HumanContact>[];
            final discoverable = contacts
                .where((contact) => !friendUids.contains(contact.uid))
                .toList();

            final current = contacts.where(
              (contact) => contact.uid == _currentContactUid,
            );
            final selected = current.isNotEmpty
                ? current.first
                : (discoverable.isNotEmpty
                      ? discoverable[_random.nextInt(discoverable.length)]
                      : null);

            if (selected != null && selected.uid != _currentContactUid) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && _currentContactUid != selected.uid) {
                  widget.onContactChanged(selected.uid);
                }
              });
            }

            if (usersSnapshot.connectionState == ConnectionState.waiting &&
                selected == null) {
              return const Center(child: CircularProgressIndicator());
            }

            if (selected == null) {
              return const _DiscoveryCompleteState(
                title: 'You have met everyone',
                text: 'Tap Human above to see the people you saved.',
              );
            }

            final isFriend = friendUids.contains(selected.uid);
            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('chats')
                  .doc(_chatIdFor(widget.currentUid, selected.uid))
                  .collection('messages')
                  .orderBy('createdAt', descending: true)
                  .limit(2)
                  .snapshots(),
              builder: (context, messagesSnapshot) {
                // A chat that does not exist yet is unreadable by the rules, so
                // an error here simply means "nothing said so far".
                final docs = messagesSnapshot.hasError
                    ? const <QueryDocumentSnapshot<Map<String, dynamic>>>[]
                    : (messagesSnapshot.data?.docs ??
                          const <QueryDocumentSnapshot<Map<String, dynamic>>>[]);

                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => FocusScope.of(context).unfocus(),
                  onHorizontalDragEnd: (details) {
                    if ((details.primaryVelocity ?? 0) < -250) {
                      _showNext(discoverable);
                    }
                  },
                  child: ClipRect(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 360),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, animation) {
                        final isIncoming =
                            child.key == ValueKey(_currentContactUid);
                        final offset = isIncoming
                            ? Tween<Offset>(
                                begin: const Offset(1, 0),
                                end: Offset.zero,
                              ).animate(animation)
                            : Tween<Offset>(
                                begin: const Offset(-1, 0),
                                end: Offset.zero,
                              ).animate(animation);
                        return SlideTransition(position: offset, child: child);
                      },
                      child: _DiscoveryPortrait(
                        key: ValueKey(selected.uid),
                        title: selected.name,
                        subtitle: selected.handle,
                        photoUrl: selected.photoUrl,
                        tint: selected.tint,
                        icon: Icons.person_rounded,
                        isFriend: isFriend,
                        friendsLabel: 'your people',
                        bubbles: [
                          for (final doc in docs.reversed)
                            _DiscoveryBubble(
                              text: (doc.data()['text'] as String?)?.trim() ??
                                  '',
                              isUser:
                                  doc.data()['senderUid'] == widget.currentUid,
                            ),
                        ],
                        messageController: _messageController,
                        isBusy: _isSending,
                        onToggleFriend: () =>
                            _toggleFriend(selected, isFriend: isFriend),
                        onSendMessage: () => _sendMessage(selected),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _HumanContactsPage extends StatelessWidget {
  const _HumanContactsPage({
    super.key,
    required this.searchController,
    required this.onSearchChanged,
    required this.currentUid,
    required this.friendsRepository,
    required this.onOpenContact,
  });

  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final String? currentUid;

  /// Null when signed out, in which case the tab falls back to listing the
  /// whole directory the way it did before friends lists existed.
  final HumanFriendsRepository? friendsRepository;
  final ValueChanged<_HumanContact> onOpenContact;

  @override
  Widget build(BuildContext context) {
    final friendsRepository = this.friendsRepository;

    return StreamBuilder<Set<String>>(
      stream: friendsRepository?.watchFriendUids(),
      builder: (context, friendsSnapshot) {
        final friendUids = friendsSnapshot.data;
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance.collection('users').snapshots(),
          builder: (context, usersSnapshot) {
            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: currentUid == null
                  ? null
                  : FirebaseFirestore.instance
                        .collection('chats')
                        .where('participantUids', arrayContains: currentUid)
                        .snapshots(),
              builder: (context, chatsSnapshot) {
                final previews = _previewsByPeer(chatsSnapshot.data?.docs);

                final query = searchController.text.trim().toLowerCase();
                final contacts =
                    usersSnapshot.data?.docs
                        .where((doc) => doc.id != currentUid)
                        .map(_HumanContact.fromUserDoc)
                        .map((contact) {
                          final preview = previews[contact.uid];
                          if (preview == null) {
                            return contact;
                          }
                          return contact.copyWith(
                            preview: preview.lastMessage,
                            lastActivity: preview.updatedAt,
                            hasConversation: true,
                          );
                        })
                        // Friends, plus anyone already mid-conversation so a
                        // thread can never become unreachable by unliking.
                        // Signed out there is no list to filter against, so
                        // the tab stays the plain directory it always was.
                        .where(
                          (contact) =>
                              friendsRepository == null ||
                              (friendUids?.contains(contact.uid) ?? false) ||
                              contact.hasConversation,
                        )
                        .where((contact) => contact.matches(query))
                        .toList() ??
                    <_HumanContact>[];
                contacts.sort(_compareContacts);

                return ListView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 122),
                  children: [
                    _SearchField(
                      controller: searchController,
                      hintText: friendsRepository == null
                          ? 'Search app users or ID'
                          : 'Search your people or ID',
                      onChanged: onSearchChanged,
                    ),
                    const SizedBox(height: 12),
                    _DeviceStatusBanner(
                      icon: Icons.phone_iphone_rounded,
                      text: usersSnapshot.hasError
                          ? 'Could not load Firebase users.'
                          : 'Your saved people and open conversations',
                    ),
                    const SizedBox(height: 8),
                    if (usersSnapshot.connectionState ==
                        ConnectionState.waiting)
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
                        _EmptySearchResult(
                          text: query.isEmpty
                              ? 'No saved people yet. Tap Friend above to meet '
                                    'someone.'
                              : 'No people match this search.',
                        ),
                    ],
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Map<String, _ChatPreview> _previewsByPeer(
    List<QueryDocumentSnapshot<Map<String, dynamic>>>? chatDocs,
  ) {
    final previews = <String, _ChatPreview>{};
    for (final doc in chatDocs ?? const []) {
      final data = doc.data();
      final participants =
          (data['participantUids'] as List<dynamic>?)
              ?.whereType<String>()
              .toList() ??
          const <String>[];
      final otherUid = participants.firstWhere(
        (uid) => uid != currentUid,
        orElse: () => '',
      );
      if (otherUid.isEmpty) {
        continue;
      }
      final lastMessage = (data['lastMessage'] as String?)?.trim() ?? '';
      if (lastMessage.isEmpty) {
        continue;
      }
      previews[otherUid] = _ChatPreview(
        lastMessage: lastMessage,
        updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
      );
    }
    return previews;
  }

  static int _compareContacts(_HumanContact a, _HumanContact b) {
    if (a.hasConversation != b.hasConversation) {
      // Active conversations rise above the rest of the directory.
      return a.hasConversation ? -1 : 1;
    }
    if (a.hasConversation && b.hasConversation) {
      final aTime = a.lastActivity;
      final bTime = b.lastActivity;
      if (aTime != null && bTime != null) {
        return bTime.compareTo(aTime);
      }
      // A null timestamp is a just-sent message awaiting the server clock;
      // keep it at the top so the newest chat does not jump around.
      if (aTime == null && bTime != null) {
        return -1;
      }
      if (aTime != null && bTime == null) {
        return 1;
      }
    }
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }
}

class _TutorChatPage extends StatelessWidget {
  const _TutorChatPage({
    super.key,
    required this.repository,
    required this.messageController,
    required this.selectedSessionId,
    required this.isReplying,
    required this.onSessionResolved,
    required this.onSessionNeeded,
    required this.onSendMessage,
    required this.onOpenHistory,
    required this.onCloseHistory,
  });

  final AiChatRepository repository;
  final TextEditingController messageController;
  final String? selectedSessionId;
  final bool isReplying;
  final ValueChanged<String> onSessionResolved;
  final VoidCallback onSessionNeeded;
  final VoidCallback onSendMessage;
  final VoidCallback onOpenHistory;
  final VoidCallback onCloseHistory;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity > 300) {
          onOpenHistory();
        } else if (velocity < -300) {
          onCloseHistory();
        }
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
        child: StreamBuilder<List<TutorSession>>(
          stream: repository.watchTutorSessions(),
          builder: (context, sessionsSnapshot) {
            if (sessionsSnapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final sessions = sessionsSnapshot.data ?? const <TutorSession>[];
            if (sessions.isEmpty) {
              // The Tutor has one assistant, so a person should land directly
              // in a ready-to-use chat instead of needing a separate plus
              // action to create its first conversation.
              WidgetsBinding.instance.addPostFrameCallback(
                (_) => onSessionNeeded(),
              );
              return const _TutorStartingState();
            }

            // Sessions stream newest-first; fall back to that when the
            // selected id is stale (deleted, or a fresh sign-in).
            final session = sessions.firstWhere(
              (candidate) => candidate.id == selectedSessionId,
              orElse: () => sessions.first,
            );
            onSessionResolved(session.id);

            return StreamBuilder<List<AiMessage>>(
              stream: repository.watchTutorMessages(session.id),
              builder: (context, messagesSnapshot) {
                final messages = messagesSnapshot.data ?? const <AiMessage>[];
                return _TutorConversation(
                  session: session,
                  messages: [
                    ...messages,
                    if (isReplying) const AiMessage.pending(),
                  ],
                  isLoading:
                      messagesSnapshot.connectionState ==
                      ConnectionState.waiting,
                  isReplying: isReplying,
                  messageController: messageController,
                  onSendMessage: onSendMessage,
                  onOpenHistory: onOpenHistory,
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _TutorStartingState extends StatelessWidget {
  const _TutorStartingState();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.76),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.stroke),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.school_rounded, color: AppColors.clay, size: 42),
              const SizedBox(height: 14),
              Text(
                'Getting Tutor ready',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Your first conversation will be ready in a moment.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TutorHistoryDrawer extends StatelessWidget {
  const _TutorHistoryDrawer({
    required this.isOpen,
    required this.repository,
    required this.searchController,
    required this.selectedSessionId,
    required this.onSearchChanged,
    required this.onSessionSelected,
    required this.onDeleteSession,
    required this.onClose,
  });

  final bool isOpen;
  final AiChatRepository repository;
  final TextEditingController searchController;
  final String? selectedSessionId;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<TutorSession> onSessionSelected;
  final ValueChanged<TutorSession> onDeleteSession;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 430;
        // Spans almost the full width so the drawer dominates the screen,
        // leaving a slim strip of scrim to tap (or swipe) it closed.
        final drawerWidth = (constraints.maxWidth * 0.9).clamp(0.0, 560.0);

        return Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                ignoring: !isOpen,
                child: GestureDetector(
                  onTap: onClose,
                  onHorizontalDragEnd: (details) {
                    if ((details.primaryVelocity ?? 0) < -200) {
                      onClose();
                    }
                  },
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                    opacity: isOpen ? 1 : 0,
                    child: ColoredBox(
                      color: AppColors.ink.withValues(alpha: 0.38),
                    ),
                  ),
                ),
              ),
            ),
            AnimatedPositioned(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              top: 0,
              bottom: 0,
              left: isOpen ? 0 : -(drawerWidth + 32),
              width: drawerWidth,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragEnd: (details) {
                  if ((details.primaryVelocity ?? 0) < -200) {
                    onClose();
                  }
                },
                child: _TutorSidebar(
                  repository: repository,
                  searchController: searchController,
                  selectedSessionId: selectedSessionId,
                  compact: compact,
                  onSearchChanged: onSearchChanged,
                  onSessionSelected: onSessionSelected,
                  onDeleteSession: onDeleteSession,
                  onCollapse: onClose,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _TutorSidebar extends StatelessWidget {
  const _TutorSidebar({
    required this.repository,
    required this.searchController,
    required this.selectedSessionId,
    required this.compact,
    required this.onSearchChanged,
    required this.onSessionSelected,
    required this.onDeleteSession,
    required this.onCollapse,
  });

  final AiChatRepository repository;
  final TextEditingController searchController;
  final String? selectedSessionId;
  final bool compact;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<TutorSession> onSessionSelected;
  final ValueChanged<TutorSession> onDeleteSession;
  final VoidCallback onCollapse;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 16,
      shadowColor: AppColors.ink.withValues(alpha: 0.3),
      color: AppColors.cream,
      borderRadius: const BorderRadius.horizontal(right: Radius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        // Extra bottom inset keeps the list clear of the floating nav bar.
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 96),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Chat history',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: AppColors.ink,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Close history',
                  onPressed: onCollapse,
                  icon: const Icon(Icons.close_rounded),
                  color: AppColors.ink,
                ),
              ],
            ),
            const SizedBox(height: 10),
            _SearchField(
              controller: searchController,
              hintText: compact ? 'Search history' : 'Search chat history',
              onChanged: onSearchChanged,
            ),
            const SizedBox(height: 12),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.stroke),
                ),
                child: StreamBuilder<List<TutorSession>>(
                  stream: repository.watchTutorSessions(),
                  builder: (context, snapshot) {
                    final query = searchController.text.trim().toLowerCase();
                    final sessions =
                        snapshot.data
                            ?.where((session) => session.matches(query))
                            .toList() ??
                        const <TutorSession>[];

                    return ListView(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      children: [
                        for (final session in sessions)
                          _TutorHistoryTile(
                            session: session,
                            isSelected: session.id == selectedSessionId,
                            onTap: () => onSessionSelected(session),
                            onDelete: () => onDeleteSession(session),
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
                    );
                  },
                ),
              ),
            ),
          ],
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
    required this.preview,
    required this.onPickAvatar,
    required this.onOpen,
  });

  final AiCharacter character;
  final String? preview;
  final ValueChanged<AiCharacter> onPickAvatar;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final lastMessage = preview?.trim() ?? '';

    return _ChatRow(
      onTap: onOpen,
      avatar: _EditableAvatar(character: character, onPickAvatar: onPickAvatar),
      title: character.name,
      subtitle: lastMessage.isEmpty ? character.preview : lastMessage,
      meta: character.publicId,
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

  final AiCharacter character;
  final ValueChanged<AiCharacter> onPickAvatar;

  @override
  Widget build(BuildContext context) {
    final avatar = _AvatarBox(
      color: character.tint,
      icon: character.icon,
      photoUrl: character.avatarUrl,
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
  const _AvatarBox({required this.color, required this.icon, this.photoUrl});

  final Color color;
  final IconData icon;
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
          child: (photoUrl != null && photoUrl!.isNotEmpty)
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
    required this.onDelete,
  });

  final TutorSession session;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Material(
        color: isSelected ? AppColors.blush : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          onLongPress: () => _confirmDelete(context),
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        session.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.ink,
                          fontSize: 16,
                          fontWeight: isSelected
                              ? FontWeight.w800
                              : FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        session.subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 13,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Delete chat',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _confirmDelete(context),
                  icon: const Icon(Icons.delete_outline_rounded, size: 19),
                  color: AppColors.muted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this chat?'),
        content: Text('"${session.title}" and its messages will be removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed ?? false) {
      onDelete();
    }
  }
}

class _TutorConversation extends StatelessWidget {
  const _TutorConversation({
    required this.session,
    required this.messages,
    required this.isLoading,
    required this.isReplying,
    required this.messageController,
    required this.onSendMessage,
    required this.onOpenHistory,
  });

  final TutorSession session;
  final List<AiMessage> messages;
  final bool isLoading;
  final bool isReplying;
  final TextEditingController messageController;
  final VoidCallback onSendMessage;
  final VoidCallback onOpenHistory;

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
            padding: const EdgeInsets.fromLTRB(6, 0, 14, 0),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.stroke)),
            ),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Chat history',
                  onPressed: onOpenHistory,
                  icon: const Icon(Icons.menu_rounded),
                  color: AppColors.clay,
                ),
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
            child: isLoading && messages.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : messages.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        'What would you like to work through right now?',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    // Newest messages sit at the bottom, so anchoring the
                    // list there keeps the latest reply in view as it grows.
                    reverse: true,
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      return _TutorBubble(
                        message: messages[messages.length - 1 - index],
                      );
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
                    enabled: !isReplying,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => onSendMessage(),
                    decoration: InputDecoration(
                      hintText: isReplying
                          ? 'Waiting for reply'
                          : 'Ask the tutor',
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
                  onPressed: isReplying ? null : onSendMessage,
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

  final AiMessage message;

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
        child: message.isPending
            ? const _TypingIndicator()
            : Text(
                message.text,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.ink,
                  fontSize: 13,
                ),
              ),
      ),
    );
  }
}

/// Three-dot "typing" affordance shown while a reply is in flight.
class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (index) {
            // Each dot peaks a third of a cycle after the previous one.
            final phase = (_controller.value - index * 0.2) % 1.0;
            final opacity = 0.3 + 0.7 * (1 - (phase * 2 - 1).abs()).clamp(0, 1);
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
              child: Opacity(
                opacity: opacity.toDouble(),
                child: Container(
                  height: 7,
                  width: 7,
                  decoration: const BoxDecoration(
                    color: AppColors.muted,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

class _DirectChatScreen extends StatefulWidget {
  const _DirectChatScreen({
    required this.peer,
    required this.currentUid,
    this.repository,
    this.humanFriends,
  });

  final _ChatPeer peer;
  final String? currentUid;

  /// Present for AI peers, whose turns are produced by a Cloud Function.
  final AiChatRepository? repository;

  /// Present for human peers when signed in, so the heart can toggle them.
  final HumanFriendsRepository? humanFriends;

  @override
  State<_DirectChatScreen> createState() => _DirectChatScreenState();
}

class _DirectChatScreenState extends State<_DirectChatScreen> {
  final _controller = TextEditingController();

  /// True while `chatWithCharacter` is in flight.
  bool _isReplying = false;

  /// True while the friend toggle is being written, so a double tap cannot
  /// queue two conflicting writes.
  bool _isUpdatingFriend = false;

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
        // The action slot belongs to the heart for AI friends, so the profile
        // moves onto the name itself.
        title: InkWell(
          onTap: _showPeerProfile,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(
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
          ),
        ),
        actions: [_buildAppBarAction()],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(child: _buildMessages()),
            _MessageComposer(
              controller: _controller,
              onSend: _sendMessage,
              isBusy: _isReplying,
            ),
          ],
        ),
      ),
    );
  }

  /// A liked AI companion gets a heart in place of the profile button, so the
  /// same control that added them can drop them again. Human contacts and the
  /// characters you made yourself — which are always in your list — keep the
  /// profile button.
  Widget _buildAppBarAction() {
    final repository = widget.repository;
    final humanFriends = widget.humanFriends;

    if (!widget.peer.isAi) {
      if (humanFriends == null) {
        return _buildProfileButton();
      }
      return StreamBuilder<bool>(
        stream: humanFriends.watchIsFriend(widget.peer.id),
        builder: (context, snapshot) {
          return _buildHeartButton(
            isFriend: snapshot.data ?? false,
            friendsLabel: 'your people',
          );
        },
      );
    }

    if (repository == null) {
      return _buildProfileButton();
    }

    return StreamBuilder<AiCharacter?>(
      stream: repository.watchCharacter(widget.peer.id),
      builder: (context, snapshot) {
        final character = snapshot.data;
        if (character == null || character.isCustom) {
          return _buildProfileButton();
        }
        return _buildHeartButton(
          isFriend: character.isFriend,
          friendsLabel: 'AI friends',
        );
      },
    );
  }

  Widget _buildHeartButton({
    required bool isFriend,
    required String friendsLabel,
  }) {
    return IconButton(
      tooltip: isFriend ? 'Remove from $friendsLabel' : 'Add to $friendsLabel',
      onPressed: _isUpdatingFriend
          ? null
          : () => _setFriend(isFriend: !isFriend),
      icon: Icon(
        isFriend ? Icons.favorite_rounded : Icons.favorite_border_rounded,
        color: isFriend ? AppColors.clay : AppColors.muted,
      ),
    );
  }

  Widget _buildProfileButton() {
    return IconButton(
      tooltip: 'Profile',
      onPressed: _showPeerProfile,
      icon: const Icon(Icons.info_outline_rounded),
    );
  }

  Future<void> _setFriend({required bool isFriend}) async {
    final repository = widget.repository;
    final humanFriends = widget.humanFriends;
    if (_isUpdatingFriend) {
      return;
    }

    setState(() => _isUpdatingFriend = true);
    try {
      if (widget.peer.isAi) {
        if (repository == null) {
          return;
        }
        if (isFriend) {
          await repository.addCharacterAsFriend(widget.peer.id);
        } else {
          await repository.removeCharacterAsFriend(widget.peer.id);
        }
      } else {
        if (humanFriends == null) {
          return;
        }
        if (isFriend) {
          await humanFriends.addFriend(widget.peer.id);
        } else {
          await humanFriends.removeFriend(widget.peer.id);
        }
      }

      if (mounted) {
        final name = widget.peer.displayName;
        final list = widget.peer.isAi ? 'your AI friends' : 'your people';
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                isFriend
                    ? '$name is back in $list.'
                    : '$name was removed from $list.',
              ),
            ),
          );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update that friend.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUpdatingFriend = false);
      }
    }
  }

  Widget _buildMessages() {
    if (widget.peer.isAi) {
      return _buildAiMessages();
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

  Widget _buildAiMessages() {
    final repository = widget.repository;
    if (repository == null) {
      return const Center(child: Text('Sign in to start chatting.'));
    }

    return StreamBuilder<List<AiMessage>>(
      stream: repository.watchCharacterMessages(widget.peer.id),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final messages = snapshot.data ?? const <AiMessage>[];
        if (messages.isEmpty && !_isReplying) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Text(
                'Hi, I am ${widget.peer.displayName}. '
                'What do you want to talk through?',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          );
        }

        return _MessageList(
          messages: [
            for (final message in messages)
              _DirectMessage(
                isMine: message.isUser,
                text: message.text,
                sentAt: message.createdAt,
              ),
            if (_isReplying)
              const _DirectMessage(
                isMine: false,
                text: '',
                sentAt: null,
                isPending: true,
              ),
          ],
        );
      },
    );
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isReplying) {
      return;
    }

    _controller.clear();

    if (widget.peer.isAi) {
      final repository = widget.repository;
      if (repository == null) {
        return;
      }

      setState(() => _isReplying = true);
      try {
        await repository.sendToCharacter(
          characterId: widget.peer.id,
          text: text,
        );
      } on AiChatException catch (error) {
        _showError(error.message);
      } catch (error) {
        _showError('${widget.peer.displayName} could not reply right now.');
      } finally {
        if (mounted) {
          setState(() => _isReplying = false);
        }
      }
      return;
    }

    final currentUid = widget.currentUid;
    if (currentUid == null) {
      return;
    }

    await _sendDirectMessage(
      currentUid: currentUid,
      peerUid: widget.peer.id,
      text: text,
    );
  }

  void _showError(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
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
      // Anchored to the bottom so a new reply is visible without scrolling.
      reverse: true,
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final message = messages[messages.length - 1 - index];
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
            child: message.isPending
                ? const _TypingIndicator()
                : Text(message.text),
          ),
        );
      },
    );
  }
}

class _MessageComposer extends StatelessWidget {
  const _MessageComposer({
    required this.controller,
    required this.onSend,
    this.isBusy = false,
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final bool isBusy;

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
              enabled: !isBusy,
              onSubmitted: (_) => onSend(),
              decoration: InputDecoration(
                hintText: isBusy ? 'Waiting for reply' : 'Message',
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
            onPressed: isBusy ? null : onSend,
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
      child: (peer.photoUrl?.isNotEmpty ?? false)
          ? Image.network(peer.photoUrl!, fit: BoxFit.cover)
          : Icon(peer.icon, color: AppColors.ink, size: size * 0.48),
    );
  }
}

/// Values collected by [_AddCharacterDialog]; the document itself is created
/// by the repository so the dialog stays free of Firestore concerns.
class _CharacterDraft {
  const _CharacterDraft({
    required this.name,
    required this.personality,
    required this.isPublic,
  });

  final String name;
  final String personality;

  /// Shared with every account rather than kept to the creator.
  final bool isPublic;
}

class _AddCharacterDialog extends StatefulWidget {
  const _AddCharacterDialog({
    required this.nameController,
    required this.personalityController,
  });

  final TextEditingController nameController;
  final TextEditingController personalityController;

  @override
  State<_AddCharacterDialog> createState() => _AddCharacterDialogState();
}

class _AddCharacterDialogState extends State<_AddCharacterDialog> {
  // Private by default: sharing a character publishes it to everyone, so it
  // should be something the creator opts into rather than out of.
  bool _isPublic = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add AI character'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: widget.nameController,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: widget.personalityController,
              minLines: 1,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Personality',
                helperText: 'How should they talk to you?',
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile.adaptive(
              value: _isPublic,
              onChanged: (value) => setState(() => _isPublic = value),
              contentPadding: EdgeInsets.zero,
              title: Text(_isPublic ? 'Public' : 'Private'),
              subtitle: Text(
                _isPublic
                    ? 'Everyone can find them in their AI tab and add their '
                          'own copy. Your conversations stay yours.'
                    : 'Only you can see and chat with them.',
              ),
              secondary: Icon(
                _isPublic ? Icons.public_rounded : Icons.lock_rounded,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final name = widget.nameController.text.trim();
            final personality = widget.personalityController.text.trim();
            if (name.isEmpty || personality.isEmpty) {
              return;
            }

            Navigator.of(context).pop(
              _CharacterDraft(
                name: name,
                personality: personality,
                isPublic: _isPublic,
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
  });

  factory _ChatPeer.ai({
    required String id,
    required String publicUserId,
    required String displayName,
    required String subtitle,
    required Color tint,
    required IconData icon,
    String? photoUrl,
  }) {
    return _ChatPeer._(
      id: id,
      publicUserId: publicUserId,
      displayName: displayName,
      subtitle: subtitle,
      isAi: true,
      tint: tint,
      icon: icon,
      photoUrl: photoUrl,
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
}

class _DirectMessage {
  const _DirectMessage({
    required this.isMine,
    required this.text,
    required this.sentAt,
    this.isPending = false,
  });

  final bool isMine;
  final String text;
  final DateTime? sentAt;

  /// Local-only placeholder rendered as a typing indicator.
  final bool isPending;
}

class _ChatPreview {
  const _ChatPreview({required this.lastMessage, this.updatedAt});

  final String lastMessage;
  final DateTime? updatedAt;
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
    this.lastActivity,
    this.hasConversation = false,
  });

  final String uid;
  final String userId;
  final String name;
  final String handle;
  final String preview;
  final Color tint;
  final String? photoUrl;
  final DateTime? lastActivity;
  final bool hasConversation;

  _HumanContact copyWith({
    String? preview,
    DateTime? lastActivity,
    bool? hasConversation,
  }) {
    return _HumanContact(
      uid: uid,
      userId: userId,
      name: name,
      handle: handle,
      preview: preview ?? this.preview,
      tint: tint,
      photoUrl: photoUrl,
      lastActivity: lastActivity ?? this.lastActivity,
      hasConversation: hasConversation ?? this.hasConversation,
    );
  }

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
