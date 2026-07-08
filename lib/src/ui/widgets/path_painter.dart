import 'package:flutter/material.dart';

import '../../processing/quaternion.dart';

/// Draws the grip-end swing path projected onto the world Y-Z plane
/// (down-the-line view: Y = toward target, Z = up), with the impact
/// point highlighted.
class PathPainter extends CustomPainter {
  final List<Vector3> path;
  final int impactIndex;
  final Color lineColor;
  final Color impactColor;

  PathPainter({
    required this.path,
    required this.impactIndex,
    this.lineColor = Colors.tealAccent,
    this.impactColor = Colors.amber,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (path.length < 2) return;

    // Bounds in projection plane (y horizontal, z vertical).
    var minY = path.first.y, maxY = path.first.y;
    var minZ = path.first.z, maxZ = path.first.z;
    for (final p in path) {
      if (p.y < minY) minY = p.y;
      if (p.y > maxY) maxY = p.y;
      if (p.z < minZ) minZ = p.z;
      if (p.z > maxZ) maxZ = p.z;
    }
    final spanY = (maxY - minY).clamp(0.01, double.infinity);
    final spanZ = (maxZ - minZ).clamp(0.01, double.infinity);
    final scale = 0.85 *
        (size.width / spanY < size.height / spanZ
            ? size.width / spanY
            : size.height / spanZ);

    Offset project(Vector3 p) => Offset(
          size.width / 2 + (p.y - (minY + maxY) / 2) * scale,
          size.height / 2 - (p.z - (minZ + maxZ) / 2) * scale,
        );

    // Fading trail: older = more transparent.
    for (var i = 1; i < path.length; i++) {
      final t = i / path.length;
      final paint = Paint()
        ..color = lineColor.withValues(alpha: 0.15 + 0.85 * t)
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(project(path[i - 1]), project(path[i]), paint);
    }

    // Impact marker.
    if (impactIndex > 0 && impactIndex < path.length) {
      canvas.drawCircle(project(path[impactIndex]), 6,
          Paint()..color = impactColor);
      canvas.drawCircle(
          project(path[impactIndex]),
          10,
          Paint()
            ..color = impactColor.withValues(alpha: 0.4)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2);
    }
  }

  @override
  bool shouldRepaint(PathPainter old) =>
      old.path != path || old.impactIndex != impactIndex;
}
