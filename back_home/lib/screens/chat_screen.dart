import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../auth/app_auth_controller.dart';
import '../chat/ai_chat_repository.dart';
import '../chat/ai_character_photo.dart';
import '../chat/ai_discovery_recommender.dart';
import '../chat/ai_models.dart';
import '../chat/chat_inbox_controller.dart';
import '../chat/chat_background_store.dart';
import '../chat/discovery_browse_history.dart';
import '../chat/discovery_card_content.dart';
import '../chat/discovery_card_surface.dart';
import '../chat/discovery_conversation.dart';
import '../chat/discovery_top_tabs.dart';
import '../chat/human_friends_repository.dart';
import '../widgets/app_ui.dart';
import '../widgets/add_ai_character_dialog.dart';
import '../widgets/edit_ai_character_dialog.dart';
import '../widgets/fullscreen_photo_viewer.dart';
import '../widgets/chat_message_actions.dart';
import '../widgets/swipeable_chat_row.dart';
import '../widgets/visible_chat_read_receipt.dart';
import '../widgets/character_portrait.dart';
import '../widgets/chat_background.dart';
import '../widgets/profile_avatar.dart';

enum _ChatPage { ai, human, tutor }

Future<void> openAiCharacterConversation(
  BuildContext context, {
  required AiCharacter character,
  required AiChatRepository repository,
  ChatInboxController? inbox,
  Future<void> Function()? onEditPhoto,
  ChatBackgroundStore? backgroundStore,
  Future<AiCharacterPhoto?> Function()? pickBackgroundPhoto,
}) => Navigator.of(context).push<void>(
  MaterialPageRoute(
    builder: (_) => _DirectChatScreen(
      peer: _ChatPeer.ai(
        id: character.id,
        publicUserId: character.publicId,
        displayName: character.name,
        subtitle: character.personality,
        photoUrl: character.avatarUrl,
        portraitAsset: character.portraitAsset,
        tint: character.tint,
        icon: character.icon,
      ),
      initialCharacter: character,
      currentUid: repository.uid,
      repository: repository,
      inbox: inbox,
      onEditPhoto: character.canEditBy(repository.uid) ? onEditPhoto : null,
      backgroundStore: backgroundStore,
      pickBackgroundPhoto: pickBackgroundPhoto,
    ),
  ),
);

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

/// Raised when someone tries to send a second message to a person who has not
/// written back yet.
class _DirectMessageLimitException implements Exception {
  const _DirectMessageLimitException(this.message);

  final String message;
}

/// Everyone who has written in a chat, from its document.
Set<String> _sendersIn(Map<String, dynamic>? chat) {
  return (chat?['senderUids'] as List<dynamic>?)?.whereType<String>().toSet() ??
      const <String>{};
}

/// Whether [currentUid] has used up their one unanswered message to the peer.
bool _isAwaitingReply({
  required Map<String, dynamic>? chat,
  required String currentUid,
  required String peerUid,
}) {
  final senders = _sendersIn(chat);
  return !senders.contains(peerUid) && senders.contains(currentUid);
}

/// The fixed id an opening message is written under. Message documents cannot
/// be updated or deleted, so this id can only ever be claimed once — which is
/// what caps an unanswered conversation at a single message.
String _introMessageId(String senderUid) => 'intro_$senderUid';

