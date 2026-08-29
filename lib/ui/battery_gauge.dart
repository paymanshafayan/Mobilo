import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A circular progress ring that shows the battery fraction (0..1).
class BatteryGauge extends StatelessWidget {
  const BatteryGauge({
    super.key,
    required this.fraction,
    required this.color,
    this.size = 230,
    this.strokeWidth = 18,
    this.child,
  });

  /// 0.0 .. 1.0 (values outside are clamped).
  final double fraction;
  final Color color;
  final double size;
  final double strokeWidth;

  /// Widget rendered in the middle of the ring.
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final double clamped = fraction.clamp(0.0, 1.0).toDouble();
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        fit: StackFit.expand,
        alignment: Alignment.center,
        children: [
          CustomPaint(
            painter: _GaugePainter(
              fraction: clamped,
              color: color,
              strokeWidth: strokeWidth,
            ),
          ),
          if (child != null) Center(child: child),
        ],
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter({
    required this.fraction,
    required this.color,
    required this.strokeWidth,
  });

  final double fraction;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect outer = Offset.zero & size;
    final Rect arcRect = outer.deflate(strokeWidth / 2);

    final Paint track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = color.withOpacity(0.15);
    canvas.drawArc(arcRect, 0, 2 * math.pi, false, track);

    if (fraction > 0) {
      final Paint sweep = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..color = color;
      canvas.drawArc(arcRect, -math.pi / 2, 2 * math.pi * fraction, false,
          sweep);
    }
  }

  @override
  bool shouldRepaint(_GaugePainter oldDelegate) =>
      oldDelegate.fraction != fraction ||
      oldDelegate.color != color ||
      oldDelegate.strokeWidth != strokeWidth;
}
