import 'package:flutter/material.dart';

import '../widgets/app_ui.dart';
import 'custom_keyboard.dart';
import 'keyboard_catalog.dart';
import 'keyboard_store.dart';
import 'keyboard_thumbnail.dart';

class CustomKeyboardShopCard extends StatelessWidget {
  const CustomKeyboardShopCard({super.key, required this.store});
  final KeyboardStore store;

  void _open(BuildContext context, [String? projectId]) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            CustomKeyboardScreen(store: store, projectId: projectId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SoftCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.auto_awesome_rounded,
              color: AppColors.clay,
              size: 30,
            ),
            const SizedBox(height: 12),
            Text(
              'A keyboard for your own AI',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              'Choose a character you created and describe your style. '
              'Generate up to three designs, then save your favorite.',
            ),
            const SizedBox(height: 12),
            const Text(
              '$customKeyboardPrice Likes · one keyboard · up to 3 generations',
              style: TextStyle(
                color: AppColors.clay,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: store.ready && !store.busy
                  ? () => _open(context)
                  : null,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Create custom keyboard'),
            ),
          ],
        ),
      ),
      if (store.ready && store.projects.isNotEmpty) ...[
        const SizedBox(height: 20),
        const SectionHeader(
          title: 'My custom keyboards',
          subtitle:
              'Saved on this device. Revisit any purchase to compare its designs.',
        ),
        const SizedBox(height: 8),
        for (final project in store.projects.reversed)
          Card(
            child: ListTile(
              leading: Icon(
                project.selected == null
                    ? Icons.auto_awesome_rounded
                    : Icons.keyboard_rounded,
              ),
              title: Text(project.characterName),
              subtitle: Text(
                '${project.selected == null ? 'Choose & save' : 'Saved locally'}'
                ' · ${project.results.length}/3 generated · ${project.remaining} left',
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: store.busy ? null : () => _open(context, project.id),
            ),
          ),
      ],
    ],
  );
}

class CustomKeyboardScreen extends StatefulWidget {
  const CustomKeyboardScreen({super.key, required this.store, this.projectId});
  final KeyboardStore store;
  final String? projectId;

  @override
  State<CustomKeyboardScreen> createState() => _CustomKeyboardScreenState();
}

class _CustomKeyboardScreenState extends State<CustomKeyboardScreen> {
  final _style = TextEditingController();
  late final String _account;
  String? _projectId;
  String? _characterId;
  String? _chosenId;
  String? _error;
  bool _working = false;
  KeyboardUseScope _scope = KeyboardUseScope.aiOnly;

  @override
  void initState() {
    super.initState();
    _account = widget.store.accountId;
    _projectId = widget.projectId;
    final project = _projectId == null
        ? null
        : widget.store.projectById(_projectId!);
    _chosenId =
        project?.selectedId ??
        (project?.results.length == 1 ? project!.results.first.skin.id : null);
    _style.text = project?.results.lastOrNull?.style ?? '';
    _scope = widget.store.scope;
  }

