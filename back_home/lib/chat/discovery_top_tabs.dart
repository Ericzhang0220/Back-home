import 'dart:async';

import 'package:flutter/widgets.dart';

/// Shares one reveal deadline between the tabs and Like button on both decks.
class DiscoveryControls extends StatefulWidget {
  const DiscoveryControls({
    super.key,
    required this.autoHide,
    required this.navVisible,
    required this.child,
    this.isActive = true,
  });

  final bool autoHide;
  final bool navVisible;
  final bool isActive;
  final Widget child;

  @override
  State<DiscoveryControls> createState() => _DiscoveryControlsState();
}

class _DiscoveryControlsState extends State<DiscoveryControls> {
  Timer? _revealTimer;
  bool _temporarilyVisible = false;
  bool _dismissed = false;

  /// Fingers currently down on the controls. While any are, nothing hides them.
  int _touches = 0;

  @override
  void didUpdateWidget(covariant DiscoveryControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive != widget.isActive) {
      _revealTimer?.cancel();
      _touches = 0;
      _temporarilyVisible = false;
      _dismissed = false;
    } else if (oldWidget.navVisible != widget.navVisible) {
      _dismissed = false;
      // The nav bar runs its own idle timer that knows nothing about the tabs.
      // If the person is touching the controls, or touched them recently, let
      // the tabs outlive the nav bar rather than vanish mid-use.
      if (_touches == 0 && !(_revealTimer?.isActive ?? false)) {
        _temporarilyVisible = false;
      }
    }
    if (oldWidget.autoHide != widget.autoHide) {
      _dismissed = false;
      // A list-to-portrait tap should not instantly hide the very controls the
      // person is using. Keep an existing reveal deadline across the switch;
      // otherwise give the newly entered portrait its normal reveal window.
      if (widget.autoHide &&
          !widget.navVisible &&
          widget.isActive &&
          !(_revealTimer?.isActive ?? false)) {
        _temporarilyVisible = true;
        _scheduleRevealEnd();
      }
    }
  }

  @override
  void dispose() {
    _revealTimer?.cancel();
    super.dispose();
  }

  void _reveal() {
    if (!widget.autoHide || !widget.isActive) return;
    setState(() {
      _temporarilyVisible = true;
      _dismissed = false;
    });
    _scheduleRevealEnd();
  }

  void _scheduleRevealEnd() {
    _revealTimer?.cancel();
    _revealTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _temporarilyVisible = false);
    });
  }

  /// Any touch on a visible control holds the controls up, and lifting the
  /// finger restarts the full reveal window from that moment.
  void _touchStarted() {
    if (!widget.autoHide || !widget.isActive) return;
    _touches++;
    _revealTimer?.cancel();
    if (!_temporarilyVisible) setState(() => _temporarilyVisible = true);
  }

  void _touchEnded() {
    if (_touches == 0) return;
    _touches--;
    if (_touches == 0) _scheduleRevealEnd();
  }

  void _dismiss() {
    if (!widget.autoHide || !widget.isActive) return;
    _revealTimer?.cancel();
    setState(() {
      _temporarilyVisible = false;
      _dismissed = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final visible =
        !widget.autoHide ||
        (!_dismissed && (widget.navVisible || _temporarilyVisible));
    return _DiscoveryControlsScope(
      visible: visible,
      canReveal: widget.autoHide && !visible && widget.isActive,
      canDismiss: widget.autoHide && visible && widget.isActive,
      onReveal: _reveal,
      onDismiss: _dismiss,
      onTouchStarted: _touchStarted,
      onTouchEnded: _touchEnded,
      child: widget.child,
    );
  }
}

class _DiscoveryControlsScope extends InheritedWidget {
  const _DiscoveryControlsScope({
    required this.visible,
    required this.canReveal,
    required this.canDismiss,
    required this.onReveal,
    required this.onDismiss,
    required this.onTouchStarted,
    required this.onTouchEnded,
    required super.child,
  });

  final bool visible;
  final bool canReveal;
  final bool canDismiss;
  final VoidCallback onReveal;
  final VoidCallback onDismiss;
  final VoidCallback onTouchStarted;
  final VoidCallback onTouchEnded;

  static _DiscoveryControlsScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_DiscoveryControlsScope>();

  @override
  bool updateShouldNotify(_DiscoveryControlsScope oldWidget) =>
      visible != oldWidget.visible ||
      canReveal != oldWidget.canReveal ||
      canDismiss != oldWidget.canDismiss;
}

/// Keeps a control's position while fading it with the shared portrait chrome.
class DiscoveryControlVisibility extends StatelessWidget {
  const DiscoveryControlVisibility({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final controls = _DiscoveryControlsScope.of(context);
    final visible = controls?.visible ?? true;
    return IgnorePointer(
      ignoring: !visible,
      // A Listener sees every pointer without joining the gesture arena, so the
      // buttons underneath still get their taps.
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: controls == null
            ? null
            : (_) => controls.onTouchStarted(),
        onPointerUp: controls == null ? null : (_) => controls.onTouchEnded(),
        onPointerCancel: controls == null
            ? null
            : (_) => controls.onTouchEnded(),
        child: ExcludeFocus(
          excluding: !visible,
          child: ExcludeSemantics(
            excluding: !visible,
            child: AnimatedOpacity(
              opacity: visible ? 1 : 0,
              duration: Duration(milliseconds: visible ? 260 : 180),
              curve: Curves.easeInOutCubic,
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// The hidden tab strip remains the double-tap target for all portrait controls.
class DiscoveryTopTabs extends StatefulWidget {
  const DiscoveryTopTabs({super.key, required this.child});

  final Widget child;

  @override
  State<DiscoveryTopTabs> createState() => _DiscoveryTopTabsState();
}

class _DiscoveryTopTabsState extends State<DiscoveryTopTabs> {
  double _verticalDrag = 0;

  @override
  Widget build(BuildContext context) {
    final controls = _DiscoveryControlsScope.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onVerticalDragStart: controls?.canDismiss ?? false
          ? (_) => _verticalDrag = 0
          : null,
      onVerticalDragUpdate: controls?.canDismiss ?? false
          ? (details) => _verticalDrag += details.primaryDelta ?? 0
          : null,
      onVerticalDragEnd: controls?.canDismiss ?? false
          ? (details) {
              if (_verticalDrag < -24 ||
                  (details.primaryVelocity ?? 0) < -300) {
                controls!.onDismiss();
              }
              _verticalDrag = 0;
            }
          : null,
      child: Stack(
        children: [
          DiscoveryControlVisibility(child: widget.child),
          if (controls?.canReveal ?? false)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onDoubleTap: controls!.onReveal,
              ),
            ),
        ],
      ),
    );
  }
}
