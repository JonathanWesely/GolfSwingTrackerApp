import 'dart:convert';

import '../models/swing_metrics.dart';

/// In-memory swing archive with JSON import/export.
///
/// Deliberately simple for Phase 2 bring-up. When persistence is needed,
/// replace the internals with drift/sqflite — the interface stays the same.
class SwingRepository {
  final List<SwingMetrics> _swings = [];

  List<SwingMetrics> get all => List.unmodifiable(_swings.reversed);

  int get count => _swings.length;

  void add(SwingMetrics m) => _swings.add(m);

  void clear() => _swings.clear();

  /// Swings from one sensor (per-device view).
  List<SwingMetrics> byDevice(String deviceId) => List.unmodifiable(
      _swings.reversed.where((s) => s.deviceId == deviceId));

  /// Distinct device labels present in the archive (for filter UIs);
  /// preserves labels of since-removed sensors.
  List<String> get deviceLabels =>
      {for (final s in _swings) if (s.deviceLabel.isNotEmpty) s.deviceLabel}
          .toList();

  double? get bestSpeedMph => _swings.isEmpty
      ? null
      : _swings.map((s) => s.clubSpeedMph).reduce((a, b) => a > b ? a : b);

  double? get avgSpeedMph => _swings.isEmpty
      ? null
      : _swings.map((s) => s.clubSpeedMph).reduce((a, b) => a + b) /
          _swings.length;

  /// Session export for filter tuning / sharing.
  String exportJson() => const JsonEncoder.withIndent('  ')
      .convert(_swings.map((s) => s.toJson()).toList());

  void importJson(String json) {
    final list = jsonDecode(json) as List;
    _swings
      ..clear()
      ..addAll(list.map((j) => SwingMetrics.fromJson(j as Map<String, dynamic>)));
  }
}
