import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// Passively observes reveal gestures without covering the page or claiming
/// taps, scrolling, or text selection from the controls beneath it.
class BottomNavigationReveal extends StatefulWidget {
  const BottomNavigationReveal({
    super.key,
    required this.enabled,
    required this.bottomGap,
    required this.onReveal,
    required this.child,
    this.zoneHeight = 56,
    this.allowDoubleTap = false,
  });

  final bool enabled;
  final double bottomGap;
  final double zoneHeight;
  final bool allowDoubleTap;
  final VoidCallback onReveal;
  final Widget child;

  @override
  State<BottomNavigationReveal> createState() => _BottomNavigationRevealState();
}

class _BottomNavigationRevealState extends State<BottomNavigationReveal> {
  int? _pointer;
  Offset? _start;
  Duration? _downTime;
  Offset? _lastTap;
  Duration? _lastTapTime;
  bool _startedInZone = false;
  bool _moved = false;
  final _activePointers = <int>{};

  void _reset() {
    _pointer = null;
    _start = null;
    _downTime = null;
    _moved = false;
  }

  void _clearTap() {
    _lastTap = null;
    _lastTapTime = null;
  }

  bool get _editingText {
    final context = FocusManager.instance.primaryFocus?.context;
    return context?.widget is EditableText ||
        context?.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  Duration _eventTime(PointerEvent event) => event.timeStamp == Duration.zero
      ? WidgetsBinding.instance.currentSystemFrameTimeStamp
      : event.timeStamp;

  void _up(PointerUpEvent event) {
    final time = _eventTime(event);
    _activePointers.remove(event.pointer);
    if (event.pointer != _pointer) return;
    final tapped =
        !_moved && _downTime != null && time - _downTime! < kLongPressTimeout;
    _reset();
    if (!tapped || !widget.allowDoubleTap || _editingText) {
      _clearTap();
      return;
    }
    final elapsed = _lastTapTime == null ? null : time - _lastTapTime!;
    if (elapsed != null &&
        elapsed >= kDoubleTapMinTime &&
        elapsed <= kDoubleTapTimeout &&
        (event.localPosition - _lastTap!).distance <= kDoubleTapSlop) {
      _clearTap();
      widget.onReveal();
    } else {
      _lastTap = event.localPosition;
      _lastTapTime = time;
    }
  }

  @override
  void didUpdateWidget(covariant BottomNavigationReveal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) _reset();
    if (!widget.allowDoubleTap) _clearTap();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => Listener(
        onPointerDown: (event) {
          _activePointers.add(event.pointer);
          if (_activePointers.length > 1) {
            _reset();
            _clearTap();
            return;
          }
          if (!widget.enabled && !widget.allowDoubleTap) return;
          final bottom = constraints.maxHeight - widget.bottomGap;
          final y = event.localPosition.dy;
          _startedInZone = y >= bottom - widget.zoneHeight && y <= bottom;
          _pointer = event.pointer;
          _start = event.localPosition;
          _downTime = _eventTime(event);
          _moved = false;
        },
        onPointerMove: (event) {
          if (event.pointer != _pointer) return;
          final delta = event.localPosition - _start!;
          if (delta.distance > kTouchSlop) _moved = true;
          if (widget.enabled &&
              _startedInZone &&
              delta.dy <= -24 &&
              -delta.dy > delta.dx.abs()) {
            _reset();
            _clearTap();
            widget.onReveal();
          }
        },
        onPointerUp: _up,
        onPointerCancel: (event) {
          _activePointers.remove(event.pointer);
          if (event.pointer == _pointer) _reset();
          _clearTap();
        },
        child: widget.child,
      ),
    );
  }
}
