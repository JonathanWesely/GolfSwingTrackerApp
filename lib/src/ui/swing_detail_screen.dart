import 'package:flutter/material.dart';

import '../models/swing_metrics.dart';
import 'widgets/path_painter.dart';

class SwingDetailScreen extends StatelessWidget {
  final SwingMetrics swing;
  final String clubName;
  const SwingDetailScreen(
      {super.key, required this.swing, required this.clubName});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('$clubName swing')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _row('Club speed',
                      '${swing.clubSpeedMph.toStringAsFixed(1)} mph'),
                  _row('Face angle',
                      '${swing.faceAngleDeg >= 0 ? '+' : ''}${swing.faceAngleDeg.toStringAsFixed(1)}° (${swing.faceLabel})'),
                  _row('Recorded', swing.timestamp.toLocal().toString()),
                  _row('Path samples', '${swing.pathM.length}'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: SizedBox(
                height: 320,
                child: CustomPaint(
                  painter: PathPainter(
                      path: swing.pathM, impactIndex: swing.impactIndex),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: Colors.grey)),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      );
}