  @override
  void dispose() {
    _style.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    if (_working) return;
    final style = _style.text.trim();
    if (style.isEmpty || style.length > 500) {
      setState(
        () => _error = style.isEmpty
            ? 'Describe the style you want first.'
            : 'Keep your style description under 500 characters.',
      );
      return;
    }
    if (_projectId == null && _characterId == null) {
      setState(() => _error = 'Choose an AI character you created first.');
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    if (_projectId == null) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Create your keyboard'),
          content: const Text(
            'Pay 60 Likes once for up to 3 generations. '
            'Choose and save one keyboard. You can compare all results and '
            'change your selection later without paying again.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Buy · 60 Likes'),
            ),
          ],
        ),
      );
      if (confirmed != true ||
          !mounted ||
          widget.store.accountId != _account ||
          !widget.store.ready) {
        return;
      }
    }
    setState(() {
      _working = true;
      _error = null;
    });
    final store = widget.store;
    String? error;
    if (_projectId == null) {
      error = await store.purchaseCustomKeyboard(_characterId!);
      if (!mounted || store.accountId != _account || !store.ready) {
        if (mounted) setState(() => _working = false);
        return;
      }
      if (error == null) _projectId = store.projects.last.id;
    }
    error ??= await store.generateKeyboard(_projectId!, style);
    if (!mounted) return;
    setState(() {
      _working = false;
      _error = error;
      if (error == null) {
        final project = store.projectById(_projectId!);
        // Once there are alternatives, the user explicitly chooses a favorite.
        _chosenId = project?.results.length == 1
            ? project!.results.first.skin.id
            : null;
      }
    });
  }

  Future<void> _save() async {
    if (_working || _chosenId == null || _projectId == null) return;
    setState(() {
      _working = true;
      _error = null;
    });
    final error = await widget.store.saveCustomKeyboard(
      _projectId!,
      _chosenId!,
      _scope,
    );
    if (!mounted) return;
    setState(() {
      _working = false;
      _error = error;
    });
    if (error == null &&
        widget.store.accountId == _account &&
        widget.store.ready) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Keyboard saved on this device and in My custom keyboards, and applied.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.store,
    builder: (context, _) {
      final store = widget.store;
      final project = _projectId == null
          ? null
          : store.projectById(_projectId!);
      final locked = _working || store.busy || !store.ready;
      final canGenerate = project == null || project.remaining > 0;
      final characters = store.ownCharacters;
      final selectedCharacter = characters.any((c) => c.id == _characterId)
          ? _characterId
          : null;
      return Scaffold(
        backgroundColor: AppColors.cream,
        appBar: AppBar(title: const Text('Your custom keyboard')),
        body: !store.ready
            ? const Center(child: CircularProgressIndicator())
            : store.accountId != _account
            ? const Center(
                child: Text('Account changed. Reopen the keyboard shop.'),
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      project == null
                          ? 'Make it yours'
                          : 'Made for ${project.characterName}',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      project == null
                          ? 'One purchase, up to three designs. Choose your favorite to save.'
                          : '${project.results.length} of 3 generated · ${project.remaining} '
                                '${project.remaining == 1 ? 'generation' : 'generations'} left',
                      key: const Key('generation-count'),
                    ),
                    const SizedBox(height: 24),
                    if (project == null) ...[
                      const Text(
                        '1. Choose your AI',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 10),
                      if (!store.charactersReady)
                        const LinearProgressIndicator()
                      else if (store.characterError != null) ...[
                        Text(store.characterError!),
                        TextButton(
                          onPressed: locked
                              ? null
                              : () => store.loadForAccount(_account),
                          child: const Text('Retry loading characters'),
                        ),
                      ] else if (characters.isEmpty)
                        const Text(
                          'Create your own AI in Chat first, then return here to make its keyboard.',
                        )
                      else
                        DropdownButtonFormField<String>(
                          key: ValueKey(selectedCharacter),
                          initialValue: selectedCharacter,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Your AI character',
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            for (final character in characters)
                              DropdownMenuItem(
                                value: character.id,
                                child: Text(
                                  character.name,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: locked
                              ? null
                              : (id) => setState(() => _characterId = id),
                        ),
                      if (selectedCharacter != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          characters
                              .firstWhere((c) => c.id == selectedCharacter)
                              .personality,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppColors.muted),
                        ),
                      ],
                      const SizedBox(height: 24),
                    ],
                    if (canGenerate) ...[
                      const Text(
                        'Describe your style',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _style,
                        enabled: !locked,
                        maxLength: 500,
                        minLines: 3,
                        maxLines: 5,
                        decoration: const InputDecoration(
                          hintText:
                              'e.g. Midnight blue, soft lavender accents, rounded glass keys',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const Text(
                        "We combine your AI's background with your description to create "
                        'an abstract keyboard theme.',
                        style: TextStyle(color: AppColors.muted),
                      ),
                      const SizedBox(height: 14),
                      FilledButton.icon(
                        onPressed:
                            locked ||
                                (project == null && selectedCharacter == null)
                            ? null
                            : _generate,
                        icon: const Icon(Icons.auto_awesome_rounded),
                        label: Text(
                          _working
                              ? 'Saving…'
                              : project == null
                              ? 'Buy & generate · 60 Likes'
                              : project.results.isEmpty
                              ? 'Generate · 3 left'
                              : 'Regenerate · ${project.remaining} left',
                        ),
                      ),
                    ] else ...[
                      const Text(
                        'All 3 designs are ready. Compare them below and choose one to save.',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    if (project != null && project.results.isNotEmpty) ...[
                      const SizedBox(height: 28),
                      Text(
                        'Choose your keyboard',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Tap a design to select it. Save keeps one keyboard from this purchase.',
                      ),
                      const SizedBox(height: 12),
                      for (var i = 0; i < project.results.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: _ResultCard(
                            result: project.results[i],
                            number: i + 1,
                            selected: _chosenId == project.results[i].skin.id,
                            saved:
                                project.selectedId ==
                                project.results[i].skin.id,
                            onTap: locked
                                ? null
                                : () => setState(
                                    () =>
                                        _chosenId = project.results[i].skin.id,
                                  ),
                          ),
                        ),
                      const SizedBox(height: 8),
                      const Text('Use this keyboard for'),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          ChoiceChip(
                            label: const Text('AI chats only'),
                            selected: _scope == KeyboardUseScope.aiOnly,
                            onSelected: locked
                                ? null
                                : (_) => setState(
                                    () => _scope = KeyboardUseScope.aiOnly,
                                  ),
                          ),
                          ChoiceChip(
                            label: const Text('All app pages'),
                            selected: _scope == KeyboardUseScope.allPages,
                            onSelected: locked
                                ? null
                                : (_) => setState(
                                    () => _scope = KeyboardUseScope.allPages,
                                  ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: locked || _chosenId == null ? null : _save,
                        icon: const Icon(Icons.save_alt_rounded),
                        label: const Text('Save selected keyboard'),
                      ),
                    ],
                  ],
                ),
              ),
      );
    },
  );
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.result,
    required this.number,
    required this.selected,
    required this.saved,
    this.onTap,
  });
  final CustomKeyboardResult result;
  final int number;
  final bool selected;
  final bool saved;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: 'Select design $number',
    child: Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: selected ? AppColors.clay : Colors.transparent,
          width: 2,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 390 / 250,
              child: KeyboardThumbnail(skin: result.skin),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Icon(
                    selected
                        ? Icons.check_circle_rounded
                        : Icons.circle_outlined,
                    color: AppColors.clay,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Design $number${saved ? ' · Saved' : ''}\n${result.style}',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
