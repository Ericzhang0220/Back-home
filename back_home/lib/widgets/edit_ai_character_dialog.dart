import 'package:flutter/material.dart';

import '../chat/ai_models.dart';

Future<void> showEditAiCharacterDialog(
  BuildContext context, {
  required AiCharacter character,
  required Future<void> Function(String name, String personality) onSave,
}) => showDialog<void>(
  context: context,
  builder: (_) => _EditAiCharacterDialog(character: character, onSave: onSave),
);

class _EditAiCharacterDialog extends StatefulWidget {
  const _EditAiCharacterDialog({required this.character, required this.onSave});
  final AiCharacter character;
  final Future<void> Function(String, String) onSave;

  @override
  State<_EditAiCharacterDialog> createState() => _EditAiCharacterDialogState();
}

class _EditAiCharacterDialogState extends State<_EditAiCharacterDialog> {
  late final _name = TextEditingController(text: widget.character.name);
  late final _personality = TextEditingController(
    text: widget.character.personality,
  );
  final _form = GlobalKey<FormState>();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _personality.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(_name.text.trim(), _personality.text.trim());
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Could not save. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      title: const Text('Edit AI character'),
      content: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                enabled: !_saving,
                maxLength: 60,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  counterText: '',
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Enter a name.'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _personality,
                enabled: !_saving,
                minLines: 2,
                maxLines: 5,
                maxLength: 400,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Personality',
                  counterText: '',
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Describe their personality.'
                    : null,
              ),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    ),
  );
}
