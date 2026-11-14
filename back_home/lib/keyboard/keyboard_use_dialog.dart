import 'package:flutter/material.dart';

import 'keyboard_catalog.dart';
import 'keyboard_store.dart';

Future<String?> offerKeyboardUse(
  BuildContext context,
  KeyboardStore store,
  KeyboardSkin skin, {
  required bool newlyOwned,
}) async {
  final account = store.accountId;
  final route = ModalRoute.of(context);
  final useScope = await showDialog<KeyboardUseScope>(
    context: context,
    useRootNavigator: false,
    builder: (context) => AlertDialog(
      title: Text(newlyOwned ? 'Use this keyboard now?' : 'Apply keyboard'),
      content: Text(
        newlyOwned
            ? '${skin.name} is saved in My inventory.'
            : 'Choose where to use ${skin.name}.',
      ),
      actions: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, KeyboardUseScope.aiOnly),
              icon: const Icon(Icons.chat_bubble_outline_rounded),
              label: const Text('AI chats only'),
            ),
            OutlinedButton.icon(
              onPressed: () =>
                  Navigator.pop(context, KeyboardUseScope.allPages),
              icon: const Icon(Icons.apps_rounded),
              label: const Text('All app pages'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(newlyOwned ? 'Later' : 'Cancel'),
            ),
          ],
        ),
      ],
    ),
  );
  if (useScope == null ||
      !context.mounted ||
      route?.isCurrent != true ||
      account != store.accountId ||
      !store.owned.contains(skin.id)) {
    return null;
  }
  return store.buyOrApply(skin, useScope);
}
