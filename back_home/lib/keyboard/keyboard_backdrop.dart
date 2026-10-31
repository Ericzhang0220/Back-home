import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'keyboard_catalog.dart';

/// Theme artwork is drawn locally; keyboards never borrow a chat's portrait.
class KeyboardBackdrop extends StatelessWidget {
  const KeyboardBackdrop({super.key, required this.skin});
  final KeyboardSkin skin;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color.lerp(skin.base, skin.accent, 0.38)!,
          skin.base,
          Color.lerp(skin.base, skin.accent, 0.15)!,
        ],
      ),
    ),
    child: CustomPaint(
      painter: _ThemeArt(skin),
      child: const SizedBox.expand(),
    ),
  );
}

class _ThemeArt extends CustomPainter {
  _ThemeArt(this.skin);
  final KeyboardSkin skin;

  @override
  void paint(Canvas canvas, Size size) {
    final seed = skin.id.codeUnits.fold<int>(
      0,
      (value, unit) => (value * 31 + unit) & 0x7fffffff,
    );
    final random = math.Random(seed);
    final paint = Paint()..style = PaintingStyle.stroke;
    for (var i = 0; i < 12; i++) {
      final center = Offset(
        random.nextDouble() * size.width,
        random.nextDouble() * size.height,
      );
      final radius = size.shortestSide * (0.15 + random.nextDouble() * 0.6);
      paint
        ..strokeWidth = i.isEven ? 1 : 12
        ..color = skin.accent.withValues(alpha: i.isEven ? 0.22 : 0.035);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        random.nextDouble() * math.pi,
        math.pi * 1.4,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_ThemeArt oldDelegate) => oldDelegate.skin != skin;
}
