import 'package:flutter/material.dart';

import 'app_auth_controller.dart';

/// Asks for the name other people will see.
///
/// Shown once automatically when a freshly verified account still has no name,
/// and on demand from Settings afterwards. Returns true when a name was saved.
Future<bool> showDisplayNamePrompt(
  BuildContext context, {
  required AppAuthController authController,
  bool isWelcome = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    // A welcome prompt should be answered or explicitly skipped rather than
    // dismissed by a stray tap outside it.
    barrierDismissible: !isWelcome,
    builder: (context) => _DisplayNameDialog(
      authController: authController,
      isWelcome: isWelcome,
    ),
  );
  return result ?? false;
}

class _DisplayNameDialog extends StatefulWidget {
  const _DisplayNameDialog({
    required this.authController,
    required this.isWelcome,
  });

  final AppAuthController authController;
  final bool isWelcome;

  @override
  State<_DisplayNameDialog> createState() => _DisplayNameDialogState();
}

class _DisplayNameDialogState extends State<_DisplayNameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.authController.currentUser?.displayName?.trim() ?? '',
  );
  String? _errorText;
  bool _isSaving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _controller.text.trim();
    if (name.isEmpty) {
      setState(() => _errorText = 'Please enter a display name.');
      return;
    }

    setState(() {
      _isSaving = true;
      _errorText = null;
    });
    try {
      await widget.authController.updateDisplayName(name);
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } on AuthFlowException catch (error) {
      if (mounted) {
        setState(() {
          _errorText = error.message;
          _isSaving = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _errorText = 'Could not save that name. Please try again.';
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.isWelcome ? 'What should we call you?' : 'Display name'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'This is the name other people see in chats and the hall. You can '
            'change it later in Settings.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            enabled: !_isSaving,
            maxLength: AppAuthController.maxDisplayNameLength,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _isSaving ? null : _save(),
            decoration: InputDecoration(
              labelText: 'Display name',
              errorText: _errorText,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
          child: Text(widget.isWelcome ? 'Not now' : 'Cancel'),
        ),
        FilledButton(
          onPressed: _isSaving ? null : _save,
          child: _isSaving
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}
