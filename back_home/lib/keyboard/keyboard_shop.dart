import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../widgets/app_ui.dart';
import 'keyboard_catalog.dart';
import 'keyboard_editing.dart';
import 'keyboard_panel.dart';
import 'keyboard_store.dart';

class KeyboardShopSection extends StatelessWidget {
  const KeyboardShopSection({super.key, required this.store});
  final KeyboardStore store;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: store,
    builder: (context, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SoftCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                store.enabled ? store.activeSkin.name : 'System keyboard',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 5),
              Text(
                store.enabled
                    ? (store.scope == KeyboardUseScope.aiOnly
                          ? 'Applied to AI chats only'
                          : 'Applied across Chet')
                    : 'Your device keyboard is active',
                style: const TextStyle(
                  fontFamilyFallback: ['ChetCJK'],
                  color: AppColors.muted,
                ),
              ),
              if (store.enabled)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: !store.ready || store.busy
                        ? null
                        : () async {
                            try {
                              await store.useSystemKeyboard();
                            } catch (_) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Could not save. Please try again.',
                                    ),
                                  ),
                                );
                              }
                            }
                          },
                    child: const Text('Use system keyboard'),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const SectionHeader(
          title: '20 character keyboards',
          subtitle:
              'Glass keys, soft light, and a palette borrowed from each portrait. Preview before buying.',
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 720
                ? 3
                : constraints.maxWidth < 330
                ? 1
                : 2;
            return Wrap(
              spacing: 12,
              runSpacing: 16,
              children: [
                for (var i = 0; i < keyboardSkins.length; i++)
                  SizedBox(
                    width:
                        (constraints.maxWidth - (columns - 1) * 12) / columns,
                    child: _SkinShopCard(
                      skin: keyboardSkins[i],
                      store: store,
                      number: i + 1,
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    ),
  );
}

class _SkinShopCard extends StatelessWidget {
  const _SkinShopCard({
    required this.skin,
    required this.store,
    required this.number,
  });
  final KeyboardSkin skin;
  final KeyboardStore store;
  final int number;
  @override
  Widget build(BuildContext context) {
    final owned = store.owned.contains(skin.id);
    return Material(
      color: AppColors.cream,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => KeyboardPreviewScreen(skin: skin, store: store),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
              child: AspectRatio(
                aspectRatio: 390 / 250,
                child: KeyboardThumbnail(skin: skin),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${number.toString().padLeft(2, '0')}  ${skin.characterName}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamilyFallback: ['ChetCJK'],
                      fontSize: 11,
                      color: AppColors.muted,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    skin.name,
                    style: const TextStyle(
                      fontFamilyFallback: ['ChetCJK'],
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(
                        owned
                            ? Icons.check_circle_outline_rounded
                            : Icons.favorite_rounded,
                        size: 15,
                        color: AppColors.clay,
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          owned ? 'Owned' : '${skin.price} Likes',
                          style: const TextStyle(
                            fontFamilyFallback: ['ChetCJK'],
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.arrow_forward_rounded,
                        size: 16,
                        color: AppColors.muted,
                      ),
                    ],
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

class KeyboardThumbnail extends StatefulWidget {
  const KeyboardThumbnail({super.key, required this.skin});
  final KeyboardSkin skin;
  @override
  State<KeyboardThumbnail> createState() => _KeyboardThumbnailState();
}

class _KeyboardThumbnailState extends State<KeyboardThumbnail> {
  final editing = KeyboardEditing()..chinese = false;
  @override
  void dispose() {
    editing.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: IgnorePointer(
      child: FittedBox(
        fit: BoxFit.contain,
        child: SizedBox(
          width: 390,
          height: 250,
          child: CharacterKeyboard(
            skin: widget.skin,
            editing: editing,
            onAction: () {},
            preview: true,
          ),
        ),
      ),
    ),
  );
}

class KeyboardPreviewScreen extends StatefulWidget {
  const KeyboardPreviewScreen({
    super.key,
    required this.skin,
    required this.store,
  });
  final KeyboardSkin skin;
  final KeyboardStore store;
  @override
  State<KeyboardPreviewScreen> createState() => _KeyboardPreviewScreenState();
}

class _KeyboardPreviewScreenState extends State<KeyboardPreviewScreen> {
  late final KeyboardEditing editing;
  bool _loading = true;
  bool _buying = false;
  @override
  void initState() {
    super.initState();
    editing = KeyboardEditing();
    editing.lexicon = PinyinLexicon.cached;
    _loading = editing.lexicon == null;
    unawaited(
      PinyinLexicon.load()
          .then((lexicon) {
            if (!mounted) return;
            editing.lexicon = lexicon;
            setState(() => _loading = false);
          })
          .catchError((Object _) {
            if (mounted) setState(() => _loading = false);
          }),
    );
  }

  @override
  void dispose() {
    editing.dispose();
    super.dispose();
  }

  Future<void> _purchase() async {
    if (_buying) return;
    final store = widget.store;
    final owned = store.owned.contains(widget.skin.id);
    final scope = await showDialog<KeyboardUseScope>(
      context: context,
      builder: (context) {
        var scope = KeyboardUseScope.aiOnly;
        return StatefulBuilder(
          builder: (context, update) => AlertDialog(
            title: Text(owned ? 'Apply keyboard' : 'Buy keyboard'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${widget.skin.name}\n${owned ? 'Already owned · no extra charge' : '${widget.skin.price} Likes'}',
                ),
                const SizedBox(height: 20),
                const Text('Use this keyboard for'),
                const SizedBox(height: 10),
                ChoiceChip(
                  label: const Text('AI chats only'),
                  selected: scope == KeyboardUseScope.aiOnly,
                  onSelected: (_) =>
                      update(() => scope = KeyboardUseScope.aiOnly),
                ),
                const SizedBox(height: 8),
                ChoiceChip(
                  label: const Text('All app pages'),
                  selected: scope == KeyboardUseScope.allPages,
                  onSelected: (_) =>
                      update(() => scope = KeyboardUseScope.allPages),
                ),
                const SizedBox(height: 12),
                const Text(
                  'You can change the scope later without paying again.',
                  style: TextStyle(
                    fontFamilyFallback: ['ChetCJK'],
                    fontSize: 12,
                    color: AppColors.muted,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, scope),
                child: Text(owned ? 'Apply' : 'Buy & apply'),
              ),
            ],
          ),
        );
      },
    );
    if (scope == null || !mounted) return;
    setState(() => _buying = true);
    final error = await store.buyOrApply(widget.skin, scope);
    if (!mounted) return;
    setState(() => _buying = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          error ??
              (scope == KeyboardUseScope.aiOnly
                  ? 'Applied to AI chats.'
                  : 'Applied across Chet.'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.store,
    builder: (context, _) {
      final store = widget.store;
      final owned = store.owned.contains(widget.skin.id);
      final canBuy = owned || store.room.likesBalance >= widget.skin.price;
      final height = math.min(
        MediaQuery.sizeOf(context).height * 0.48,
        312 + MediaQuery.viewPaddingOf(context).bottom,
      );
      return Scaffold(
        backgroundColor: widget.skin.base,
        body: Column(
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset(
                    widget.skin.asset,
                    fit: BoxFit.cover,
                    alignment: const Alignment(0, -0.55),
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black26,
                          Colors.transparent,
                          widget.skin.base.withValues(alpha: 0.96),
                        ],
                        stops: const [0, 0.25, 1],
                      ),
                    ),
                  ),
                  SafeArea(
                    bottom: false,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        IconButton(
                          tooltip: 'Back',
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.arrow_back_rounded),
                          color: Colors.white,
                        ),
                        const Spacer(),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.skin.characterName,
                                style: TextStyle(
                                  fontFamilyFallback: ['ChetCJK'],
                                  color: widget.skin.ink.withValues(alpha: 0.8),
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                widget.skin.name,
                                style: TextStyle(
                                  fontFamilyFallback: ['ChetCJK'],
                                  color: widget.skin.ink,
                                  fontSize: 23,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 12),
                              AnimatedBuilder(
                                animation: editing,
                                builder: (context, _) => Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(
                                      alpha: widget.skin.isDark ? 0.12 : 0.40,
                                    ),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Text(
                                    editing.value.text.isEmpty
                                        ? (_loading
                                              ? 'Loading pinyin…'
                                              : 'Try typing below · 试试拼音输入')
                                        : editing.value.text,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontFamilyFallback: ['ChetCJK'],
                                      color: widget.skin.ink,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                child: SizedBox(
                                  width: double.infinity,
                                  child: FilledButton(
                                    onPressed:
                                        !store.ready ||
                                            store.busy ||
                                            _buying ||
                                            !canBuy
                                        ? null
                                        : _purchase,
                                    child: Text(
                                      _buying
                                          ? 'Saving…'
                                          : !canBuy
                                          ? 'Not enough Likes'
                                          : owned
                                          ? 'Use keyboard'
                                          : 'Buy · ${widget.skin.price} Likes',
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: height,
              child: CharacterKeyboard(
                skin: widget.skin,
                editing: editing,
                onAction: () => editing.key('\n'),
                preview: false,
                actionLabel: 'Return',
              ),
            ),
          ],
        ),
      );
    },
  );
}
