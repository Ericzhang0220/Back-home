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

  @override
  void didUpdateWidget(covariant DiscoveryControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.navVisible != widget.navVisible ||
        oldWidget.isActive != widget.isActive) {
      _revealTimer?.cancel();
      _temporarilyVisible = false;
      _dismissed = false;
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
    required super.child,
  });

  final bool visible;
  final bool canReveal;
  final bool canDismiss;
  final VoidCallback onReveal;
  final VoidCallback onDismiss;

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
    final visible = _DiscoveryControlsScope.of(context)?.visible ?? true;
    return IgnorePointer(
      ignoring: !visible,
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
