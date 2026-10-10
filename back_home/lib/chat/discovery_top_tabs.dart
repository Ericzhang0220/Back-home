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

  @override
  void didUpdateWidget(covariant DiscoveryControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.autoHide != widget.autoHide ||
        oldWidget.navVisible != widget.navVisible ||
        oldWidget.isActive != widget.isActive) {
      _revealTimer?.cancel();
      _temporarilyVisible = false;
    }
  }

  @override
  void dispose() {
    _revealTimer?.cancel();
    super.dispose();
  }

  void _reveal() {
    if (!widget.autoHide || widget.navVisible || !widget.isActive) return;
    _revealTimer?.cancel();
    setState(() => _temporarilyVisible = true);
    _revealTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _temporarilyVisible = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final visible =
        !widget.autoHide || widget.navVisible || _temporarilyVisible;
    return _DiscoveryControlsScope(
      visible: visible,
      canReveal: widget.autoHide && !visible && widget.isActive,
      onReveal: _reveal,
      child: widget.child,
    );
  }
}

class _DiscoveryControlsScope extends InheritedWidget {
  const _DiscoveryControlsScope({
    required this.visible,
    required this.canReveal,
    required this.onReveal,
    required super.child,
  });

  final bool visible;
  final bool canReveal;
  final VoidCallback onReveal;

  static _DiscoveryControlsScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_DiscoveryControlsScope>();

  @override
  bool updateShouldNotify(_DiscoveryControlsScope oldWidget) =>
      visible != oldWidget.visible || canReveal != oldWidget.canReveal;
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
            duration: Duration(milliseconds: visible ? 260 : 380),
            curve: Curves.easeInOutCubic,
            child: child,
          ),
        ),
      ),
    );
  }
}

/// The hidden tab strip remains the double-tap target for all portrait controls.
class DiscoveryTopTabs extends StatelessWidget {
  const DiscoveryTopTabs({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final controls = _DiscoveryControlsScope.of(context);
    return Stack(
      children: [
        DiscoveryControlVisibility(child: child),
        if (controls?.canReveal ?? false)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onDoubleTap: controls!.onReveal,
            ),
          ),
      ],
    );
  }
}
