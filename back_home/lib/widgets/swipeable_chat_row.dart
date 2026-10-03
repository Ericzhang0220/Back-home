import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// A physical right swipe reveals Delete; swiping alone never deletes a chat.
class SwipeableChatRow extends StatefulWidget {
  const SwipeableChatRow({
    super.key,
    required this.child,
    required this.onDelete,
  });

  final Widget child;
  final Future<void> Function() onDelete;

  @override
  State<SwipeableChatRow> createState() => _SwipeableChatRowState();
}

class _SwipeableChatRowState extends State<SwipeableChatRow>
    with SingleTickerProviderStateMixin {
  static const _actionWidth = 88.0;
  late final _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  );
  bool _deleting = false;

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    if (_deleting) return;
    setState(() => _deleting = true);
    try {
      await widget.onDelete();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not delete the chat. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _deleting = false);
        _animation.reverse();
      }
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _animation,
    builder: (context, _) {
      final offset = _animation.value * _actionWidth;
      return ClipRect(
        child: Stack(
          children: [
            if (offset > 0)
              Positioned(
                left: 0,
                top: 5,
                bottom: 5,
                width: offset,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: OverflowBox(
                    alignment: Alignment.centerLeft,
                    minWidth: _actionWidth,
                    maxWidth: _actionWidth,
                    child: Material(
                      color: const Color(0xFFE34848),
                      child: InkWell(
                        onTap: _deleting ? null : _delete,
                        child: SizedBox(
                          width: _actionWidth,
                          child: Center(
                            child: _deleting
                                ? const CupertinoActivityIndicator(
                                    color: Colors.white,
                                  )
                                : const Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        CupertinoIcons.trash,
                                        color: Colors.white,
                                        size: 23,
                                      ),
                                      SizedBox(height: 5),
                                      Text(
                                        'Delete',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            Transform.translate(
              offset: Offset(offset, 0),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragStart: _deleting
                    ? null
                    : (_) => _animation.stop(),
                onHorizontalDragUpdate: _deleting
                    ? null
                    : (details) {
                        _animation.value =
                            (_animation.value + details.delta.dx / _actionWidth)
                                .clamp(0.0, 1.0);
                      },
                onHorizontalDragEnd: _deleting
                    ? null
                    : (details) {
                        final velocity = details.primaryVelocity ?? 0;
                        if (velocity > 250 ||
                            (velocity >= -250 && _animation.value >= 0.5)) {
                          _animation.forward();
                        } else {
                          _animation.reverse();
                        }
                      },
                onHorizontalDragCancel: _deleting
                    ? null
                    : () => _animation.reverse(),
                onTap: offset > 0 ? () => _animation.reverse() : null,
                child: AbsorbPointer(
                  absorbing: offset > 0 || _deleting,
                  child: widget.child,
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}
