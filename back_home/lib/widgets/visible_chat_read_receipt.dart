import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Acknowledges the newest incoming message only when it is actually visible
/// on the current route in the foreground. Hidden tabs and covered routes do
/// not silently clear unread badges.
class VisibleChatReadReceipt extends StatefulWidget {
  const VisibleChatReadReceipt({
    super.key,
    required this.child,
    required this.onRead,
    required this.through,
    this.enabled = true,
  });
  final Widget child;
  final DateTime? through;
  final bool enabled;
  final Future<void> Function(DateTime) onRead;

  @override
  State<VisibleChatReadReceipt> createState() => _VisibleChatReadReceiptState();
}

class _VisibleChatReadReceiptState extends State<VisibleChatReadReceipt>
    with WidgetsBindingObserver {
  DateTime? _acknowledged;
  bool _scheduled = false;
  ScrollPosition? _scrollPosition;
  ModalRoute<dynamic>? _route;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != _route) {
      _route?.animation?.removeListener(_schedule);
      _route?.secondaryAnimation?.removeListener(_schedule);
      _route = route;
      _route?.animation?.addListener(_schedule);
      _route?.secondaryAnimation?.addListener(_schedule);
    }
    final position = Scrollable.maybeOf(context)?.position;
    if (position != _scrollPosition) {
      _scrollPosition?.removeListener(_schedule);
      _scrollPosition = position;
      _scrollPosition?.addListener(_schedule);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollPosition?.removeListener(_schedule);
    _route?.animation?.removeListener(_schedule);
    _route?.secondaryAnimation?.removeListener(_schedule);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _schedule();
  }

  bool _visible() {
    if (!mounted || !widget.enabled || widget.through == null) return false;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) {
      return false;
    }
    if (ModalRoute.of(context)?.isCurrent == false) return false;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return false;
    var visible = box.localToGlobal(Offset.zero) & box.size;
    final view = View.of(context);
    final screen = MediaQuery.sizeOf(context);
    visible = visible.intersect(
      Rect.fromLTWH(
        0,
        0,
        screen.width,
        screen.height - view.viewInsets.bottom / view.devicePixelRatio,
      ),
    );
    RenderObject? ancestor = box.parent;
    while (ancestor != null && !visible.isEmpty) {
      if (ancestor is RenderOffstage && ancestor.offstage) return false;
      if (ancestor is RenderBox &&
          (ancestor is RenderAbstractViewport ||
              ancestor is RenderClipRect ||
              ancestor is RenderClipRRect)) {
        visible = visible.intersect(
          ancestor.localToGlobal(Offset.zero) & ancestor.size,
        );
      }
      ancestor = ancestor.parent;
    }
    return !visible.isEmpty;
  }

  void _schedule() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _scheduled = false;
      if (!mounted) return;
      final through = widget.through;
      if (!_visible() ||
          through == null ||
          (_acknowledged != null && !through.isAfter(_acknowledged!))) {
        return;
      }
      _acknowledged = through;
      try {
        await widget.onRead(through);
      } catch (_) {
        if (mounted && _acknowledged == through) _acknowledged = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Registers for route changes, including returning from another screen.
    ModalRoute.of(context);
    _schedule();
    return NotificationListener<ScrollNotification>(
      onNotification: (_) {
        _schedule();
        return false;
      },
      child: widget.child,
    );
  }
}
