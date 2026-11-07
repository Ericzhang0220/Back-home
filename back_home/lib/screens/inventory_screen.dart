import 'package:flutter/material.dart';

import '../keyboard/keyboard_catalog.dart';
import '../keyboard/keyboard_store.dart';
import '../rooms/room_state.dart';
import '../widgets/app_ui.dart';

/// The same owned collection is available from Profile and AI chat settings.
class InventoryScreen extends StatefulWidget {
  const InventoryScreen({
    super.key,
    required this.store,
    this.keyboardsOnly = false,
  });
  final KeyboardStore store;
  final bool keyboardsOnly;

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  bool _keyboards = true;
  RoomItemCategory? _category;

  void _showError(String message) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Could not complete action'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _turnOff() async {
    try {
      await widget.store.useSystemKeyboard();
    } catch (_) {
      if (!mounted) return;
      _showError('Could not save. Please try again.');
    }
  }

  Future<void> _apply(KeyboardSkin skin) async {
    final store = widget.store;
    final account = store.accountId;
    final scope = await showDialog<KeyboardUseScope>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Apply keyboard'),
        contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: Text('Where would you like to use this keyboard?'),
          ),
          for (final scope in KeyboardUseScope.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context, scope),
                style: OutlinedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: AppColors.ink,
                  side: const BorderSide(color: AppColors.clay, width: 1.5),
                  padding: const EdgeInsets.all(16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.blush,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        scope == KeyboardUseScope.aiOnly
                            ? Icons.chat_bubble_outline_rounded
                            : Icons.apps_rounded,
                        color: AppColors.clay,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            scope == KeyboardUseScope.aiOnly
                                ? 'AI chats only'
                                : 'All app pages',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            scope == KeyboardUseScope.aiOnly
                                ? 'Use only when chatting with AI.'
                                : 'Use across chats and other app text fields.',
                            style: const TextStyle(fontSize: 13, height: 1.4),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.clay,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
    if (scope == null ||
        !mounted ||
        !store.ready ||
        store.accountId != account ||
        !store.owned.contains(skin.id)) {
      return;
    }
    final error = await store.buyOrApply(skin, scope);
    if (!mounted) return;
    if (error != null) _showError(error);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([widget.store, widget.store.room]),
    builder: (context, _) {
      final store = widget.store;
      return Scaffold(
        backgroundColor: AppColors.cream,
        appBar: AppBar(
          title: Text(
            widget.keyboardsOnly ? 'Change keyboard' : 'My inventory',
          ),
        ),
        body: !store.ready
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
                children: [
                  if (!widget.keyboardsOnly) ...[
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(
                          value: true,
                          icon: Icon(Icons.keyboard_rounded),
                          label: Text('Keyboards'),
                        ),
                        ButtonSegment(
                          value: false,
                          icon: Icon(Icons.chair_outlined),
                          label: Text('Furniture'),
                        ),
                      ],
                      selected: {_keyboards},
                      onSelectionChanged: (value) =>
                          setState(() => _keyboards = value.single),
                    ),
                    const SizedBox(height: 18),
                  ],
                  if (_keyboards || widget.keyboardsOnly) ...[
                    const Text(
                      'Turn on a keyboard, or turn it off to use your system keyboard.',
                    ),
                    const SizedBox(height: 12),
                    for (final skin in store.ownedSkins)
                      Card(
                        child: ListTile(
                          leading: Icon(skin.motif, color: skin.accent),
                          title: Text(skin.name),
                          subtitle: Text(
                            store.enabled && store.activeId == skin.id
                                ? '${skin.category} · On'
                                : '${skin.category} · Off',
                          ),
                          onTap: store.busy ? null : () => _apply(skin),
                          trailing: Semantics(
                            label: 'Use ${skin.name}',
                            child: Switch.adaptive(
                              value: store.enabled && store.activeId == skin.id,
                              activeTrackColor: AppColors.clay,
                              onChanged: store.busy
                                  ? null
                                  : (enabled) {
                                      if (enabled) {
                                        _apply(skin);
                                      } else {
                                        _turnOff();
                                      }
                                    },
                            ),
                          ),
                        ),
                      ),
                  ] else ...[
                    DropdownButtonFormField<RoomItemCategory>(
                      initialValue: _category,
                      decoration: const InputDecoration(
                        labelText: 'Furniture category',
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('All furniture'),
                        ),
                        for (final category in RoomItemCategory.values)
                          DropdownMenuItem(
                            value: category,
                            child: Text(
                              category.name[0].toUpperCase() +
                                  category.name.substring(1),
                            ),
                          ),
                      ],
                      onChanged: (value) => setState(() => _category = value),
                    ),
                    const SizedBox(height: 12),
                    for (final item in store.room.ownedCatalog.where(
                      (item) => _category == null || item.category == _category,
                    ))
                      Card(
                        child: ListTile(
                          leading: Icon(item.icon),
                          title: Text(item.title),
                          subtitle: Text(
                            'Owned ${store.room.ownedCount(item.id)} · In room ${store.room.placedCount(item.id)}',
                          ),
                          trailing: TextButton(
                            onPressed:
                                store.busy ||
                                    store.room.availableToPlace(item.id) <= 0
                                ? null
                                : () {
                                    final result = store.room.addOwnedItem(
                                      item.id,
                                    );
                                    if (!result.isSuccess)
                                      _showError(result.message);
                                  },
                            child: const Text('Place'),
                          ),
                        ),
                      ),
                  ],
                ],
              ),
      );
    },
  );
}
