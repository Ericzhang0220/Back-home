import 'dart:ui';

import 'package:flutter/material.dart';

import '../rooms/isometric_room_view.dart';
import '../rooms/room_state.dart';

class RoomEditScreen extends StatefulWidget {
  const RoomEditScreen({
    super.key,
    required this.controller,
    this.initialDefinitionId,
  });

  final RoomEditorController controller;
  final String? initialDefinitionId;

  @override
  State<RoomEditScreen> createState() => _RoomEditScreenState();
}

class _RoomEditScreenState extends State<RoomEditScreen> {
  late final RoomEditorController _draftController;
  final List<RoomEditSnapshot> _undoStack = [];
  final List<RoomEditSnapshot> _redoStack = [];
  bool _restoringHistory = false;
  bool _rotationMode = false;
  Offset? _selectedFurniturePosition;

  bool get _canUndo => _undoStack.length > 1;
  bool get _canRedo => _redoStack.isNotEmpty;
  bool get _canDelete => _draftController.selectedItemId != null;
  bool get _canRotate {
    final selectedItemId = _draftController.selectedItemId;
    if (selectedItemId == null) {
      return false;
    }
    final item = _draftController.placedItemById(selectedItemId);
    if (item == null) {
      return false;
    }
    return _draftController.definitionFor(item.definitionId).canRotate;
  }

