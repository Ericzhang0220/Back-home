import 'package:flutter/widgets.dart';

/// Observes an upward swipe without covering the controls beneath it or
/// claiming their tap, double-tap, or text-selection gestures.
class BottomNavigationReveal extends StatefulWidget {
  const BottomNavigationReveal({
    super.key,
    required this.enabled,
    required this.bottomGap,
    required this.onReveal,
    required this.child,
    this.zoneHeight = 56,
  });

  final bool enabled;
  final double bottomGap;
  final double zoneHeight;
  final VoidCallback onReveal;
  final Widget child;

  @override
  State<BottomNavigationReveal> createState() => _BottomNavigationRevealState();
}

class _BottomNavigationRevealState extends State<BottomNavigationReveal> {
  int? _pointer;
  Offset? _start;

  void _reset() {
    _pointer = null;
    _start = null;
  }

  @override
  void didUpdateWidget(covariant BottomNavigationReveal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) _reset();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => Listener(
        onPointerDown: (event) {
          if (!widget.enabled || _pointer != null) return;
          final bottom = constraints.maxHeight - widget.bottomGap;
          final y = event.localPosition.dy;
          if (y >= bottom - widget.zoneHeight && y <= bottom) {
            _pointer = event.pointer;
            _start = event.localPosition;
          }
        },
        onPointerMove: (event) {
          if (!widget.enabled || event.pointer != _pointer) return;
          final delta = event.localPosition - _start!;
          if (delta.dy <= -24 && -delta.dy > delta.dx.abs()) {
            _reset();
            widget.onReveal();
          }
        },
        onPointerUp: (event) {
          if (event.pointer == _pointer) _reset();
        },
        onPointerCancel: (event) {
          if (event.pointer == _pointer) _reset();
        },
        child: widget.child,
      ),
    );
  }
}
