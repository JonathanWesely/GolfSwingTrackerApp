import 'dart:async';
import 'dart:convert';

import '../models/swing_metrics.dart';
import 'swing_database.dart';

/// Swing archive: an in-memory list (what the UI reads, synchronously)
/// optionally mirrored to SQLite (what survives app restarts).
///
/// With no [SwingDatabase] the repository is pure in-memory — exactly the
/// old Phase 2 bring-up behavior, still used by most unit tests. With one,
/// [restore] loads the archive at startup and every mutation is written
/// through in the background (writes are fire-and-forget; the in-memory
/// state is the source of truth for the running session).
class SwingRepository {
  final SwingDatabase? _db;
  final List<SwingMetrics> _swings = [];

  SwingRepository({SwingDatabase? db}) : _db = db;

  /// Loads persisted swings (oldest-first). Call once at startup.
  Future<void> restore() async {
    final db = _db;
    if (db == null) return;
    _swings
      ..clear()
      ..addAll(await db.loadSwings());
  }

  List<SwingMetrics> get all => List.unmodifiable(_swings.reversed);

  int get count => _swings.length;

  void add(SwingMetrics m) {
    _swings.add(m);
    unawaited(_db?.insertSwing(m));
  }

  void clear() {
    _swings.clear();
    unawaited(_db?.clearSwings());
  }

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

  /// Session export for filter tuning / sharing — and the replay-data
  /// source for the Phase 3 Lens Studio prototype.
  String exportJson() => const JsonEncoder.withIndent('  ')
      .convert(_swings.map((s) => s.toJson()).toList());

  void importJson(String json) {
    final list = jsonDecode(json) as List;
    _swings
      ..clear()
      ..addAll(
          list.map((j) => SwingMetrics.fromJson(j as Map<String, dynamic>)));
    unawaited(_db?.replaceSwings(List.of(_swings)));
  }
}
