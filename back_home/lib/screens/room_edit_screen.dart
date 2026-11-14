import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../rooms/isometric_room_view.dart';
import '../rooms/furniture_preview.dart';
import '../rooms/room_gl_gate.dart';
import '../rooms/room_state.dart';

class RoomEditScreen extends StatefulWidget {
  static const routeName = '/room/edit';

  const RoomEditScreen({
    super.key,
    required this.controller,
    this.initialDefinitionId,
    this.initiallyShowStorage = false,
  });

  final RoomEditorController controller;
  final String? initialDefinitionId;
  final bool initiallyShowStorage;

  @override
  State<RoomEditScreen> createState() => _RoomEditScreenState();
}

class _RoomEditScreenState extends State<RoomEditScreen> {
  static const double _moveNudgeAmount = 0.05;
  static const double _rotationNudgeDegrees = 1;

  /// The editor runs its own 3D renderer, so it takes the GL claim for as long
  /// as it is on screen; the room view behind it (and the shop's previews, when
  /// the editor was opened from there) release theirs until we pop.
  final Object _glToken = Object();

  late final RoomEditorController _draftController;
  final List<RoomEditSnapshot> _undoStack = [];
  final List<RoomEditSnapshot> _redoStack = [];
  bool _restoringHistory = false;
  bool _rotationMode = false;
  Timer? _storedFeedbackTimer;
  bool _showStoredFeedback = false;
  int _placementViewRevision = 0;

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
    if (initialDefinitionId != null) _placeFromStorage(initialDefinitionId);
    if (widget.initiallyShowStorage) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_openStorage());
      });
    }
    _undoStack.add(_draftController.createEditSnapshot());
    _draftController.addListener(_handleDraftChanged);
    // Take the GL claim so whatever was rendering behind us releases its
    // context. The gate defers the actual hand-off out of this build phase.
    RoomGlGate.claim(_glToken);
  }

  @override
  void dispose() {
    // The gate's post-frame hand-back lands after our own renderer has fully
    // torn down, so the screen behind us rebuilds against a clean slate with no
    // second context alive.
    RoomGlGate.release(_glToken);
    _storedFeedbackTimer?.cancel();
    _draftController.removeListener(_handleDraftChanged);
    _draftController.dispose();
    super.dispose();
  }

  Future<void> _showEditError(String message) => showDialog<void>(
    context: context,
    useRootNavigator: false,
    builder: (context) => AlertDialog(
      title: const Text('Could not edit room'),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('OK'),
        ),
      ],
    ),
  );

  Future<void> _save() async {
    if (!_draftController.hasValidLayout) {
      for (final item in _draftController.placedItems) {
        if (!_draftController.isPlacedItemValid(item.instanceId)) {
          _draftController.selectItem(item.instanceId);
          break;
        }
      }
      await _showEditError('Move highlighted furniture to an open spot first.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
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
  }

  void _storeSelected() {
    final selectedItemId = _draftController.selectedItemId;
    if (selectedItemId == null) return;
    final result = _draftController.storePlacedItem(selectedItemId);
    if (!result.isSuccess) return;
    _storedFeedbackTimer?.cancel();
    setState(() => _showStoredFeedback = true);
    _storedFeedbackTimer = Timer(const Duration(milliseconds: 1000), () {
      if (mounted) setState(() => _showStoredFeedback = false);
    });
  }

  Future<void> _openStorage() async {
    final items = _draftController.ownedCatalog;
    final definitionId = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => SizedBox(
        height: MediaQuery.sizeOf(context).height * .58,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: Text('Storage', style: Theme.of(context).textTheme.titleLarge),
            ),
            if (items.isEmpty)
              const Expanded(child: Center(child: Text('No furniture yet.')))
            else
              Expanded(
                child: ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final stored = _draftController.availableToPlace(item.id);
                    return ListTile(
                      leading: FurnitureThumbnail(definition: item, size: 44),
                      title: Text(item.title),
                      subtitle: Text('In storage: $stored · In room: ${_draftController.placedCount(item.id)}'),
                      trailing: TextButton(
                        onPressed: stored > 0 ? () => Navigator.pop(context, item.id) : null,
                        child: const Text('Place'),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
    if (!mounted || definitionId == null) return;
    _placeFromStorage(definitionId);
    setState(() => _placementViewRevision++);
  }

  void _placeFromStorage(String definitionId) {
    final result = _draftController.addOwnedItemForEditing(definitionId);
    if (!result.isSuccess) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_showEditError(result.message));
      });
      return;
    }
    final item = _draftController.placedItemById(result.instanceId!)!;
    final bounds = _draftController.placementBox(item);
    final view = _draftController.viewPose;
    final x = bounds.x - RoomEditorController.roomWidth / 2;
    final z = bounds.z - RoomEditorController.roomDepth / 2;
    final centerY = (bounds.bottom + bounds.top) / 2;
    final dx = x - view.x;
    final dz = z - view.z;
    final distance = math.sqrt(dx * dx + dz * dz);

    // Aim at the model's center so a low piece is visible above the controls.
    _draftController.viewPose = (
      x: view.x, y: view.y, z: view.z,
      yaw: distance > .1 ? math.atan2(dx, -dz) : view.yaw,
      pitch: ((centerY - view.y) / math.max(distance, .1)).clamp(-1.2, .75).toDouble(),
    );
  }

  void _toggleRotationMode() {
    setState(() => _rotationMode = !_rotationMode);
  }

  void _rotateSelectedBy(double deltaDegrees) {
    final selectedItemId = _draftController.selectedItemId;
    if (!_rotationMode || selectedItemId == null || !_canRotate) return;
    final result = _draftController.rotatePlacedItem(selectedItemId, deltaDegrees: deltaDegrees);
    if (!result.isSuccess) _showBlocked(result.message);
  }

  void _moveSelectedBy(double deltaX, double deltaZ, {double lift = 0}) {
    if (_rotationMode) return;
    final item = _draftController.placedItemById(_draftController.selectedItemId ?? '');
    if (item == null) return;
    final result = _draftController.movePlacedItem(
      item.instanceId,
      GridPoint(item.origin.x + deltaX, item.origin.z + deltaZ),
      elevation: item.elevation + lift,
    );
    if (!result.isSuccess) _showBlocked(result.message);
  }

  void _showBlocked(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), duration: const Duration(milliseconds: 900)));
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
          left.rotationDegrees != right.rotationDegrees ||
          left.elevation != right.elevation) {
        return false;
      }
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);

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
              placementViewRevision: _placementViewRevision,
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
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Badge(
                              isLabelVisible: _showStoredFeedback,
                              label: const Text('+1'),
                              child: _ToolbarIcon(
                                icon: Icons.inventory_2_outlined,
                                label: 'Storage',
                                onPressed: _openStorage,
                                highlighted: _showStoredFeedback,
                              ),
                            ),
                          ),
                        ),
                        _ToolbarIcon(
                          onPressed: _canUndo ? _undo : null,
                          icon: Icons.undo_rounded,
                          label: 'Undo',
                        ),
                        _ToolbarIcon(
                          onPressed: _canRedo ? _redo : null,
                          icon: Icons.redo_rounded,
                          label: 'Redo',
                        ),
                        _ToolbarIcon(
                          onPressed: _canDelete ? _storeSelected : null,
                          icon: Icons.delete_rounded,
                          label: 'Store selected furniture',
                        ),
                        _ToolbarIcon(
                          onPressed: _toggleRotationMode,
                          icon: _rotationMode ? Icons.rotate_90_degrees_ccw_rounded : Icons.open_with_rounded,
                          label: _rotationMode ? 'Rotate mode. Switch to move' : 'Move mode. Switch to rotate',
                          highlighted: _rotationMode,
                        ),
                        _ToolbarIcon(
                          onPressed: _save,
                          icon: Icons.check_rounded,
                          label: 'Save',
                          highlighted: true,
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
                    onRaise: () => _moveSelectedBy(0, 0, lift: _moveNudgeAmount),
                    onLower: () => _moveSelectedBy(0, 0, lift: -_moveNudgeAmount),
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

class _ToolbarIcon extends StatelessWidget {
  const _ToolbarIcon({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.highlighted = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 48,
      child: Center(
        child: highlighted
            ? IconButton.filled(
                tooltip: label,
                onPressed: onPressed,
                icon: Icon(icon),
              )
            : IconButton.filledTonal(
                tooltip: label,
                onPressed: onPressed,
                icon: Icon(icon),
              ),
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
    required this.onRaise,
    required this.onLower,
  });

  final bool rotationMode;
  final bool canRotate;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final VoidCallback onMoveLeft;
  final VoidCallback onMoveRight;
  final VoidCallback onCounterClockwise;
  final VoidCallback onClockwise;
  final VoidCallback onRaise, onLower;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFFF8EFE4).withValues(alpha: 0.66),
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
                        label: 'Rotate left',
                        onPressed: canRotate ? onCounterClockwise : null,
                      ),
                      const SizedBox(width: 14),
                      _EditToolbarButton(
                        icon: Icons.rotate_right_rounded,
                        label: 'Rotate right',
                        onPressed: canRotate ? onClockwise : null,
                      ),
                    ],
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _EditToolbarButton(
                        icon: Icons.keyboard_arrow_left_rounded,
                        label: 'Move left',
                        onPressed: onMoveLeft,
                      ),
                      const SizedBox(width: 10),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _EditToolbarButton(
                            icon: Icons.keyboard_arrow_up_rounded,
                        label: 'Move forward',
                            onPressed: onMoveUp,
                          ),
                          const SizedBox(height: 8),
                          _EditToolbarButton(
                            icon: Icons.keyboard_arrow_down_rounded,
                        label: 'Move backward',
                            onPressed: onMoveDown,
                          ),
                        ],
                      ),
                      const SizedBox(width: 10),
                      _EditToolbarButton(
                        icon: Icons.keyboard_arrow_right_rounded,
                        label: 'Move right',
                        onPressed: onMoveRight,
                      ),
                      const SizedBox(width: 12),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _EditToolbarButton(icon: Icons.vertical_align_top, label: 'Raise furniture', onPressed: onRaise),
                          const SizedBox(height: 8),
                          _EditToolbarButton(icon: Icons.vertical_align_bottom, label: 'Lower furniture', onPressed: onLower),
                        ],
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
  const _EditToolbarButton({required this.icon, required this.label, required this.onPressed});

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      tooltip: label,
      onPressed: onPressed,
      icon: Icon(icon),
      style: IconButton.styleFrom(
        fixedSize: const Size(44, 44),
        iconSize: 25,
        backgroundColor: Colors.white.withValues(alpha: .5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}
