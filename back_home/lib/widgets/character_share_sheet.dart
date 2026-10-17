import 'package:flutter/material.dart';

import '../chat/ai_chat_repository.dart';
import '../chat/ai_models.dart';
import '../chat/character_share.dart';
import 'app_ui.dart';
import 'character_portrait.dart';

const _shareSheetShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
);

Future<CharacterShareRecipient?> showCharacterShareSheet(
  BuildContext context, {
  required AiCharacter character,
  required AiChatRepository repository,
}) => showModalBottomSheet<CharacterShareRecipient>(
  context: context,
  isScrollControlled: true,
  backgroundColor: AppColors.cream,
  shape: _shareSheetShape,
  builder: (_) =>
      _CharacterShareSheet(character: character, repository: repository),
);

class _CharacterShareSheet extends StatefulWidget {
  const _CharacterShareSheet({
    required this.character,
    required this.repository,
  });
  final AiCharacter character;
  final AiChatRepository repository;
  @override
  State<_CharacterShareSheet> createState() => _CharacterShareSheetState();
}

class _CharacterShareSheetState extends State<_CharacterShareSheet> {
  late Future<List<CharacterShareRecipient>> _recipients = widget.repository
      .loadShareRecipients(widget.character.id);
  bool _ai = true;
  String _query = '';

  Future<void> _select(CharacterShareRecipient recipient) async {
    FocusScope.of(context).unfocus();
    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: AppColors.cream,
      shape: _shareSheetShape,
      builder: (_) => _CharacterShareConfirmation(
        character: widget.character,
        recipient: recipient,
        repository: widget.repository,
      ),
    );
    if (sent == true && mounted) Navigator.of(context).pop(recipient);
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 12,
      ),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.72,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Select chat',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Close sharing',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            Row(
              children: [
                for (final isAi in [true, false])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(isAi ? 'AI friends' : 'People'),
                      selected: _ai == isAi,
                      onSelected: (_) => setState(() => _ai = isAi),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              onChanged: (value) =>
                  setState(() => _query = value.toLowerCase().trim()),
              decoration: const InputDecoration(
                hintText: 'Search recipients',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
            Expanded(
              child: FutureBuilder<List<CharacterShareRecipient>>(
                future: _recipients,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(
                      child: TextButton(
                        onPressed: () => setState(() {
                          _recipients = widget.repository.loadShareRecipients(
                            widget.character.id,
                          );
                        }),
                        child: const Text('Could not load recipients. Retry'),
                      ),
                    );
                  }
                  if (!snapshot.hasData)
                    return const Center(child: CircularProgressIndicator());
                  final recipients = snapshot.data!
                      .where(
                        (r) =>
                            r.isAi == _ai &&
                            r.name.toLowerCase().contains(_query),
                      )
                      .toList();
                  if (recipients.isEmpty)
                    return const Center(child: Text('No recipients yet.'));
                  return ListView.builder(
                    itemCount: recipients.length,
                    itemBuilder: (context, index) {
                      final recipient = recipients[index];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: _RecipientAvatar(recipient: recipient),
                        title: Text(
                          recipient.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => _select(recipient),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _RecipientAvatar extends StatelessWidget {
  const _RecipientAvatar({required this.recipient});
  final CharacterShareRecipient recipient;
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(12),
    child: SizedBox(
      width: 44,
      height: 44,
      child: CharacterPortrait(
        photoUrl: recipient.photoUrl,
        assetPath: recipient.portraitAsset,
        fallback: Icon(
          recipient.isAi ? Icons.auto_awesome : Icons.person_outline,
        ),
      ),
    ),
  );
}

class _CharacterShareConfirmation extends StatefulWidget {
  const _CharacterShareConfirmation({
    required this.character,
    required this.recipient,
    required this.repository,
  });
  final AiCharacter character;
  final CharacterShareRecipient recipient;
  final AiChatRepository repository;
  @override
  State<_CharacterShareConfirmation> createState() =>
      _CharacterShareConfirmationState();
}

class _CharacterShareConfirmationState
    extends State<_CharacterShareConfirmation> {
  final _note = TextEditingController();
  bool _sending = false;
  String? _error;
  String? _requestId;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_sending) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      _requestId ??= widget.repository.newShareRequestId();
      await widget.repository.shareCharacter(
        characterId: widget.character.id,
        recipient: widget.recipient,
        requestId: _requestId!,
        note: _note.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted)
        setState(
          () => _error = error is AiChatException
              ? error.message
              : 'Could not share. Please try again.',
        );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_sending,
    child: Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Send to', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 12),
              Row(
                children: [
                  _RecipientAvatar(recipient: widget.recipient),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.recipient.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SoftCard(
                padding: const EdgeInsets.all(12),
                radius: 14,
                child: SharedCharacterCard(
                  share: SharedAiCharacter(widget.character),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _note,
                enabled: !_sending,
                maxLength: 2000,
                minLines: 1,
                maxLines: 3,
                onChanged: (_) => _requestId = null,
                decoration: const InputDecoration(
                  hintText: 'Add a message (optional)',
                  counterText: '',
                ),
              ),
              if (widget.recipient.isAi) ...[
                const SizedBox(height: 8),
                Text(
                  'Includes your recent chat with this character.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _sending
                          ? null
                          : () => Navigator.of(context).pop(false),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _sending ? null : _send,
                      child: Text(_sending ? 'Sending…' : 'Send'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class SharedCharacterCard extends StatelessWidget {
  const SharedCharacterCard({super.key, required this.share, this.onTap});
  final SharedAiCharacter share;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final character = share.character;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 52,
                    height: 52,
                    child: CharacterPortrait(
                      photoUrl: character.avatarUrl,
                      assetPath: character.portraitAsset,
                      fallback: Icon(character.icon),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        character.name,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      Text(
                        character.personality,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'AI character · ${character.publicId}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (onTap != null)
              const Text(
                'Tap to chat',
                style: TextStyle(color: AppColors.clay),
              ),
          ],
        ),
      ),
    );
  }
}
