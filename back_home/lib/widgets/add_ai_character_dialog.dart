import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../chat/ai_character_catalog.dart';
import '../chat/ai_character_photo.dart';

Future<AiCharacterDraft?> showAddAiCharacterDialog(
  BuildContext context, {
  Future<AiCharacterPhoto?> Function()? pickPhoto,
  Future<void> Function(AiCharacterDraft)? onCreate,
}) {
  return showDialog<AiCharacterDraft>(
    context: context,
    builder: (_) =>
        _AddCharacterDialog(pickPhoto: pickPhoto, onCreate: onCreate),
  );
}

class AiCharacterDraft {
  const AiCharacterDraft({
    required this.name,
    required this.personality,
    required this.isPublic,
    required this.photo,
    this.gender = 'unspecified',
    this.tags = const [],
  });

  final String name;
  final String personality;
  final bool isPublic;
  final AiCharacterPhoto photo;
  final String gender;
  final List<String> tags;
}

class _AddCharacterDialog extends StatefulWidget {
  const _AddCharacterDialog({this.pickPhoto, this.onCreate});
  final Future<AiCharacterPhoto?> Function()? pickPhoto;
  final Future<void> Function(AiCharacterDraft)? onCreate;

  @override
  State<_AddCharacterDialog> createState() => _AddCharacterDialogState();
}

class _AddCharacterDialogState extends State<_AddCharacterDialog> {
  // Keep controllers alive through the route's closing animation.
  final _nameController = TextEditingController();
  final _personalityController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isPublic = false;
  bool _isPicking = false;
  bool _isSaving = false;
  String _gender = 'unspecified';
  AiCharacterPhoto? _photo;
  String? _photoError;
  String? _saveError;

  @override
  void dispose() {
    _nameController.dispose();
    _personalityController.dispose();
    super.dispose();
  }

  Future<void> _choosePhoto() async {
    if (_isPicking || _isSaving) return;
    setState(() {
      _isPicking = true;
      _photoError = null;
    });
    try {
      final photo =
          await (widget.pickPhoto ?? AiCharacterPhoto.pickFromGallery)();
      if (mounted && photo != null) {
        setState(() => _photo = photo);
      }
    } on PlatformException catch (error) {
      if (mounted) {
        setState(
          () => _photoError =
              error.code.contains('denied') || error.code.contains('restricted')
              ? 'Photo access is unavailable. Allow access in Settings and try again.'
              : 'Could not open your photos. Please try again.',
        );
      }
    } on FormatException catch (error) {
      if (mounted) {
        setState(() => _photoError = error.message);
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _photoError =
              'Could not read that image. Please choose another photo.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isPicking = false);
      }
    }
  }

  Future<void> _create() async {
    if (_isSaving || _isPicking) return;
    final valid = _formKey.currentState!.validate();
    if (_photo == null) {
      setState(() => _photoError = 'Choose a character photo to continue.');
      return;
    }
    if (!valid) return;
    final draft = AiCharacterDraft(
      name: _nameController.text.trim(),
      personality: _personalityController.text.trim(),
      isPublic: _isPublic,
      photo: _photo!,
      gender: _gender,
      tags: aiTagsFromPersonality(_personalityController.text),
    );
    setState(() {
      _isSaving = true;
      _saveError = null;
    });
    try {
      await widget.onCreate?.call(draft);
      if (mounted) {
        Navigator.of(context).pop(draft);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _saveError = 'Could not create character. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isSaving,
      child: AlertDialog(
        title: const Text('Add AI character'),
        content: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _nameController,
                  enabled: !_isSaving,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Name'),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Enter a name.'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _personalityController,
                  enabled: !_isSaving,
                  minLines: 1,
                  maxLines: 3,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Personality'),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Describe their personality.'
                      : null,
                ),
                const SizedBox(height: 12),
                if (_photo != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: SizedBox(
                      height: 120,
                      child: Image.memory(_photo!.bytes, fit: BoxFit.cover),
                    ),
                  ),
                OutlinedButton.icon(
                  key: const ValueKey('ai-character-photo-picker'),
                  onPressed: _isPicking || _isSaving ? null : _choosePhoto,
                  icon: _isPicking
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add_rounded),
                  label: Text(_photo == null ? 'Add photo' : 'Change photo'),
                ),
                if (_photoError != null)
                  Text(
                    _photoError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 12,
                    ),
                  ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _gender,
                  decoration: const InputDecoration(
                    labelText: 'Character gender',
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'unspecified',
                      child: Text('Not specified'),
                    ),
                    DropdownMenuItem(value: 'male', child: Text('Male')),
                    DropdownMenuItem(value: 'female', child: Text('Female')),
                  ],
                  onChanged: _isSaving
                      ? null
                      : (value) => setState(() => _gender = value!),
                ),
                SwitchListTile.adaptive(
                  value: _isPublic,
                  onChanged: _isSaving
                      ? null
                      : (value) => setState(() => _isPublic = value),
                  contentPadding: EdgeInsets.zero,
                  title: Text(_isPublic ? 'Public' : 'Private'),
                  secondary: Icon(
                    _isPublic ? Icons.public_rounded : Icons.lock_rounded,
                  ),
                ),
                if (_saveError != null)
                  Text(
                    _saveError!,
                    key: const ValueKey('ai-character-create-error'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _isSaving || _isPicking ? null : _create,
            child: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Add'),
          ),
        ],
      ),
    );
  }
}
