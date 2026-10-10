import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../widgets/app_ui.dart';

/// The discovery conversation and its composer, above the floating navigation
/// when browsing and directly above the keyboard when editing a draft.
class DiscoveryCardContent extends StatefulWidget {
  const DiscoveryCardContent({
    super.key,
    required this.conversation,
    required this.controller,
    required this.isReplying,
    required this.onSendMessage,
    required this.keyboardOpen,
    this.navVisible = true,
    this.isInteractive = true,
  });

  final Widget conversation;
  final TextEditingController controller;
  final bool isReplying;
  final VoidCallback onSendMessage;

  /// Read above the resizing Scaffold, which removes viewInsets from its body.
  final bool keyboardOpen;
  final bool navVisible;

  /// Cards underneath the front card show a visual preview only. They must not
  /// attach another editable field to the front card's draft controller.
  final bool isInteractive;

  @override
  State<DiscoveryCardContent> createState() => _DiscoveryCardContentState();
}

class _DiscoveryCardContentState extends State<DiscoveryCardContent> {
  // Preserve the input connection, focus, selection and composing range when
  // the keyboard moves the composer between the two layouts.
  final _composerKey = GlobalKey();
  final _conversationScrollController = ScrollController();

  @override
  void dispose() {
    _conversationScrollController.dispose();
    super.dispose();
  }

  Widget _scrollableConversation() => Scrollbar(
    controller: _conversationScrollController,
    thumbVisibility: true,
    child: SingleChildScrollView(
      controller: _conversationScrollController,
      reverse: true,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: widget.conversation,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final composer = _DiscoveryComposer(
      key: _composerKey,
      controller: widget.controller,
      isReplying: widget.isReplying,
      isInteractive: widget.isInteractive,
      onSendMessage: widget.onSendMessage,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (widget.keyboardOpen) {
          // The Scaffold already removes the keyboard's height. Keep a small
          // margin here, and let longer drafts grow upward into the scrollable
          // conversation instead of retaining the navigation card's empty band.
          final top = math.min(
            12.0,
            math.max(0.0, constraints.maxHeight - 200),
          );
          final composerHeight = math.min(
            140.0,
            math.max(0.0, constraints.maxHeight - top - 24),
          );
          return Stack(
            children: [
              Positioned(
                top: top,
                left: 16,
                right: 16,
                bottom: 12,
                child: Column(
                  children: [
                    Expanded(child: _scrollableConversation()),
                    const SizedBox(height: 12),
                    ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: composerHeight),
                      child: composer,
                    ),
                  ],
                ),
              ),
            ],
          );
        }

        final safeBottom = MediaQuery.viewPaddingOf(context).bottom;
        final bottom = widget.navVisible
            ? math.max(104.0, safeBottom + 84)
            : safeBottom + 12;
        final top = math.min(
          144.0,
          math.max(0.0, constraints.maxHeight - bottom - 200),
        );
        return Stack(
          children: [
            // The profile and composer move together into the space vacated
            // by the dock, then make room again when it is swiped back up.
            AnimatedPositioned(
              duration: Duration(milliseconds: widget.navVisible ? 260 : 380),
              curve: Curves.easeInOutCubic,
              left: 16,
              right: 16,
              top: top,
              bottom: bottom,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _scrollableConversation()),
                  const SizedBox(height: 14),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 140),
                    child: composer,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DiscoveryComposer extends StatelessWidget {
  const _DiscoveryComposer({
    super.key,
    required this.controller,
    required this.isReplying,
    required this.isInteractive,
    required this.onSendMessage,
  });

  final TextEditingController controller;
  final bool isReplying;
  final bool isInteractive;
  final VoidCallback onSendMessage;

  @override
  Widget build(BuildContext context) {
    final hint = isReplying ? 'Waiting for reply' : 'Send a message';
    final decoration = InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.60),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: BorderSide.none,
      ),
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: isInteractive
              ? TextField(
                  controller: controller,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: AppColors.ink,
                  ),
                  enabled: !isReplying,
                  minLines: 1,
                  maxLines: 5,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => onSendMessage(),
                  decoration: decoration,
                )
              : InputDecorator(
                  decoration: decoration,
                  child: Text(
                    hint,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Theme.of(context).hintColor,
                    ),
                  ),
                ),
        ),
        const SizedBox(width: 8),
        IconButton.filled(
          onPressed: isInteractive && !isReplying ? onSendMessage : null,
          icon: const Icon(Icons.arrow_upward_rounded),
          tooltip: 'Send',
          style: IconButton.styleFrom(
            backgroundColor: AppColors.clay,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }
}