  @override
  void initState() {
    super.initState();
    _draftController = RoomEditorController.editing(widget.controller);
    final initialDefinitionId = widget.initialDefinitionId;
    if (initialDefinitionId != null) {
      final result = _draftController.addOwnedItemForEditing(
        initialDefinitionId,
        preferredOrigin: _draftController.centerOriginFor(initialDefinitionId),
      );
      if (!result.isSuccess) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) {
            return;
          }
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text(result.message)));
        });
      }
    }
    _undoStack.add(_draftController.createEditSnapshot());
    _draftController.addListener(_handleDraftChanged);
  }

  @override
  void dispose() {
    _draftController.removeListener(_handleDraftChanged);
    _draftController.dispose();
    super.dispose();
  }

  void _cancel() {
    Navigator.of(context).pop();
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    if (!_draftController.hasValidLayout) {
      for (final item in _draftController.placedItems) {
        if (!_draftController.isPlacedItemValid(item.instanceId)) {
          _draftController.selectItem(item.instanceId);
          break;
        }
      }
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Move highlighted furniture to an open spot first.'),
          ),
        );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Save room layout?'),
          content: const Text('This will replace your current room layout.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
    if (!mounted || confirmed != true) {
      return;
    }
    widget.controller.applyEditSession(_draftController);
    Navigator.of(context).pop();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Room layout saved.')));
  }

  void _deleteSelected() {
    final selectedItemId = _draftController.selectedItemId;
    if (selectedItemId == null) {
      return;
    }
    _rotationMode = false;
    _draftController.storePlacedItem(selectedItemId);
  }

  void _toggleRotationMode() {
    if (!_canRotate) {
      return;
    }
    setState(() {
      _rotationMode = !_rotationMode;
    });
  }

  void _rotateSelectedBy(double deltaDegrees) {
    final selectedItemId = _draftController.selectedItemId;
    if (selectedItemId == null) {
      return;
    }
    final result = _draftController.rotatePlacedItem(
      selectedItemId,
      deltaDegrees: deltaDegrees,
    );
    if (!result.isSuccess) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(result.message)));
    }
  }

  void _undo() {
    if (!_canUndo) {
      return;
    }
    final current = _undoStack.removeLast();
    _redoStack.add(current);
    _restoreSnapshot(_undoStack.last);
  }

  void _redo() {
    if (!_canRedo) {
      return;
    }
    final next = _redoStack.removeLast();
    _undoStack.add(next);
    _restoreSnapshot(next);
  }

  void _restoreSnapshot(RoomEditSnapshot snapshot) {
    _restoringHistory = true;
    _draftController.restoreEditSnapshot(snapshot);
    _restoringHistory = false;
    if (mounted) {
      setState(() {});
    }
  }

  void _handleDraftChanged() {
    if (_restoringHistory) {
      return;
    }
    if (_rotationMode && !_canRotate) {
      _rotationMode = false;
    }

    final current = _draftController.createEditSnapshot();
    if (!_samePlacedLayout(_undoStack.last, current)) {
      _undoStack.add(current);
      _redoStack.clear();
    }

    if (mounted) {
      setState(() {});
    }
  }

  bool _samePlacedLayout(RoomEditSnapshot a, RoomEditSnapshot b) {
    if (a.placedItems.length != b.placedItems.length) {
      return false;
    }
    for (var i = 0; i < a.placedItems.length; i += 1) {
      final left = a.placedItems[i];
      final right = b.placedItems[i];
      if (left.instanceId != right.instanceId ||
          left.definitionId != right.definitionId ||
          left.origin != right.origin ||
          left.rotationDegrees != right.rotationDegrees) {
        return false;
      }
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final compactToolbar = media.size.width < 560;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: IsometricRoomView(
              controller: _draftController,
              isActive: true,
              canMoveFurniture: true,
              onSelectedScreenPositionChanged: (position) {
                if (!mounted) {
                  return;
                }
                setState(() {
                  _selectedFurniturePosition = position;
                });
              },
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.5),
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.2),
                    ],
                    stops: const [0, 0.34, 1],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: media.padding.top + 14,
            left: 16,
            right: 16,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8EFE4).withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.34),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                    child: Row(
                      children: [
                        IconButton.filledTonal(
                          onPressed: _cancel,
                          icon: const Icon(Icons.close_rounded),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filledTonal(
                          onPressed: _canUndo ? _undo : null,
                          icon: const Icon(Icons.undo_rounded),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filledTonal(
                          onPressed: _canRedo ? _redo : null,
                          icon: const Icon(Icons.redo_rounded),
                        ),
                        const Spacer(),
                        if (compactToolbar)
                          IconButton.filledTonal(
                            onPressed: _canDelete ? _deleteSelected : null,
                            icon: const Icon(Icons.delete_rounded),
                          )
                        else
                          FilledButton.tonalIcon(
                            onPressed: _canDelete ? _deleteSelected : null,
                            icon: const Icon(Icons.delete_rounded),
                            label: const Text('Delete'),
                          ),
                        const SizedBox(width: 8),
                        if (compactToolbar)
                          IconButton(
                            onPressed: _canRotate ? _toggleRotationMode : null,
                            icon: const Icon(
                              Icons.rotate_90_degrees_ccw_rounded,
                            ),
                            style:
                                (_rotationMode
                                        ? IconButton.styleFrom(
                                            backgroundColor: Theme.of(
                                              context,
                                            ).colorScheme.primary,
                                            foregroundColor: Theme.of(
                                              context,
                                            ).colorScheme.onPrimary,
                                          )
                                        : IconButton.styleFrom(
                                            backgroundColor: Theme.of(
                                              context,
                                            ).colorScheme.secondaryContainer,
                                            foregroundColor: Theme.of(
                                              context,
                                            ).colorScheme.onSecondaryContainer,
                                          ))
                                    .copyWith(
                                      padding: const WidgetStatePropertyAll(
                                        EdgeInsets.all(8),
                                      ),
                                    ),
                          )
                        else
                          _rotationMode
                              ? FilledButton.icon(
                                  onPressed: _canRotate
                                      ? _toggleRotationMode
                                      : null,
                                  icon: const Icon(
                                    Icons.rotate_90_degrees_ccw_rounded,
                                  ),
                                  label: const Text('Rotate'),
                                )
                              : FilledButton.tonalIcon(
                                  onPressed: _canRotate
                                      ? _toggleRotationMode
                                      : null,
                                  icon: const Icon(
                                    Icons.rotate_90_degrees_ccw_rounded,
                                  ),
                                  label: const Text('Rotate'),
                                ),
                        const SizedBox(width: 8),
                        if (compactToolbar)
                          IconButton.filled(
                            onPressed: _save,
                            icon: const Icon(Icons.check_rounded),
                          )
                        else
                          FilledButton.icon(
                            onPressed: _save,
                            icon: const Icon(Icons.check_rounded),
                            label: const Text('Save'),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (_rotationMode && _selectedFurniturePosition != null)
            _RotationControls(
              position: _selectedFurniturePosition!,
              screenSize: media.size,
              topInset: media.padding.top,
              onCounterClockwise: () => _rotateSelectedBy(-5),
              onClockwise: () => _rotateSelectedBy(5),
            ),
        ],
      ),
    );
  }
}

class _RotationControls extends StatelessWidget {
  const _RotationControls({
    required this.position,
    required this.screenSize,
    required this.topInset,
    required this.onCounterClockwise,
    required this.onClockwise,
  });

  final Offset position;
  final Size screenSize;
  final double topInset;
  final VoidCallback onCounterClockwise;
  final VoidCallback onClockwise;

  @override
  Widget build(BuildContext context) {
    final left = (position.dx - 58).clamp(12.0, screenSize.width - 128.0);
    final top = (position.dy - 28).clamp(topInset + 76, screenSize.height - 76);

    return Positioned(
      left: left,
      top: top,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _RotationControlButton(
            icon: Icons.rotate_left_rounded,
            onPressed: onCounterClockwise,
          ),
          const SizedBox(width: 16),
          _RotationControlButton(
            icon: Icons.rotate_right_rounded,
            onPressed: onClockwise,
          ),
        ],
      ),
    );
  }
}

class _RotationControlButton extends StatelessWidget {
  const _RotationControlButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.primary,
      shape: const CircleBorder(),
      elevation: 8,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon),
        color: Theme.of(context).colorScheme.onPrimary,
      ),
    );
  }
}
