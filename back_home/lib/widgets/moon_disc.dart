import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../rooms/moon_state.dart';

class MoonDisc extends StatelessWidget {
  const MoonDisc({super.key, required this.moon, this.cloudOpacity = 1});
  final MoonState moon;
  final double cloudOpacity;
  @override
  Widget build(BuildContext context) => Semantics(
    label:
        '${moon.label}, ${(moon.illuminated * 100).round()}% illuminated${moon.eclipse == LunarEclipse.none ? '' : ', ${moon.eclipse.name} lunar eclipse'}',
    child: Opacity(
      opacity: cloudOpacity,
      child: CustomPaint(painter: MoonDiscPainter(moon)),
    ),
  );
}

class MoonDiscPainter extends CustomPainter {
  const MoonDiscPainter(this.moon);
  final MoonState moon;
  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.shortestSide / 2;
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    if (moon.southernHemisphere) canvas.rotate(math.pi);
    final disc = Rect.fromCircle(center: Offset.zero, radius: radius);
    final path = illuminatedPath(radius, moon.progress);
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0x55E7E1C9)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * .28),
    );
    canvas.drawPath(path, Paint()..color = const Color(0xFFE2E0D2));
    canvas.save();
    canvas.clipPath(Path()..addOval(disc));
    switch (moon.eclipse) {
      case LunarEclipse.none:
        break;
      case LunarEclipse.penumbral:
        canvas.drawOval(
          disc,
          Paint()
            ..color = Colors.black.withValues(
              alpha: .35 * moon.eclipseCoverage,
            ),
        );
      case LunarEclipse.partial:
        final shadow = Offset(radius * (2 - 2 * moon.eclipseCoverage), 0);
        canvas.drawCircle(
          shadow,
          radius,
          Paint()..color = const Color(0xFF452622),
        );
      case LunarEclipse.total:
        canvas.drawOval(
          disc,
          Paint()
            ..shader = const RadialGradient(
              colors: [Color(0xFFB86B44), Color(0xFF552B28)],
            ).createShader(disc),
        );
    }
    canvas.restore();
    canvas.restore();
  }

  /// The terminator is a projected ellipse, giving a continuous crescent →
  /// half-disc → gibbous shape without a separate hard-coded icon per day.
  static Path illuminatedPath(double radius, double progress) {
    final waxing = progress <= .5;
    final terminator = math.cos(progress * 2 * math.pi);
    final path = Path();
    for (var step = 0; step <= 120; step++) {
      final y = -1 + step / 60;
      final edge = math.sqrt(math.max(0, 1 - y * y));
      final x = (waxing ? 1 : -1) * edge * radius;
      if (step == 0) {
        path.moveTo(x, y * radius);
      } else {
        path.lineTo(x, y * radius);
      }
    }
    for (var step = 120; step >= 0; step--) {
      final y = -1 + step / 60;
      final edge = math.sqrt(math.max(0, 1 - y * y));
      path.lineTo((waxing ? 1 : -1) * terminator * edge * radius, y * radius);
    }
    return path..close();
  }

  @override
  bool shouldRepaint(MoonDiscPainter oldDelegate) => oldDelegate.moon != moon;
}
