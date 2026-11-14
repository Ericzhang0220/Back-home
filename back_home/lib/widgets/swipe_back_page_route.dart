import 'package:flutter/material.dart';

/// Allows a right swipe across the page to use the same back action as the OS.
class SwipeBackPageRoute<T> extends MaterialPageRoute<T> {
  SwipeBackPageRoute({
    required WidgetBuilder builder,
    super.settings,
    double? maxDragStartX,
  }) : super(
         builder: (context) => _SwipeBackPage(
           maxDragStartX: maxDragStartX,
           child: builder(context),
         ),
       );

  // The page-wide recognizer handles edge swipes too, so only one can pop.
  @override
  bool get popGestureEnabled => false;
}

class _SwipeBackPage extends StatefulWidget {
  const _SwipeBackPage({required this.child, this.maxDragStartX});

  final Widget child;
  final double? maxDragStartX;

  @override
  State<_SwipeBackPage> createState() => _SwipeBackPageState();
}

class _SwipeBackPageState extends State<_SwipeBackPage> {
  double _distance = 0;
  bool _enabled = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: (details) {
        _distance = 0;
        final maxDragStartX = widget.maxDragStartX;
        _enabled =
            (maxDragStartX == null ||
                details.localPosition.dx <= maxDragStartX) &&
            ModalRoute.of(context)?.isCurrent == true &&
            Navigator.of(context).canPop();
      },
      onHorizontalDragUpdate: (details) => _distance += details.delta.dx,
      onHorizontalDragCancel: () => _enabled = false,
      onHorizontalDragEnd: (details) {
        final threshold = (MediaQuery.sizeOf(context).width * 0.25).clamp(
          80.0,
          160.0,
        );
        final shouldPop =
            _enabled &&
            (_distance >= threshold ||
                (_distance >= 32 &&
                    details.velocity.pixelsPerSecond.dx >= 700));
        _enabled = false;
        if (shouldPop) {
          FocusManager.instance.primaryFocus?.unfocus();
          Navigator.of(context).maybePop();
        }
      },
      child: widget.child,
    );
  }
}