/// Appends a human-to-human message, creating the chat document on first send.
///
/// Until the other person writes back, only one message can be sent: the
/// opening one takes a fixed document id, and a second attempt is refused here
/// and by the security rules.
Future<void> _sendDirectMessage({
  required String currentUid,
  required String peerUid,
  required String text,
}) async {
  final chatRef = FirebaseFirestore.instance
      .collection('chats')
      .doc(_chatIdFor(currentUid, peerUid));

  final snapshot = await chatRef.get();
  final chat = snapshot.data();
  if (_isAwaitingReply(chat: chat, currentUid: currentUid, peerUid: peerUid)) {
    throw const _DirectMessageLimitException(
      'You can send one message until they write back.',
    );
  }

  final senders = _sendersIn(chat);
  final hasReplied = senders.contains(peerUid);
  await chatRef.set({
    'participantUids': [currentUid, peerUid]..sort(),
    // Written out in full rather than with arrayUnion: the security rules
    // compare the old and new lists element by element, which is only
    // dependable when the value being written is a plain list.
    'senderUids': <String>{...senders, currentUid}.toList()..sort(),
    'updatedAt': FieldValue.serverTimestamp(),
    'lastMessage': text,
  }, SetOptions(merge: true));

  final messages = chatRef.collection('messages');
  final messageRef = hasReplied
      ? messages.doc()
      : messages.doc(_introMessageId(currentUid));
  await messageRef.set({
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
  const ChatScreen({
    super.key,
    required this.authController,
    this.keyboardOpen = false,
    this.navVisible = true,
    this.isActive = true,
  });

  final AppAuthController authController;
  final bool keyboardOpen;
  final bool navVisible;
  final bool isActive;

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

  _ChatPage _selectedPage = _ChatPage.ai;
  bool _showAiFriends = false;
  bool _showHumanFriends = false;
  bool _isTutorSidebarOpen = false;

  /// Held here rather than inside the discovery pages so that toggling to a
  /// friends list and back returns to the same profile instead of reshuffling.
  String? _discoveryCharacterId;
  String? _discoveryContactUid;
  final _aiDiscoveryDeck = AiDiscoveryDeck();
  final _humanDiscoveryHistory = DiscoveryBrowseHistory(repeat: true);

  AiChatRepository? _repository;
  HumanFriendsRepository? _humanFriends;
  ChatInboxController? _inbox;

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
    _inbox?.removeListener(_onInboxChanged);
    _inbox?.dispose();
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
    final humanFriends = uid == null ? null : HumanFriendsRepository(uid: uid);
    _inbox?.removeListener(_onInboxChanged);
    _inbox?.dispose();
    _inbox = uid == null ? null : ChatInboxController(uid: uid);
    _inbox?.addListener(_onInboxChanged);
    _aiDiscoveryDeck.reset();
    _humanDiscoveryHistory.reset();
    if (mounted) {
      setState(() {
        _repository = repository;
        _humanFriends = humanFriends;
        _selectedTutorSessionId = null;
        _discoveryCharacterId = null;
        _discoveryContactUid = null;
      });
    } else {
      _repository = repository;
      _humanFriends = humanFriends;
      _selectedTutorSessionId = null;
      _discoveryCharacterId = null;
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

    return DiscoveryControls(
      autoHide: isDiscovery,
      navVisible: widget.navVisible && !widget.keyboardOpen,
      isActive: widget.isActive,
      child: Stack(
        children: [
          if (isAiDiscovery)
            Positioned.fill(
              child: _AiDiscoveryPage(
                repository: repository,
                recommendationDeck: _aiDiscoveryDeck,
                inbox: _inbox,
                isActive: widget.isActive,
                keyboardOpen: widget.keyboardOpen,
                navVisible: widget.navVisible,
                onToggleFriend: _toggleAiFriend,
                messageController: _aiDiscoveryMessageController,
                characterId: _discoveryCharacterId,
                onCharacterChanged: (id) {
                  setState(() => _discoveryCharacterId = id);
                },
              ),
            ),
          if (isHumanDiscovery)
            Positioned.fill(
              child: _HumanDiscoveryPage(
                friendsRepository: humanFriends,
                history: _humanDiscoveryHistory,
                inbox: _inbox,
                isActive: widget.isActive,
                keyboardOpen: widget.keyboardOpen,
                navVisible: widget.navVisible,
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
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                DiscoveryTopTabs(
                  child: _TopTabs(
                    aiUnreadCount: _inbox?.aiTotal ?? 0,
                    humanUnreadCount: _inbox?.humanTotal ?? 0,
                    selectedPage: _selectedPage,
                    isAiFriends: _showAiFriends,
                    isHumanFriends: _showHumanFriends,
                    overlay: true,
                    onChanged: _selectPage,
                  ),
                ),
                if (!isDiscovery)
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: _selectedPage == _ChatPage.tutor
                          ? Duration.zero
                          : const Duration(milliseconds: 180),
                      // Only the AI and Tutor pages need an account — the human
                      // directory still renders signed out, as it always has.
                      child: switch (_selectedPage) {
                        _ChatPage.ai =>
                          repository == null
                              ? const _SignedOutNotice(
                                  key: ValueKey(_ChatPage.ai),
                                  text:
                                      'Sign in to use the AI chats and tutor.',
                                )
                              : _AiContactsPage(
                                  key: const ValueKey(_ChatPage.ai),
                                  repository: repository,
                                  unreadCounts: _inbox?.aiCounts ?? const {},
                                  searchController: _aiSearchController,
                                  onSearchChanged: (_) => setState(() {}),
                                  onOpenCharacter: _openAiConversation,
                                  onCreateCharacter: _showAddAiCharacterDialog,
                                ),
                        _ChatPage.human => _HumanContactsPage(
                          key: const ValueKey(_ChatPage.human),
                          searchController: _humanSearchController,
                          onSearchChanged: (_) => setState(() {}),
                          currentUid: currentUid,
                          friendsRepository: humanFriends,
                          unreadCounts: _inbox?.humanCounts ?? const {},
                          onOpenContact: _openHumanConversation,
                        ),
                        _ChatPage.tutor =>
                          repository == null
                              ? const _SignedOutNotice(
                                  key: ValueKey(_ChatPage.tutor),
                                  text:
                                      'Sign in to use the AI chats and tutor.',
                                )
                              : _TutorChatPage(
                                  key: const ValueKey(_ChatPage.tutor),
                                  navVisible: widget.navVisible,
                                  keyboardOpen: widget.keyboardOpen,
                                  repository: repository,
                                  messageController: _messageController,
                                  selectedSessionId: _selectedTutorSessionId,
                                  isReplying: _isTutorReplying,
                                  onSessionResolved: _rememberTutorSession,
                                  onSessionNeeded: _ensureTutorSession,
                                  onSendMessage: _sendTutorMessage,
                                  onOpenHistory: () => setState(
                                    () => _isTutorSidebarOpen = true,
                                  ),
                                  onCloseHistory: () => setState(
                                    () => _isTutorSidebarOpen = false,
                                  ),
                                ),
                      },
                    ),
                  ),
              ],
            ),
          ),
          // The tutor history drawer overlays the entire chat screen — header,
          // tabs and all — so it dominates the screen rather than sitting beside
          // the conversation card.
          if (_selectedPage == _ChatPage.tutor && repository != null)
            SafeArea(
              bottom: false,
              child: _TutorHistoryDrawer(
                isOpen: _isTutorSidebarOpen,
                navVisible: widget.navVisible,
                keyboardOpen: widget.keyboardOpen,
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
            ),
        ],
      ),
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

  void _onInboxChanged() {
    if (mounted) setState(() {});
  }

  void _selectPage(_ChatPage page) {
    // Tapping the tab you are already on flips that tab between its discovery
    // deck and its friends list. The AI and Human tabs each keep their own.
    if (page == _selectedPage) {
      if (page == _ChatPage.tutor) return;
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

    try {
      await showAddAiCharacterDialog(
        context,
        onCreate: (draft) async {
          await repository.createCharacter(
            name: draft.name,
            personality: draft.personality,
            photo: draft.photo,
            gender: draft.gender,
            tags: draft.tags,
            isPublic: draft.isPublic,
          );
        },
      );
    } catch (error) {
      _showError('Could not create that character.');
    }
  }

  Future<void> _pickAiAvatar(AiCharacter character) async {
    final repository = _repository;
    if (repository == null) {
      return;
    }

    try {
      final photo = await AiCharacterPhoto.pickFromGallery();
      if (photo == null) return;
      await repository.updateCharacterAvatar(
        characterId: character.id,
        bytes: photo.bytes,
        contentType: photo.contentType,
      );
      final oldUrl = character.avatarUrl;
      if (oldUrl != null && oldUrl.isNotEmpty) {
        // Storage can retain the same URL when replacing a photo.
        await ResizeImage.resizeIfNeeded(
          256,
          null,
          NetworkImage(oldUrl),
        ).evict();
      }
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
        // _showError(
        //   add
        //       ? '${character.name} was added to your AI friends.'
        //       : '${character.name} was removed from your AI friends.',
        // );
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

    await openAiCharacterConversation(
      context,
      character: character,
      repository: repository,
      inbox: _inbox,
      onEditPhoto: () => _pickAiAvatar(character),
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
          inbox: _inbox,
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
    this.aiUnreadCount = 0,
    this.humanUnreadCount = 0,
  });

  final int aiUnreadCount;
  final int humanUnreadCount;
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
              child: UnreadBadge(
                count: switch (page) {
                  _ChatPage.ai => aiUnreadCount,
                  _ChatPage.human => humanUnreadCount,
                  _ChatPage.tutor => 0,
                },
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
      contextMenuBuilder: (context, editableTextState) {
        // Keep normal text editing actions without the iOS Scan Text entry.
        final items = editableTextState.contextMenuButtonItems
            .where((item) => item.type != ContextMenuButtonType.liveTextInput)
            .toList();
        if (items.isEmpty) return const SizedBox.shrink();
        return AdaptiveTextSelectionToolbar.buttonItems(
          anchors: editableTextState.contextMenuAnchors,
          buttonItems: items,
        );
      },
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
    this.unreadCounts = const {},
    required this.searchController,
    required this.onSearchChanged,
    required this.onOpenCharacter,
    required this.onCreateCharacter,
  });

  final AiChatRepository repository;
  final Map<String, int> unreadCounts;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<AiCharacter> onOpenCharacter;
  final VoidCallback onCreateCharacter;

  Future<void> _deleteChat(BuildContext context, AiCharacter character) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Delete chat?'),
        content: Text(
          'Clear your conversation with ${character.name}? Your friend and Like will stay saved.',
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) await repository.deleteCharacterChat(character.id);
  }

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
                          previews[character.id]?.isHidden != true &&
                          (character.isFriend ||
                              previews.containsKey(character.id)) &&
                          character.matches(query),
                    )
                    .toList() ??
                <AiCharacter>[];

            characters.sort((a, b) {
              final aChat = previews[a.id];
              final bChat = previews[b.id];
              if ((aChat != null) != (bChat != null)) {
                return aChat != null ? -1 : 1;
              }
              final aTime = aChat?.updatedAt;
              final bTime = bChat?.updatedAt;
              if (aTime != null && bTime != null) return bTime.compareTo(aTime);
              return a.name.toLowerCase().compareTo(b.name.toLowerCase());
            });
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: _SearchField(
                          controller: searchController,
                          hintText: 'Search AI friends or AI ID',
                          onChanged: onSearchChanged,
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox.square(
                        dimension: 48,
                        child: IconButton.filled(
                          tooltip: 'Create an AI friend',
                          onPressed: onCreateCharacter,
                          icon: const Icon(Icons.add_rounded),
                          style: IconButton.styleFrom(
                            backgroundColor: AppColors.clay,
                            foregroundColor: Colors.white,
                            shape: const CircleBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 122),
                    children: [
                      if (charactersSnapshot.connectionState ==
                          ConnectionState.waiting)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 30),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else ...[
                        for (final character in characters)
                          SwipeableChatRow(
                            key: ValueKey('${repository.uid}:${character.id}'),
                            onDelete: () => _deleteChat(context, character),
                            child: _AiCharacterTile(
                              character: character,
                              unreadCount: unreadCounts[character.id] ?? 0,
                              // A started conversation replaces the scripted preview.
                              preview: previews[character.id]?.lastMessage,
                              onOpen: () => onOpenCharacter(character),
                            ),
                          ),
                        if (characters.isEmpty)
                          const _EmptySearchResult(
                            text: 'No AI friends match this search.',
                          ),
                      ],
                    ],
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

/// Full-screen AI friend discovery with bundled artwork for every preset.
class _AiDiscoveryPage extends StatefulWidget {
  const _AiDiscoveryPage({
    required this.repository,
    required this.recommendationDeck,
    required this.keyboardOpen,
    this.navVisible = true,
    this.inbox,
    this.isActive = true,
    required this.onToggleFriend,
    required this.messageController,
    required this.characterId,
    required this.onCharacterChanged,
  });

  final AiChatRepository repository;
  final AiDiscoveryDeck recommendationDeck;
  final bool keyboardOpen;
  final bool navVisible;
  final ChatInboxController? inbox;
  final bool isActive;

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
  late DiscoveryConversationCache<AiMessage> _conversations;
  late Stream<List<AiCharacter>> _characters;
  late Stream<List<AiCharacter>> _publicCharacters;
  late Stream<Map<String, AiCharacterInteraction>> _discoveryInteractions;
  bool _isReplying = false;

  String? get _currentCharacterId => widget.characterId;
  TextEditingController get _messageController => widget.messageController;

  @override
  void initState() {
    super.initState();
    _bindRepository();
  }

  void _bindRepository() {
    _characters = widget.repository.watchCharacters();
    _publicCharacters = widget.repository.watchPublicCharacters();
    _discoveryInteractions = widget.repository.watchDiscoveryInteractions();
    _conversations = DiscoveryConversationCache<AiMessage>(
      watch: widget.repository.watchCharacterPreviewMessages,
    );
  }

  @override
  void dispose() {
    _conversations.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _AiDiscoveryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository.uid != widget.repository.uid) {
      _conversations.dispose();
      _bindRepository();
    }
  }

  void _page(int delta) {
    if (_isReplying) {
      return;
    }
    final id = widget.recommendationDeck.move(delta);
    if (id != null) widget.onCharacterChanged(id);
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
        // copy first. Sending then saves it into the AI friends list.
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
      key: ValueKey(widget.repository.uid),
      stream: _characters,
      builder: (context, snapshot) {
        return StreamBuilder<List<AiCharacter>>(
          stream: _publicCharacters,
          builder: (context, publicSnapshot) {
            return StreamBuilder<Map<String, AiCharacterInteraction>>(
              stream: _discoveryInteractions,
              builder: (context, interactionsSnapshot) {
                if ((!snapshot.hasData && !snapshot.hasError) ||
                    (!publicSnapshot.hasData && !publicSnapshot.hasError) ||
                    (!interactionsSnapshot.hasData &&
                        !interactionsSnapshot.hasError)) {
                  return const Center(child: CircularProgressIndicator());
                }
                return _buildDeck(
                  context,
                  snapshot,
                  publicSnapshot.data ?? const <AiCharacter>[],
                  interactionsSnapshot.data ?? const {},
                );
              },
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
    Map<String, AiCharacterInteraction> interactions,
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
    final discoverable = widget.recommendationDeck.resolve(
      candidates: [
        ...owned.where(
          (character) =>
              (!character.isCustom && !character.isFriend) ||
              interactions[character.id]?.isChatHidden == true,
        ),
        ...shared,
      ],
      knownCharacters: characters,
      interactions: interactions,
      currentId: _currentCharacterId,
    );
    final current = characters.where(
      (character) => character.id == _currentCharacterId,
    );
    final selected = current.isNotEmpty
        ? current.first
        : (discoverable.isNotEmpty ? discoverable.first : null);

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
        title: 'No characters available yet',
        text: 'Characters will appear here when they are available.',
      );
    }

    final currentIndex = widget.recommendationDeck.currentIndex;
    AiCharacter? neighbour(int delta) {
      if (discoverable.isEmpty) {
        return null;
      }
      final index = currentIndex + delta;
      if (index < 0 || index >= discoverable.length) return null;
      return discoverable[index];
    }

    final previous = neighbour(-1);
    final next = neighbour(1);
    _conversations.preload([
      selected.id,
      if (previous != null) previous.id,
      if (next != null) next.id,
    ]);

    Widget portraitFor(
      AiCharacter character,
      int visit, {
      bool isInteractive = true,
    }) {
      return DiscoveryConversation<AiMessage>(
        key: ValueKey((character.id, visit)),
        cache: _conversations,
        conversationId: character.id,
        builder: (context, recentMessages) {
          final isSharedTemplate = shared.any(
            (template) => template.id == character.id,
          );
          return _DiscoveryPortrait(
            key: ValueKey(character.id),
            keyboardOpen: widget.keyboardOpen,
            navVisible: widget.navVisible,
            inbox: widget.inbox,
            readKey: 'ai:${character.id}',
            isActive: widget.isActive,
            title: character.name,
            photoUrl: character.avatarUrl,
            portraitAsset: character.portraitAsset,
            tint: character.tint,
            icon: character.icon,
            isFriend: character.isFriend,
            friendsLabel: 'AI friends',
            bubbles: [
              _DiscoveryBubble(text: character.introduction),
              for (final message
                  in recentMessages.reversed.take(2).toList().reversed)
                _DiscoveryBubble(
                  text: message.text,
                  isUser: message.isUser,
                  isPending: message.isPending,
                  createdAt: message.createdAt,
                ),
              if (isInteractive && _isReplying)
                const _DiscoveryBubble(text: '', isPending: true),
            ],
            messageController: _messageController,
            isInteractive: isInteractive,
            isBusy: _isReplying,
            onToggleFriend: () => widget.onToggleFriend(
              character,
              isSharedTemplate: isSharedTemplate,
            ),
            onSendMessage: () =>
                _sendMessage(character, isSharedTemplate: isSharedTemplate),
          );
        },
      );
    }

    return SwipeableDiscoveryDeck(
      cardKey: (selected.id, currentIndex),
      frontCard: portraitFor(selected, currentIndex),
      previousCard: previous == null
          ? null
          : portraitFor(previous, currentIndex - 1, isInteractive: false),
      nextCard: next == null
          ? null
          : portraitFor(next, currentIndex + 1, isInteractive: false),
      enabled: !_isReplying && !widget.keyboardOpen,
      onSwiped: _page,
    );
  }
}

/// One line of the conversation preview printed over a discovery card.
class _DiscoveryBubble {
  const _DiscoveryBubble({
    required this.text,
    this.isUser = false,
    this.isPending = false,
    this.createdAt,
  });

  final String text;
  final bool isUser;
  final bool isPending;
  final DateTime? createdAt;
}

/// A two-card discovery stack. The front card tracks the user's finger while
/// the neighbouring card stays underneath, so swiping reveals the next person
/// instead of sliding two full-screen pages past each other.
class SwipeableDiscoveryDeck extends StatefulWidget {
  const SwipeableDiscoveryDeck({
    super.key,
    required this.cardKey,
    required this.frontCard,
    required this.previousCard,
    required this.nextCard,
    required this.onSwiped,
    required this.enabled,
  });

  final Object cardKey;
  final Widget frontCard;
  final Widget? previousCard;
  final Widget? nextCard;
  final ValueChanged<int> onSwiped;
  final bool enabled;

  @override
  State<SwipeableDiscoveryDeck> createState() => _SwipeableDiscoveryDeckState();
}

class _SwipeableDiscoveryDeckState extends State<SwipeableDiscoveryDeck>
    with SingleTickerProviderStateMixin {
  static const Duration _commitDuration = Duration(milliseconds: 230);
  static const Duration _restoreDuration = Duration(milliseconds: 190);
  static const double _velocityThreshold = 650;
  static const double _distanceThreshold = 0.22;

  late final AnimationController _animationController;
  Animation<Offset>? _offsetAnimation;
  Offset _dragOffset = Offset.zero;
  double _deckWidth = 1;
  int _revealedDirection = 1;
  int? _committedDirection;
  bool _awaitingSelection = false;

  bool get _isAnimating =>
      _animationController.isAnimating || _awaitingSelection;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(vsync: this)
      ..addListener(() {
        final animation = _offsetAnimation;
        if (animation != null && mounted) {
          setState(() => _dragOffset = animation.value);
        }
      })
      ..addStatusListener((status) {
        if (status != AnimationStatus.completed || !mounted) {
          return;
        }
        final direction = _committedDirection;
        setState(() {
          _offsetAnimation = null;
          _committedDirection = null;
          _awaitingSelection = direction != null;
          // Keep the incoming preview in place until its identity is committed.
          // Resetting now can briefly put the outgoing portrait back on top.
          if (direction == null) _dragOffset = Offset.zero;
        });
        if (direction != null) {
          widget.onSwiped(direction);
        }
      });
  }

  @override
  void didUpdateWidget(covariant SwipeableDiscoveryDeck oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.cardKey != oldWidget.cardKey) {
      _animationController.stop();
      _offsetAnimation = null;
      _committedDirection = null;
      _awaitingSelection = false;
      _dragOffset = Offset.zero;
      _revealedDirection = 1;
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _handleDragStart(DragStartDetails details) {
    if (!widget.enabled || _isAnimating) {
      return;
    }
    FocusScope.of(context).unfocus();
    _offsetAnimation = null;
    _committedDirection = null;
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    if (!widget.enabled || _isAnimating) {
      return;
    }
    final nextDx = _dragOffset.dx + details.delta.dx;
    setState(() {
      _dragOffset = Offset(nextDx, 0);
      if (nextDx != 0) {
        _revealedDirection = nextDx < 0 ? 1 : -1;
      }
    });
  }

  void _handleDragEnd(DragEndDetails details) {
    if (!widget.enabled || _isAnimating) {
      return;
    }
    final velocity = details.primaryVelocity ?? 0;
    final predictedDx = _dragOffset.dx + velocity * 0.12;
    final direction = predictedDx < 0 ? 1 : -1;
    final hasCard = direction > 0
        ? widget.nextCard != null
        : widget.previousCard != null;
    final shouldCommit =
        hasCard &&
        (_dragOffset.dx.abs() >= _deckWidth * _distanceThreshold ||
            velocity.abs() >= _velocityThreshold);

    if (!shouldCommit) {
      _animateOffset(Offset.zero, duration: _restoreDuration);
      return;
    }

    _revealedDirection = direction;
    _committedDirection = direction;
    final sign = direction > 0 ? -1.0 : 1.0;
    _animateOffset(
      Offset(sign * (_deckWidth + 120), 0),
      duration: _commitDuration,
    );
  }

  void _animateOffset(Offset target, {required Duration duration}) {
    _animationController
      ..duration = duration
      ..reset();
    _offsetAnimation = Tween<Offset>(begin: _dragOffset, end: target).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutCubic),
    );
    _animationController.forward();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _deckWidth = math.max(1, constraints.maxWidth).toDouble();
        final progress = (_dragOffset.dx.abs() / (_deckWidth * 0.6))
            .clamp(0.0, 1.0)
            .toDouble();
        final cardUnder = _revealedDirection > 0
            ? widget.nextCard
            : widget.previousCard;
        final angle = (_dragOffset.dx / _deckWidth).clamp(-1.0, 1.0) * 0.09;

        Widget layer(Widget card, {required bool isFront}) => IgnorePointer(
          // The preview and front card occupy the same keyed layer structure.
          // Promoting a card retains its decoded portrait and message state.
          key: ValueKey((
            #discoveryCardLayer,
            card.key ?? (isFront ? widget.cardKey : _revealedDirection),
          )),
          ignoring: !isFront,
          child: Transform.translate(
            offset: isFront ? _dragOffset : Offset.zero,
            child: Transform.rotate(
              angle: isFront ? angle : 0,
              alignment: Alignment.topCenter,
              child: Transform.scale(
                scale: isFront ? 1 : 0.96 + progress * 0.04,
                child: Opacity(
                  opacity: isFront ? 1 : 0.82 + progress * 0.18,
                  child: card,
                ),
              ),
            ),
          ),
        );

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => FocusScope.of(context).unfocus(),
          onHorizontalDragStart: widget.enabled ? _handleDragStart : null,
          onHorizontalDragUpdate: widget.enabled ? _handleDragUpdate : null,
          onHorizontalDragEnd: widget.enabled ? _handleDragEnd : null,
          onHorizontalDragCancel: !widget.enabled
              ? null
              : () {
                  if (!_isAnimating) {
                    _animateOffset(Offset.zero, duration: _restoreDuration);
                  }
                },
          child: ClipRect(
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (cardUnder != null) layer(cardUnder, isFront: false),
                layer(widget.frontCard, isFront: true),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The full-bleed "meet someone" card. Shared by the AI and Human decks, which
/// differ only in where their portrait, bubbles and friend state come from.
class _DiscoveryPortrait extends StatelessWidget {
  const _DiscoveryPortrait({
    super.key,
    required this.title,
    required this.keyboardOpen,
    this.navVisible = true,
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
    this.bio,
    this.portraitAsset,
    this.isInteractive = true,
    this.inbox,
    this.readKey,
    this.isActive = true,
  });

  final String title;
  final bool keyboardOpen;
  final bool navVisible;
  final String? subtitle;
  final String? bio;
  final String? photoUrl;
  final String? portraitAsset;
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
  final bool isInteractive;
  final ChatInboxController? inbox;
  final String? readKey;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return DiscoveryCardSurface(
      background: Stack(
        fit: StackFit.expand,
        children: [
          CharacterPortrait(
            photoUrl: photoUrl,
            assetPath: portraitAsset,
            semanticLabel: title,
            fallback: DecoratedBox(
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
        ],
      ),
      foreground: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            top: 76,
            left: 18,
            child: DiscoveryControlVisibility(
              child: _DiscoveryHeartButton(
                isFriend: isFriend,
                friendsLabel: friendsLabel,
                onPressed: onToggleFriend,
              ),
            ),
          ),
          DiscoveryCardContent(
            keyboardOpen: keyboardOpen,
            navVisible: navVisible,
            controller: messageController,
            isReplying: isBusy,
            isInteractive: isInteractive,
            onSendMessage: onSendMessage,
            conversation: Column(
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
                if (bio != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    bio!,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.white.withValues(alpha: 0.94),
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                      shadows: const [
                        Shadow(color: Colors.black54, blurRadius: 8),
                      ],
                    ),
                  ),
                ],
                for (final (index, bubble) in bubbles.indexed) ...[
                  const SizedBox(height: 8),
                  VisibleChatReadReceipt(
                    key: ValueKey('$readKey:$index'),
                    through: bubble.createdAt,
                    enabled:
                        isActive &&
                        isInteractive &&
                        !bubble.isUser &&
                        !bubble.isPending,
                    onRead: (date) => inbox != null && readKey != null
                        ? inbox!.markRead(readKey!, date)
                        : Future<void>.value(),
                    child: _DiscoveryChatBubble(
                      text: bubble.text,
                      isUser: bubble.isUser,
                      isPending: bubble.isPending,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
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
      child: CopyableMessage(
        text: text,
        enabled: !isPending,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 360),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isUser
                ? AppColors.clay.withValues(alpha: 0.60)
                : Colors.white.withValues(alpha: 0.56),
            borderRadius: BorderRadius.circular(20),
          ),
          child: isPending
              ? const _TypingIndicator()
              : Text(
                  text,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: isUser ? Colors.white : AppColors.ink,
                    height: 1.35,
                  ),
                ),
        ),
      ),
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
    required this.history,
    required this.keyboardOpen,
    this.navVisible = true,
    this.inbox,
    this.isActive = true,
    required this.currentUid,
    required this.messageController,
    required this.contactUid,
    required this.onContactChanged,
  });

  final HumanFriendsRepository friendsRepository;
  final DiscoveryBrowseHistory history;
  final bool keyboardOpen;
  final bool navVisible;
  final ChatInboxController? inbox;
  final bool isActive;
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
  late DiscoveryConversationCache<QueryDocumentSnapshot<Map<String, dynamic>>>
  _conversations;
  late Stream<Set<String>> _friends;
  late Stream<QuerySnapshot<Map<String, dynamic>>> _users;
  final math.Random _random = math.Random();
  bool _isSending = false;

  String? get _currentContactUid => widget.contactUid;
  TextEditingController get _messageController => widget.messageController;

  @override
  void initState() {
    super.initState();
    _bindConversations();
  }

  void _bindConversations() {
    final uid = widget.currentUid;
    _friends = widget.friendsRepository.watchFriendUids();
    _users = FirebaseFirestore.instance.collection('users').snapshots();
    _conversations = DiscoveryConversationCache(
      watch: (peerUid) => FirebaseFirestore.instance
          .collection('chats')
          .doc(_chatIdFor(uid, peerUid))
          .collection('messages')
          .orderBy('createdAt', descending: true)
          .limit(2)
          .snapshots()
          .map((snapshot) => snapshot.docs),
    );
  }

  @override
  void didUpdateWidget(covariant _HumanDiscoveryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentUid != widget.currentUid) {
      _conversations.dispose();
      _bindConversations();
    }
  }

  @override
  void dispose() {
    _conversations.dispose();
    super.dispose();
  }

  void _page(int delta) {
    if (_isSending) {
      return;
    }
    final uid = widget.history.move(delta);
    if (uid != null) widget.onContactChanged(uid);
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
              content: Text('Saved. You are now following ${contact.name}.'),
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
    } on _DirectMessageLimitException catch (error) {
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
        setState(() => _isSending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Set<String>>(
      key: ValueKey(widget.currentUid),
      stream: _friends,
      builder: (context, friendsSnapshot) {
        final friendUids = friendsSnapshot.data ?? const <String>{};

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _users,
          builder: (context, usersSnapshot) {
            if ((!usersSnapshot.hasData && !usersSnapshot.hasError) ||
                (!friendsSnapshot.hasData && !friendsSnapshot.hasError)) {
              return const Center(child: CircularProgressIndicator());
            }
            final contacts =
                usersSnapshot.data?.docs
                    .where((doc) => doc.id != widget.currentUid)
                    .map(_HumanContact.fromUserDoc)
                    .toList() ??
                const <_HumanContact>[];
            final byUid = {
              for (final contact in contacts) contact.uid: contact,
            };
            final discoverable = widget.history
                .resolve(
                  candidates: contacts
                      .where((contact) => !friendUids.contains(contact.uid))
                      .map((contact) => contact.uid),
                  available: byUid.keys,
                  currentId: _currentContactUid,
                  orderUnseen: (ids) => ids..shuffle(_random),
                )
                .map((uid) => byUid[uid]!)
                .toList();

            final current = contacts.where(
              (contact) => contact.uid == _currentContactUid,
            );
            final selected = current.isNotEmpty
                ? current.first
                : (discoverable.isNotEmpty ? discoverable.first : null);

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
                title: 'No people available yet',
                text: 'People will appear here when they are available.',
              );
            }

            final currentIndex = widget.history.currentIndex;
            _HumanContact? neighbour(int delta) {
              if (discoverable.isEmpty) {
                return null;
              }
              final index = currentIndex + delta;
              if (index < 0 || index >= discoverable.length) return null;
              return discoverable[index];
            }

            final previous = neighbour(-1);
            final next = neighbour(1);
            _conversations.preload([
              selected.uid,
              if (previous != null) previous.uid,
              if (next != null) next.uid,
            ]);
            Widget portraitFor(
              _HumanContact contact,
              int visit, {
              bool isInteractive = true,
            }) {
              return DiscoveryConversation<
                QueryDocumentSnapshot<Map<String, dynamic>>
              >(
                key: ValueKey((contact.uid, visit)),
                cache: _conversations,
                conversationId: contact.uid,
                builder: (context, recentMessages) {
                  final contactIsFriend = friendUids.contains(contact.uid);
                  return _DiscoveryPortrait(
                    key: ValueKey(contact.uid),
                    keyboardOpen: widget.keyboardOpen,
                    navVisible: widget.navVisible,
                    inbox: widget.inbox,
                    readKey:
                        'human:${_chatIdFor(widget.currentUid, contact.uid)}',
                    isActive: widget.isActive,
                    title: contact.name,
                    subtitle: contact.handle,
                    bio: contact.bio,
                    photoUrl: contact.photoUrl,
                    tint: contact.tint,
                    icon: Icons.person_rounded,
                    isFriend: contactIsFriend,
                    friendsLabel: 'your people',
                    bubbles: [
                      for (final doc in recentMessages.reversed)
                        _DiscoveryBubble(
                          text: (doc.data()['text'] as String?)?.trim() ?? '',
                          createdAt: (doc.data()['createdAt'] as Timestamp?)
                              ?.toDate(),
                          isUser: doc.data()['senderUid'] == widget.currentUid,
                        ),
                    ],
                    messageController: _messageController,
                    isInteractive: isInteractive,
                    isBusy: _isSending,
                    onToggleFriend: () =>
                        _toggleFriend(contact, isFriend: contactIsFriend),
                    onSendMessage: () => _sendMessage(contact),
                  );
                },
              );
            }

            return SwipeableDiscoveryDeck(
              cardKey: (selected.uid, currentIndex),
              frontCard: portraitFor(selected, currentIndex),
              previousCard: previous == null
                  ? null
                  : portraitFor(previous, currentIndex - 1, isInteractive: false),
              nextCard: next == null
                  ? null
                  : portraitFor(next, currentIndex + 1, isInteractive: false),
              enabled: !_isSending && !widget.keyboardOpen,
              onSwiped: _page,
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
    this.unreadCounts = const {},
  });

  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final String? currentUid;

  /// Null when signed out, in which case the tab falls back to listing the
  /// whole directory the way it did before friends lists existed.
  final HumanFriendsRepository? friendsRepository;
  final ValueChanged<_HumanContact> onOpenContact;
  final Map<String, int> unreadCounts;

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
                          ? 'Search app users or User ID'
                          : 'Search your people or User ID',
                      onChanged: onSearchChanged,
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
                          unreadCount: unreadCounts[contact.uid] ?? 0,
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

double _tutorBottomInset(
  BuildContext context, {
  required bool navVisible,
  required bool keyboardOpen,
}) {
  if (keyboardOpen) return 12;
  final safeBottom = MediaQuery.viewPaddingOf(context).bottom;
  return navVisible ? math.max(100.0, safeBottom + 84) : safeBottom + 12;
}

class _TutorChatPage extends StatelessWidget {
  const _TutorChatPage({
    super.key,
    required this.navVisible,
    required this.keyboardOpen,
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

  final bool navVisible;
  final bool keyboardOpen;
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
      child: AnimatedPadding(
        duration: Duration(
          milliseconds: keyboardOpen
              ? 0
              : navVisible
              ? 260
              : 380,
        ),
        curve: Curves.easeInOutCubic,
        padding: EdgeInsets.fromLTRB(
          16,
          4,
          16,
          _tutorBottomInset(
            context,
            navVisible: navVisible,
            keyboardOpen: keyboardOpen,
          ),
        ),
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
    required this.navVisible,
    required this.keyboardOpen,
    required this.repository,
    required this.searchController,
    required this.selectedSessionId,
    required this.onSearchChanged,
    required this.onSessionSelected,
    required this.onDeleteSession,
    required this.onClose,
  });

  final bool isOpen;
  final bool navVisible;
  final bool keyboardOpen;
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
                  navVisible: navVisible,
                  keyboardOpen: keyboardOpen,
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
    required this.navVisible,
    required this.keyboardOpen,
    required this.repository,
    required this.searchController,
    required this.selectedSessionId,
    required this.compact,
    required this.onSearchChanged,
    required this.onSessionSelected,
    required this.onDeleteSession,
    required this.onCollapse,
  });

  final bool navVisible;
  final bool keyboardOpen;
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
      child: AnimatedPadding(
        duration: Duration(
          milliseconds: keyboardOpen
              ? 0
              : navVisible
              ? 260
              : 380,
        ),
        curve: Curves.easeInOutCubic,
        padding: EdgeInsets.fromLTRB(
          16,
          18,
          16,
          _tutorBottomInset(
            context,
            navVisible: navVisible,
            keyboardOpen: keyboardOpen,
          ),
        ),
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
    required this.onOpen,
    this.unreadCount = 0,
  });

  final AiCharacter character;
  final String? preview;
  final VoidCallback onOpen;
  final int unreadCount;

  @override
  Widget build(BuildContext context) {
    final lastMessage = preview?.trim() ?? '';

    return _ChatRow(
      onTap: onOpen,
      unreadCount: unreadCount,
      avatar: _AvatarBox(
        color: character.tint,
        icon: character.icon,
        photoUrl: character.avatarUrl,
        portraitAsset: character.portraitAsset,
      ),
      title: character.name,
      subtitle: lastMessage.isEmpty ? character.preview : lastMessage,
    );
  }
}

class _HumanContactTile extends StatelessWidget {
  const _HumanContactTile({
    required this.contact,
    required this.onOpen,
    this.unreadCount = 0,
  });

  final _HumanContact contact;
  final VoidCallback onOpen;
  final int unreadCount;

  @override
  Widget build(BuildContext context) {
    return _ChatRow(
      onTap: onOpen,
      unreadCount: unreadCount,
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
    this.meta,
    this.trailing,
    this.unreadCount = 0,
  });

  final VoidCallback onTap;
  final Widget avatar;
  final String title;
  final String subtitle;
  final String? meta;
  final Widget? trailing;
  final int unreadCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
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
                child: UnreadBadge(count: unreadCount, child: avatar),
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
                          if (meta != null) const SizedBox(width: 8),
                          if (meta != null)
                            Flexible(
                              child: Text(
                                meta!,
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
                          if (trailing != null) ...[
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 76,
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: trailing,
                              ),
                            ),
                          ],
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

class _AvatarBox extends StatelessWidget {
  const _AvatarBox({
    required this.color,
    required this.icon,
    this.photoUrl,
    this.portraitAsset,
  });

  final Color color;
  final IconData icon;
  final String? photoUrl;
  final String? portraitAsset;

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
          child: CharacterPortrait(
            photoUrl: photoUrl,
            assetPath: portraitAsset,
            assetAlignment: const Alignment(0, -0.75),
            cacheWidth: 256,
            fallback: Icon(icon, color: AppColors.ink, size: 29),
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
      child: CopyableMessage(
        text: message.text,
        enabled: !message.isPending,
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
    return Semantics(
      label: 'AI is replying',
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(3, (index) {
              // Stagger a soft bounce and fade across the three dots.
              final phase = (_controller.value - index * 0.2) % 1.0;
              final pulse = math.max(0.0, math.sin(phase * math.pi * 2));
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                child: Opacity(
                  opacity: 0.35 + 0.65 * pulse,
                  child: Transform.translate(
                    offset: Offset(0, -3 * pulse),
                    child: Container(
                      height: 7,
                      width: 7,
                      decoration: const BoxDecoration(
                        color: AppColors.muted,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}

class _DirectChatScreen extends StatefulWidget {
  const _DirectChatScreen({
    required this.peer,
    required this.currentUid,
    this.repository,
    this.inbox,
    this.humanFriends,
    this.onEditPhoto,
    this.initialCharacter,
    this.backgroundStore,
    this.pickBackgroundPhoto,
  });

  final _ChatPeer peer;
  final AiCharacter? initialCharacter;
  final ChatBackgroundStore? backgroundStore;
  final Future<AiCharacterPhoto?> Function()? pickBackgroundPhoto;
  final Future<void> Function()? onEditPhoto;
  final String? currentUid;

  /// Present for AI peers, whose turns are produced by a Cloud Function.
  final AiChatRepository? repository;
  final ChatInboxController? inbox;

  /// Present for human peers when signed in, so the heart can toggle them.
  final HumanFriendsRepository? humanFriends;

  @override
  State<_DirectChatScreen> createState() => _DirectChatScreenState();
}

class _DirectChatScreenState extends State<_DirectChatScreen> {
  final _controller = TextEditingController();
  late final _characterStream = widget.peer.isAi
      ? widget.repository?.watchCharacter(widget.peer.id)
      : null;
  late final _aiMessagesStream = widget.peer.isAi
      ? widget.repository?.watchCharacterMessages(widget.peer.id)
      : null;
  late final _humanChatStream = !widget.peer.isAi && widget.currentUid != null
      ? FirebaseFirestore.instance
            .collection('chats')
            .doc(_chatIdFor(widget.currentUid!, widget.peer.id))
            .snapshots()
      : null;
  late final _humanMessagesStream =
      !widget.peer.isAi && widget.currentUid != null
      ? FirebaseFirestore.instance
            .collection('chats')
            .doc(_chatIdFor(widget.currentUid!, widget.peer.id))
            .collection('messages')
            .orderBy('createdAt')
            .snapshots()
      : null;
  late final _humanFriendStream = widget.humanFriends?.watchIsFriend(
    widget.peer.id,
  );
  late final _backgroundStore = widget.backgroundStore ?? ChatBackgroundStore();
  late ChatBackgroundChoice _background = ChatBackgroundChoice(
    widget.peer.isAi ? ChatBackgroundMode.portrait : ChatBackgroundMode.plain,
  );
  late final Future<void> _backgroundReady = _restoreBackground();
  bool _isUpdatingBackground = false;
  bool _isUpdatingPhoto = false;
  int _photoRevision = 0;

  /// True while `chatWithCharacter` is in flight.
  bool _isReplying = false;

  /// True while the friend toggle is being written, so a double tap cannot
  /// queue two conflicting writes.
  bool _isUpdatingFriend = false;

  Future<void> _restoreBackground() async {
    try {
      final choice = await _backgroundStore.load(
        uid: widget.currentUid ?? 'signed-out',
        isAi: widget.peer.isAi,
        peerId: widget.peer.id,
      );
      if (mounted) setState(() => _background = choice);
    } catch (_) {
      // Keep the default appearance if local preferences are unavailable.
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    unawaited(_backgroundReady);
    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: AppBar(
        backgroundColor: AppColors.card.withValues(alpha: 0.94),
        foregroundColor: AppColors.ink,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 0,
        // The action slot belongs to the heart for AI friends, so the profile
        // moves onto the name itself.
        title: StreamBuilder<AiCharacter?>(
          stream: _characterStream,
          initialData: widget.initialCharacter,
          builder: (context, snapshot) => Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => _showPeerProfile(snapshot.data),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 4,
                    ),
                    child: Row(
                      children: [
                        _PeerAvatar(
                          key: ValueKey(_photoRevision),
                          peer: widget.peer,
                          size: 36,
                          character: snapshot.data,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            snapshot.data?.name ?? widget.peer.displayName,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Chat background',
                onPressed: _isUpdatingBackground
                    ? null
                    : () => _changeBackground(snapshot.data),
                icon: const Icon(Icons.wallpaper_outlined),
              ),
            ],
          ),
        ),
        actions: [_buildAppBarAction()],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          StreamBuilder<AiCharacter?>(
            stream: _characterStream,
            initialData: widget.initialCharacter,
            builder: (context, snapshot) => ChatBackground(
              choice: _background,
              photoUrl: snapshot.data?.avatarUrl ?? widget.peer.photoUrl,
              portraitAsset:
                  snapshot.data?.portraitAsset ?? widget.peer.portraitAsset,
            ),
          ),
          Column(
            children: [
              Expanded(child: _buildMessages()),
              _buildComposer(),
            ],
          ),
        ],
      ),
    );
  }

  /// Ownership controls stay visible; profiles open by tapping the name.
  Widget _buildAppBarAction() {
    final repository = widget.repository;
    final humanFriends = widget.humanFriends;

    if (!widget.peer.isAi) {
      if (humanFriends == null) {
        return const SizedBox.shrink();
      }
      return StreamBuilder<bool>(
        stream: _humanFriendStream,
        builder: (context, snapshot) {
          return _buildHeartButton(
            isFriend: snapshot.data ?? false,
            friendsLabel: 'your people',
          );
        },
      );
    }

    if (repository == null) {
      return const SizedBox.shrink();
    }

    return StreamBuilder<AiCharacter?>(
      stream: _characterStream,
      initialData: widget.initialCharacter,
      builder: (context, snapshot) {
        final character = snapshot.data;
        if (character == null) {
          return const SizedBox.shrink();
        }
        if (character.canEditBy(repository.uid)) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.onEditPhoto != null)
                IconButton(
                  tooltip: 'Change photo',
                  onPressed: _isUpdatingPhoto ? null : _changePhoto,
                  icon: _isUpdatingPhoto
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add_a_photo_outlined),
                ),
              IconButton(
                tooltip: 'Edit character',
                onPressed: () => _editCharacter(character),
                icon: const Icon(Icons.edit_outlined),
              ),
            ],
          );
        }
        return _buildHeartButton(
          isFriend: character.isFriend,
          friendsLabel: 'AI friends',
        );
      },
    );
  }

  Future<void> _changePhoto() async {
    if (_isUpdatingPhoto || widget.onEditPhoto == null) return;
    setState(() => _isUpdatingPhoto = true);
    try {
      await widget.onEditPhoto!();
    } finally {
      if (mounted) {
        setState(() {
          _isUpdatingPhoto = false;
          _photoRevision++;
        });
      }
    }
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

  Future<void> _editCharacter(AiCharacter character) =>
      showEditAiCharacterDialog(
        context,
        character: character,
        onSave: (name, personality) =>
            widget.repository!.updateCharacterDetails(
              characterId: character.id,
              name: name,
              personality: personality,
            ),
      );

  Future<void> _changeBackground(AiCharacter? character) async {
    if (_isUpdatingBackground) return;
    FocusScope.of(context).unfocus();
    setState(() => _isUpdatingBackground = true);
    try {
      await _backgroundReady;
      if (!mounted) return;
      final url = character?.avatarUrl ?? widget.peer.photoUrl;
      final asset = character?.portraitAsset ?? widget.peer.portraitAsset;
      final action = await showChatBackgroundPicker(
        context,
        selected: _background.mode,
        isAi: widget.peer.isAi,
        hasPortrait: (url != null && url.trim().isNotEmpty) || asset != null,
      );
      if (action == null || !mounted) return;
      final photo = action == ChatBackgroundAction.choosePhoto
          ? await (widget.pickBackgroundPhoto ??
                AiCharacterPhoto.pickFromGallery)()
          : null;
      if (action == ChatBackgroundAction.choosePhoto && photo == null) return;
      if (!mounted) return;
      final choice = await _backgroundStore.save(
        uid: widget.currentUid ?? 'signed-out',
        isAi: widget.peer.isAi,
        peerId: widget.peer.id,
        mode: switch (action) {
          ChatBackgroundAction.portrait => ChatBackgroundMode.portrait,
          ChatBackgroundAction.choosePhoto => ChatBackgroundMode.photo,
          ChatBackgroundAction.plain => ChatBackgroundMode.plain,
        },
        photo: photo?.bytes,
      );
      if (mounted) setState(() => _background = choice);
    } on FormatException catch (error) {
      _showError(error.message);
    } catch (_) {
      _showError('Could not change the background. Please try again.');
    } finally {
      if (mounted) setState(() => _isUpdatingBackground = false);
    }
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

  /// Human conversations swap the composer for a notice once the one opening
  /// message has been sent and is still unanswered.
  Widget _buildComposer() {
    final currentUid = widget.currentUid;
    if (widget.peer.isAi || currentUid == null) {
      return _MessageComposer(
        controller: _controller,
        onSend: _sendMessage,
        isBusy: _isReplying,
      );
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _humanChatStream,
      builder: (context, snapshot) {
        final isAwaitingReply = _isAwaitingReply(
          chat: snapshot.data?.data(),
          currentUid: currentUid,
          peerUid: widget.peer.id,
        );
        if (isAwaitingReply) {
          return _AwaitingReplyNotice(name: widget.peer.displayName);
        }
        return _MessageComposer(
          controller: _controller,
          onSend: _sendMessage,
          isBusy: _isReplying,
        );
      },
    );
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
      stream: _humanMessagesStream,
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
          return _emptyConversationNotice(
            Text(
              'Start a conversation with ${widget.peer.displayName}.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          );
        }

        return _MessageList(
          messages: messages,
          inbox: widget.inbox,
          readKey: 'human:${_chatIdFor(currentUid, widget.peer.id)}',
        );
      },
    );
  }

  Widget _buildAiMessages() {
    final repository = widget.repository;
    if (repository == null) {
      return const Center(child: Text('Sign in to start chatting.'));
    }

    return StreamBuilder<List<AiMessage>>(
      stream: _aiMessagesStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final messages = snapshot.data ?? const <AiMessage>[];
        if (messages.isEmpty && !_isReplying) {
          return _emptyConversationNotice(
            StreamBuilder<AiCharacter?>(
              stream: _characterStream,
              initialData: widget.initialCharacter,
              builder: (context, character) => Text(
                'Hi, I am ${character.data?.name ?? widget.peer.displayName}. '
                'What do you want to talk through?',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          );
        }

        return _MessageList(
          inbox: widget.inbox,
          readKey: 'ai:${widget.peer.id}',
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

  Widget _emptyConversationNotice(Widget text) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: _background.mode == ChatBackgroundMode.plain
          ? text
          : Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.94),
                borderRadius: BorderRadius.circular(16),
              ),
              child: text,
            ),
    ),
  );

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

    try {
      await _sendDirectMessage(
        currentUid: currentUid,
        peerUid: widget.peer.id,
        text: text,
      );
    } on _DirectMessageLimitException catch (error) {
      _showError(error.message);
    } catch (_) {
      _showError('Could not send that message.');
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

  void _showPeerProfile(AiCharacter? currentCharacter) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.cream,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => StreamBuilder<AiCharacter?>(
        stream: _characterStream,
        // A new listener on the broadcast stream may not replay its last
        // event. Start with the same current character the header is showing.
        initialData: currentCharacter,
        builder: (context, snapshot) {
          final character = snapshot.data;
          final repository = widget.repository;
          return _PeerProfileSheet(
            peer: widget.peer,
            character: character,
            onEdit:
                character != null &&
                    repository != null &&
                    character.canEditBy(repository.uid)
                ? () => _editCharacter(character)
                : null,
          );
        },
      ),
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
  const _MessageList({required this.messages, this.inbox, this.readKey});

  final List<_DirectMessage> messages;
  final ChatInboxController? inbox;
  final String? readKey;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
      // Anchored to the bottom so a new reply is visible without scrolling.
      reverse: true,
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final message = messages[messages.length - 1 - index];
        return VisibleChatReadReceipt(
          through: message.sentAt,
          enabled: !message.isMine && !message.isPending,
          onRead: (date) => inbox != null && readKey != null
              ? inbox!.markRead(readKey!, date)
              : Future<void>.value(),
          child: Align(
            alignment: message.isMine
                ? Alignment.centerRight
                : Alignment.centerLeft,
            child: CopyableMessage(
              text: message.text,
              enabled: !message.isPending,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 290),
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 11,
                ),
                decoration: BoxDecoration(
                  color: message.isMine ? AppColors.blush : Colors.white,
                  borderRadius: BorderRadius.circular(17),
                  border: Border.all(color: AppColors.stroke),
                ),
                child: message.isPending
                    ? const _TypingIndicator()
                    : Text(message.text),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Stands in for the composer while an opening message goes unanswered.
class _AwaitingReplyNotice extends StatelessWidget {
  const _AwaitingReplyNotice({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(top: BorderSide(color: AppColors.stroke)),
      ),
      child: Row(
        children: [
          const Icon(Icons.hourglass_bottom_rounded, color: AppColors.muted),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Your message was sent. You can write again once $name '
              'replies.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
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
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final bottom = keyboardOpen
        ? 14.0
        : math.max(8.0, MediaQuery.viewPaddingOf(context).bottom - 16) + 6;
    return Container(
      key: const ValueKey('direct-chat-composer'),
      padding: EdgeInsets.fromLTRB(12, 10, 12, bottom),
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
                fillColor: Colors.white.withValues(alpha: 0.94),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(32),
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
  const _PeerProfileSheet({required this.peer, this.character, this.onEdit});

  final _ChatPeer peer;
  final AiCharacter? character;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final name = character?.name ?? peer.displayName;
    final url = character?.avatarUrl ?? peer.photoUrl;
    final asset = character?.portraitAsset ?? peer.portraitAsset;
    final ImageProvider? photo = url != null && url.trim().isNotEmpty
        ? NetworkImage(url)
        : asset != null
        ? AssetImage(asset)
        : null;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      child: SingleChildScrollView(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 22, 24, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Semantics(
                  button: photo != null,
                  label: 'View $name photo',
                  child: GestureDetector(
                    onTap: photo == null
                        ? null
                        : () => showFullscreenPhoto(
                            context,
                            image: photo,
                            label: name,
                          ),
                    child: _PeerAvatar(
                      peer: peer,
                      size: 74,
                      character: character,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  name,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 6),
                Text(
                  character?.personality ?? peer.subtitle,
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
                          peer.isAi ? 'AI ID' : 'User ID',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      Text(
                        character?.publicId ?? peer.publicUserId,
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                if (onEdit != null) ...[
                  const SizedBox(height: 14),
                  OutlinedButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Edit character'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PeerAvatar extends StatelessWidget {
  const _PeerAvatar({
    super.key,
    required this.peer,
    required this.size,
    this.character,
  });

  final _ChatPeer peer;
  final AiCharacter? character;
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
      child: CharacterPortrait(
        photoUrl: character?.avatarUrl ?? peer.photoUrl,
        assetPath: peer.portraitAsset,
        assetAlignment: const Alignment(0, -0.75),
        cacheWidth: 256,
        semanticLabel: peer.displayName,
        fallback: Icon(peer.icon, color: AppColors.ink, size: size * 0.48),
      ),
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
    this.portraitAsset,
  });

  factory _ChatPeer.ai({
    required String id,
    required String publicUserId,
    required String displayName,
    required String subtitle,
    required Color tint,
    required IconData icon,
    String? photoUrl,
    String? portraitAsset,
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
      portraitAsset: portraitAsset,
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
  final String? portraitAsset;
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
    required this.bio,
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
  final String? bio;
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
      bio: bio,
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
    final bio = _readString(data['bio']);
    final name = displayName ?? email ?? phone ?? 'Back Home user';
    final handle = email ?? phone ?? '@${doc.id.substring(0, 6)}';

    return _HumanContact(
      uid: doc.id,
      userId: _publicUserIdForUid(doc.id),
      name: name,
      handle: handle,
      preview: 'Tap to start a conversation',
      bio: bio,
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
