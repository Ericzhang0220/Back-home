import 'package:flutter/material.dart';

import 'keyboard_catalog.dart';
import 'keyboard_editing.dart';
import 'keyboard_panel.dart';

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
