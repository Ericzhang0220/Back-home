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

  /// True while an editor is on screen. The editor runs its own 3D renderer,
  /// and the mobile GL backend can't safely keep two live renderers at once —
  /// so the background room view watches this to release its context while we
  /// edit and rebuild fresh afterwards. Without it, returning from an edit left
  /// the room's renderer wedged and the camera frozen.
  static final ValueNotifier<bool> editorActive = ValueNotifier<bool>(false);

  @override
  State<RoomEditScreen> createState() => _RoomEditScreenState();
}

class _RoomEditScreenState extends State<RoomEditScreen> {
  static const double _moveNudgeAmount = 0.05;
  static const double _rotationNudgeDegrees = 1;

  late final RoomEditorController _draftController;
  final List<RoomEditSnapshot> _undoStack = [];
  final List<RoomEditSnapshot> _redoStack = [];
  bool _restoringHistory = false;
  bool _rotationMode = false;

  bool get _canUndo => _undoStack.length > 1;
  bool get _canRedo => _redoStack.isNotEmpty;
  bool get _canDelete => _draftController.selectedItemId != null;
  bool get _hasSelection => _draftController.selectedItemId != null;
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
    // Signal the background room view to release its renderer before ours warms
    // up, so only one GL context is ever live at a time.
    RoomEditScreen.editorActive.value = true;
  }

  @override
  void dispose() {
    // Cleared after our own IsometricRoomView (a child, disposed first) has
    // torn down its context, so the room view rebuilds into a clean slate.
    RoomEditScreen.editorActive.value = false;
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

  void _moveSelectedBy(double deltaX, double deltaZ) {
    final selectedItemId = _draftController.selectedItemId;
    if (selectedItemId == null) {
      return;
    }
    final item = _draftController.placedItemById(selectedItemId);
    if (item == null) {
      return;
    }
    final result = _draftController.movePlacedItem(
      selectedItemId,
      GridPoint(item.origin.x + deltaX, item.origin.z + deltaZ),
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
              rotateSelectedWithDrag: _rotationMode,
              onRotateSelectedBy: _rotateSelectedBy,
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
          if (_hasSelection)
            Align(
              alignment: Alignment.bottomCenter,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: _BottomEditToolbar(
                    rotationMode: _rotationMode,
                    canRotate: _canRotate,
                    onMoveUp: () => _moveSelectedBy(0, -_moveNudgeAmount),
                    onMoveDown: () => _moveSelectedBy(0, _moveNudgeAmount),
                    onMoveLeft: () => _moveSelectedBy(-_moveNudgeAmount, 0),
                    onMoveRight: () => _moveSelectedBy(_moveNudgeAmount, 0),
                    onCounterClockwise: () =>
                        _rotateSelectedBy(-_rotationNudgeDegrees),
                    onClockwise: () => _rotateSelectedBy(_rotationNudgeDegrees),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _BottomEditToolbar extends StatelessWidget {
  const _BottomEditToolbar({
    required this.rotationMode,
    required this.canRotate,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onMoveLeft,
    required this.onMoveRight,
    required this.onCounterClockwise,
    required this.onClockwise,
  });

  final bool rotationMode;
  final bool canRotate;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final VoidCallback onMoveLeft;
  final VoidCallback onMoveRight;
  final VoidCallback onCounterClockwise;
  final VoidCallback onClockwise;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFFF8EFE4).withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white.withValues(alpha: 0.34)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: rotationMode
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _EditToolbarButton(
                        icon: Icons.rotate_left_rounded,
                        onPressed: canRotate ? onCounterClockwise : null,
                      ),
                      const SizedBox(width: 14),
                      _EditToolbarButton(
                        icon: Icons.rotate_right_rounded,
                        onPressed: canRotate ? onClockwise : null,
                      ),
                    ],
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _EditToolbarButton(
                        icon: Icons.keyboard_arrow_left_rounded,
                        onPressed: onMoveLeft,
                      ),
                      const SizedBox(width: 10),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _EditToolbarButton(
                            icon: Icons.keyboard_arrow_up_rounded,
                            onPressed: onMoveUp,
                          ),
                          const SizedBox(height: 8),
                          _EditToolbarButton(
                            icon: Icons.keyboard_arrow_down_rounded,
                            onPressed: onMoveDown,
                          ),
                        ],
                      ),
                      const SizedBox(width: 10),
                      _EditToolbarButton(
                        icon: Icons.keyboard_arrow_right_rounded,
                        onPressed: onMoveRight,
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _EditToolbarButton extends StatelessWidget {
  const _EditToolbarButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      onPressed: onPressed,
      icon: Icon(icon),
      style: IconButton.styleFrom(fixedSize: const Size(46, 46), iconSize: 28),
    );
  }
}
