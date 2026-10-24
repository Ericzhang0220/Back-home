import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'keyboard_catalog.dart';
import 'keyboard_editing.dart';

class CharacterKeyboard extends StatelessWidget {
  const CharacterKeyboard({
    super.key,
    required this.skin,
    required this.editing,
    required this.onAction,
    this.onHide,
    this.onSystem,
    this.actionLabel = 'Send',
    this.preview = false,
    this.artworkAsset,
  });
  final KeyboardSkin skin;
  final KeyboardEditing editing;
  final VoidCallback onAction;
  final VoidCallback? onHide;
  final VoidCallback? onSystem;
  final String actionLabel;
  final bool preview;
  final String? artworkAsset;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: editing,
    builder: (context, _) => LayoutBuilder(
      builder: (context, bounds) {
        final short = bounds.maxHeight < 285;
        final suggestions = editing.candidates;
        final rows = editing.emoji
            ? [
                '😊 🥰 🤍 ✨ 🌿 🌙 💕 ☀️',
                '😂 🥺 😍 🫶 💫 🌸 🎵 🐱',
                '😭 😌 🤗 😎 💛 🔥 🌊 ⭐',
              ].map((r) => r.split(' ')).toList()
            : editing.symbols
            ? [
                '1234567890'.split(''),
                ['@', '#', '\$', '%', '&', '*', '(', ')', '/'],
                ['-', '_', ':', ';', '!', '?', '.', ','],
              ]
            : [
                'qwertyuiop'.split(''),
                'asdfghjkl'.split(''),
                'zxcvbnm'.split(''),
              ];
        return ClipRRect(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(skin.radius + 6),
          ),
          child: Material(
            color: Colors.transparent,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Opacity(
                  opacity: skin.isDark ? 0.44 : 0.32,
                  child: ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 9, sigmaY: 9),
                    child: Image.asset(
                      artworkAsset ?? skin.asset,
                      fit: BoxFit.cover,
                      alignment: const Alignment(0, -0.2),
                      excludeFromSemantics: true,
                    ),
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        skin.base.withValues(alpha: 0.74),
                        skin.base.withValues(alpha: 0.90),
                      ],
                    ),
                  ),
                ),
                CustomPaint(painter: _AtmospherePainter(skin)),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    5,
                    3,
                    5,
                    preview
                        ? 5
                        : math.max(6, MediaQuery.viewPaddingOf(context).bottom),
                  ),
                  child: Column(
                    children: [
                      SizedBox(
                        height: short ? 25 : 32,
                        child: Row(
                          children: [
                            const SizedBox(width: 7),
                            Icon(skin.motif, color: skin.accent, size: 17),
                            const SizedBox(width: 7),
                            Expanded(
                              child: Text(
                                skin.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamilyFallback: ['ChetCJK'],
                                  color: skin.ink.withValues(alpha: 0.88),
                                  fontSize: 11,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                            if (onSystem != null)
                              Semantics(
                                label: 'System keyboard',
                                button: true,
                                child: IconButton(
                                  onPressed: onSystem,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints.tightFor(
                                    width: 36,
                                  ),
                                  icon: Icon(
                                    Icons.keyboard_outlined,
                                    color: skin.ink,
                                    size: 19,
                                  ),
                                ),
                              ),
                            if (onHide != null)
                              Semantics(
                                label: 'Hide keyboard',
                                button: true,
                                child: IconButton(
                                  onPressed: onHide,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints.tightFor(
                                    width: 36,
                                  ),
                                  icon: Icon(
                                    Icons.keyboard_arrow_down_rounded,
                                    color: skin.ink,
                                    size: 23,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      SizedBox(
                        height: short ? 31 : 39,
                        child: editing.pinyin.isEmpty
                            ? Row(
                                children: [
                                  const SizedBox(width: 9),
                                  Text(
                                    editing.chinese ? '拼音' : 'English',
                                    style: TextStyle(
                                      fontFamilyFallback: ['ChetCJK'],
                                      color: skin.accent,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'A little closer, one word at a time.',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontFamilyFallback: ['ChetCJK'],
                                        color: skin.ink.withValues(alpha: 0.65),
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : Row(
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                    ),
                                    child: ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxWidth: 85,
                                      ),
                                      child: Text(
                                        editing.pinyin,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontFamilyFallback: ['ChetCJK'],
                                          color: skin.accent,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: ListView(
                                      scrollDirection: Axis.horizontal,
                                      children: [
                                        for (final candidate in suggestions)
                                          TextButton(
                                            onPressed: () =>
                                                editing.choose(candidate),
                                            style: TextButton.styleFrom(
                                              foregroundColor: skin.ink,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                  ),
                                              minimumSize: const Size(30, 32),
                                            ),
                                            child: Text(
                                              candidate.text,
                                              style: const TextStyle(
                                                fontFamilyFallback: ['ChetCJK'],
                                                fontSize: 17,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                      ),
                      for (var i = 0; i < rows.length; i++)
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: i == 1 ? 11 : 0,
                            ),
                            child: Row(
                              children: [
                                if (i == 2 &&
                                    !editing.emoji &&
                                    !editing.symbols)
                                  _key(
                                    'Shift',
                                    icon: editing.capsLock
                                        ? Icons.keyboard_capslock_rounded
                                        : Icons.arrow_upward_rounded,
                                    active: editing.shifted,
                                    flex: 14,
                                    onTap: editing.shift,
                                    onLongPress: () =>
                                        editing.shift(lock: true),
                                  ),
                                for (final letter in rows[i])
                                  _key(
                                    editing.shifted && !editing.chinese
                                        ? letter.toUpperCase()
                                        : letter,
                                    flex: 10,
                                    onTap: () => editing.key(letter),
                                  ),
                                if (i == 2)
                                  _key(
                                    'Delete',
                                    icon: Icons.backspace_outlined,
                                    flex: 14,
                                    onTap: editing.backspace,
                                    repeat: true,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      Expanded(
                        child: Row(
                          children: [
                            _key(
                              editing.symbols ? 'ABC' : '123',
                              flex: 13,
                              onTap: editing.toggleSymbols,
                            ),
                            _key(
                              editing.chinese ? '中' : 'EN',
                              flex: 11,
                              onTap: editing.toggleLanguage,
                            ),
                            _key(
                              'Emoji',
                              icon: editing.emoji
                                  ? Icons.abc_rounded
                                  : Icons.sentiment_satisfied_alt_rounded,
                              flex: 10,
                              onTap: editing.toggleEmoji,
                            ),
                            _key(
                              editing.chinese ? '空格' : 'space',
                              flex: 42,
                              onTap: editing.space,
                            ),
                            _key(
                              editing.chinese ? '，' : ',',
                              flex: 9,
                              onTap: () =>
                                  editing.key(editing.chinese ? '，' : ','),
                            ),
                            _key(
                              actionLabel,
                              icon: actionLabel == 'Send'
                                  ? Icons.arrow_upward_rounded
                                  : null,
                              flex: 17,
                              active: true,
                              onTap: () {
                                editing.commitBestCandidate();
                                onAction();
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );

  Widget _key(
    String text, {
    required VoidCallback onTap,
    int flex = 10,
    IconData? icon,
    bool active = false,
    VoidCallback? onLongPress,
    bool repeat = false,
  }) => Expanded(
    flex: flex,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2.3, vertical: 3),
      child: _GlassKey(
        skin: skin,
        label: text,
        icon: icon,
        active: active,
        onTap: onTap,
        onLongPress: onLongPress,
        repeat: repeat,
      ),
    ),
  );
}

class _GlassKey extends StatefulWidget {
  const _GlassKey({
    required this.skin,
    required this.label,
    required this.active,
    required this.onTap,
    required this.repeat,
    this.icon,
    this.onLongPress,
  });
  final KeyboardSkin skin;
  final String label;
  final IconData? icon;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool repeat;
  @override
  State<_GlassKey> createState() => _GlassKeyState();
}

class _GlassKeyState extends State<_GlassKey> {
  Timer? _repeat;
  bool _pressed = false;
  @override
  void dispose() {
    _repeat?.cancel();
    super.dispose();
  }

  void _release() {
    _repeat?.cancel();
    if (mounted) setState(() => _pressed = false);
  }

  @override
  Widget build(BuildContext context) {
    final skin = widget.skin;
    final ink = widget.active
        ? (skin.accent.computeLuminance() > 0.5 ? skin.base : Colors.white)
        : skin.ink;
    return Semantics(
      button: true,
      label: widget.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: _release,
        onTapUp: (_) => _release(),
        onTap: () {
          HapticFeedback.selectionClick();
          widget.onTap();
        },
        onLongPressStart: (_) {
          if (widget.repeat) {
            widget.onTap();
            _repeat = Timer.periodic(
              const Duration(milliseconds: 70),
              (_) => widget.onTap(),
            );
          } else {
            widget.onLongPress?.call();
          }
        },
        onLongPressEnd: (_) => _release(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 70),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(skin.radius),
            color: widget.active
                ? skin.accent.withValues(alpha: _pressed ? 1 : 0.90)
                : Colors.white.withValues(
                    alpha: _pressed
                        ? 0.48
                        : skin.isDark
                        ? 0.12
                        : 0.49,
                  ),
            border: Border.all(
              color: (widget.active ? skin.accent : Colors.white).withValues(
                alpha: 0.27,
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: skin.base.withValues(alpha: 0.12),
                offset: const Offset(0, 2),
                blurRadius: 2,
              ),
            ],
          ),
          child: widget.icon != null
              ? Icon(widget.icon, size: 21, color: ink)
              : Text(
                  widget.label,
                  maxLines: 1,
                  style: TextStyle(
                    fontFamilyFallback: ['ChetCJK'],
                    color: ink,
                    fontSize: widget.label.characters.length == 1 ? 22 : 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
        ),
      ),
    );
  }
}

class _AtmospherePainter extends CustomPainter {
  _AtmospherePainter(this.skin);
  final KeyboardSkin skin;
  @override
  void paint(Canvas canvas, Size size) {
    final seed = keyboardSkins.indexOf(skin);
    final random = math.Random(seed + 41);
    final paint = Paint()
      ..color = skin.accent.withValues(alpha: 0.14)
      ..strokeWidth = 0.8;
    for (var i = 0; i < 28; i++) {
      final point = Offset(
        random.nextDouble() * size.width,
        random.nextDouble() * size.height,
      );
      switch (seed % 5) {
        case 0:
          canvas.drawCircle(point, 1 + random.nextDouble() * 2.5, paint);
        case 1:
          canvas.drawLine(point, point + const Offset(-4, 15), paint);
        case 2:
          canvas.drawLine(
            point - const Offset(3, 0),
            point + const Offset(3, 0),
            paint,
          );
          canvas.drawLine(
            point - const Offset(0, 3),
            point + const Offset(0, 3),
            paint,
          );
        case 3:
          canvas.drawOval(
            Rect.fromCenter(center: point, width: 3, height: 8),
            paint,
          );
        case 4:
          canvas.drawArc(
            Rect.fromCenter(center: point, width: 32, height: 10),
            0,
            math.pi,
            false,
            paint..style = PaintingStyle.stroke,
          );
      }
    }
    canvas.drawLine(
      const Offset(18, 0.5),
      Offset(size.width - 18, 0.5),
      Paint()..color = skin.accent.withValues(alpha: 0.5),
    );
  }

  @override
  bool shouldRepaint(_AtmospherePainter oldDelegate) =>
      oldDelegate.skin != skin;
}
