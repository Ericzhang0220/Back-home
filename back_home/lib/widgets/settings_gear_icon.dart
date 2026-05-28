import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A settings gear drawn with a [CustomPainter] in a rounded outline style.
class SettingsGearIcon extends StatelessWidget {
  const SettingsGearIcon({this.size = 24, this.color, super.key});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final resolvedColor =
        color ?? IconTheme.of(context).color ?? Colors.black;
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _SettingsGearPainter(
          color: resolvedColor,
          strokeWidth: size * 0.09,
        ),
      ),
    );
  }
}

class _SettingsGearPainter extends CustomPainter {
  _SettingsGearPainter({required this.color, required this.strokeWidth});

  final Color color;
  final double strokeWidth;

  static const int _teeth = 8;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = math.min(size.width, size.height) / 2 - strokeWidth / 2;
    final tipRadius = maxRadius;
    final valleyRadius = maxRadius * 0.74;
    final holeRadius = maxRadius * 0.34;

    final anglePerTooth = (2 * math.pi) / _teeth;
    final tipHalf = anglePerTooth * 0.18;
    final valleyHalf = anglePerTooth * 0.30;

    final gear = Path();
    var started = false;
    for (var i = 0; i < _teeth; i++) {
      final c = i * anglePerTooth - math.pi / 2;
      final points = <Offset>[
        _point(center, valleyRadius, c - valleyHalf),
        _point(center, tipRadius, c - tipHalf),
        _point(center, tipRadius, c + tipHalf),
        _point(center, valleyRadius, c + valleyHalf),
      ];
      for (final p in points) {
        if (!started) {
          gear.moveTo(p.dx, p.dy);
          started = true;
        } else {
          gear.lineTo(p.dx, p.dy);
        }
      }
    }
    gear.close();

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(gear, paint);
    canvas.drawCircle(center, holeRadius, paint);
  }

  Offset _point(Offset center, double radius, double angle) {
    return Offset(
      center.dx + radius * math.cos(angle),
      center.dy + radius * math.sin(angle),
    );
  }

  @override
  bool shouldRepaint(_SettingsGearPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.strokeWidth != strokeWidth;
  }
}
