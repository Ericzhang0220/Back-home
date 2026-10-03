import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A message bubble's long-press menu works across AI, human and tutor chats.
class CopyableMessage extends StatefulWidget {
  const CopyableMessage({
    super.key,
    required this.text,
    required this.child,
    this.enabled = true,
  });

  final String text;
  final Widget child;
  final bool enabled;

  @override
  State<CopyableMessage> createState() => _CopyableMessageState();
}

class _CopyableMessageState extends State<CopyableMessage>
    with WidgetsBindingObserver {
  var _menu = ContextMenuController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (ModalRoute.of(context)?.isCurrent == false) _menu.remove();
  }

  @override
  void didUpdateWidget(CopyableMessage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text || !widget.enabled) _menu.remove();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _menu.remove();
  }

  @override
  void dispose() {
    _menu.remove();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onLongPressStart: !widget.enabled || widget.text.isEmpty
        ? null
        : (details) {
            final box = context.findRenderObject() as RenderBox;
            final rect = box.localToGlobal(Offset.zero) & box.size;
            final text = widget.text;
            HapticFeedback.selectionClick();
            _menu.remove();
            _menu = ContextMenuController();
            _menu.show(
              context: context,
              contextMenuBuilder: (context) => Stack(
                children: [
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _menu.remove,
                      onPanStart: (_) => _menu.remove(),
                      child: const SizedBox.expand(),
                    ),
                  ),
                  AdaptiveTextSelectionToolbar.buttonItems(
                    anchors: TextSelectionToolbarAnchors(
                      primaryAnchor: Offset(
                        details.globalPosition.dx,
                        rect.top,
                      ),
                      secondaryAnchor: Offset(
                        details.globalPosition.dx,
                        rect.bottom,
                      ),
                    ),
                    buttonItems: [
                      ContextMenuButtonItem(
                        type: ContextMenuButtonType.copy,
                        onPressed: () async {
                          _menu.remove();
                          await Clipboard.setData(ClipboardData(text: text));
                        },
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
    child: widget.child,
  );
}

class UnreadBadge extends StatelessWidget {
  const UnreadBadge({super.key, required this.count, required this.child});
  final int count;
  final Widget child;

  @override
  Widget build(BuildContext context) => Badge.count(
    count: count,
    maxCount: 99,
    isLabelVisible: count > 0,
    backgroundColor: const Color(0xFFE34848),
    textColor: Colors.white,
    alignment: Alignment.topRight,
    child: child,
  );
}
