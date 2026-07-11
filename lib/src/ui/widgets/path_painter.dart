import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Garmin-style swing-path gauge.
///
/// Draws a straight vertical **gray reference line** (a perfectly straight,
/// on-target swing) and a **green line that leans** left or right by a signed
/// [deviationDeg] to show how far off the swing was: positive leans right,
/// negative leans left, ~0 sits straight up. The lean is visually amplified
/// so that a few degrees reads clearly at a glance; the exact amount is
/// printed underneath.
///
/// The caller decides what feeds it — the home and detail screens pass the
/// swing's club-path angle, so the green line shows the club's actual travel
/// direction relative to the target line.
class SwingPathGauge extends StatelessWidget {
  /// Signed deviation in degrees: positive = open / right, negative = closed
  /// / left, ~0 = straight.
  final double deviationDeg;

  /// Height of the drawn gauge (a small caption is added below it).
  final double height;

  const SwingPathGauge({
    super.key,
    required this.deviationDeg,
    this.height = 200,
  });

  @override
  Widget build(BuildContext context) {
    final mag = deviationDeg.abs();
    final square = mag < 0.5;
    final caption = square
        ? 'Square'
        : '${mag.toStringAsFixed(1)}° ${deviationDeg > 0 ? 'right' : 'left'} '
            'of straight';
    return Column(
      children: [
        SizedBox(
          height: height,
          width: double.infinity,
          child: CustomPaint(
            painter: _SwingPathPainter(deviationDeg: deviationDeg),
            child: const SizedBox.expand(),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          caption,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: square ? Colors.grey : const Color(0xFF2ECC71),
              ),
        ),
      ],
    );
  }
}

class _SwingPathPainter extends CustomPainter {
  final double deviationDeg;

  /// Deviation (deg) at which the green line reaches its maximum lean.
  static const double fullScaleDeg = 12.0;

  /// Maximum on-screen lean of the green line, in degrees from vertical.
  static const double maxVisualTiltDeg = 42.0;

  const _SwingPathPainter({required this.deviationDeg});

  @override
  void paint(Canvas canvas, Size size) {
    const topPad = 14.0;
    const bottomPad = 12.0;
    final base = Offset(size.width / 2, size.height - bottomPad);
    final length = base.dy - topPad;
    final topRef = Offset(base.dx, topPad);

    // Amplified, capped visual lean (radians). +right, -left.
    final tiltFrac =
        (deviationDeg / fullScaleDeg).clamp(-1.0, 1.0).toDouble();
    final tiltRad = tiltFrac * maxVisualTiltDeg * math.pi / 180.0;
    final end = Offset(
      base.dx + length * math.sin(tiltRad),
      base.dy - length * math.cos(tiltRad),
    );

    const green = Color(0xFF2ECC71);

    // Faint shaded wedge between the reference and the actual line.
    if (deviationDeg.abs() > 0.3) {
      final wedge = Path()
        ..moveTo(base.dx, base.dy)
        ..lineTo(topRef.dx, topRef.dy)
        ..lineTo(end.dx, end.dy)
        ..close();
      canvas.drawPath(wedge, Paint()..color = green.withValues(alpha: 0.12));
    }

    // Vertical gray reference line — a perfectly straight swing.
    canvas.drawLine(
      base,
      topRef,
      Paint()
        ..color = Colors.grey.withValues(alpha: 0.7)
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round,
    );

    // Green swing line, leaning by the (amplified) deviation.
    canvas.drawLine(
      base,
      end,
      Paint()
        ..color = green
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round,
    );

    // Impact point where both lines originate.
    canvas.drawCircle(
        base, 5, Paint()..color = Colors.white.withValues(alpha: 0.85));
  }

  @override
  bool shouldRepaint(_SwingPathPainter old) =>
      old.deviationDeg != deviationDeg;
}
