import '../models/swing_metrics.dart';
import 'calibration_engine.dart';

/// Parses a Garmin Approach R10 session export (CSV) into [ReferenceShot]s.
///
/// The R10's exact export column names haven't been confirmed against a real
/// file yet, so header matching is alias-based and forgiving: it looks for a
/// speed / path / face / club column by any of several likely names
/// (case-insensitive, trimmed). Adjust the alias lists below once a real
/// export is in hand.
///
/// Assumptions (documented so they're easy to revisit): speeds are mph and
/// angles are degrees, and the file is comma-separated without quoted commas
/// (true for numeric shot data).
class R10CsvImporter {
  static const List<String> speedAliases = [
    'club speed',
    'club head speed',
    'clubhead speed',
    'chs',
    'club speed (mph)',
  ];
  static const List<String> pathAliases = [
    'club path',
    'path',
    'club path (deg)',
  ];
  static const List<String> faceAliases = [
    'face angle',
    'club face',
    'face',
    'face angle (deg)',
    'face to target',
  ];
  static const List<String> clubAliases = ['club', 'club type', 'club name'];

  static List<ReferenceShot> parse(String csv) {
    final lines =
        csv.split(RegExp(r'\r?\n')).where((l) => l.trim().isNotEmpty).toList();
    if (lines.length < 2) return const [];

    final header =
        _splitRow(lines.first).map((h) => h.trim().toLowerCase()).toList();
    final speedCol = _findCol(header, speedAliases);
    final pathCol = _findCol(header, pathAliases);
    final faceCol = _findCol(header, faceAliases);
    final clubCol = _findCol(header, clubAliases);
    if (speedCol < 0 || pathCol < 0 || faceCol < 0) {
      throw const FormatException(
          'CSV is missing a club speed, club path, or face angle column. '
          'Check the header names against the importer aliases.');
    }

    final shots = <ReferenceShot>[];
    for (var i = 1; i < lines.length; i++) {
      final cells = _splitRow(lines[i]);
      final speed = _num(cells, speedCol);
      final path = _num(cells, pathCol);
      final face = _num(cells, faceCol);
      if (speed == null || path == null || face == null) continue;
      shots.add(ReferenceShot(
        clubId: (clubCol >= 0 && clubCol < cells.length)
            ? cells[clubCol].trim()
            : null,
        speedMph: speed,
        pathDeg: path,
        faceDeg: face,
      ));
    }
    return shots;
  }

  /// Pairs reference shots with this session's sensor swings, in order (both
  /// oldest-first). Extra rows on either side are ignored. The sensor swings
  /// should be UNCALIBRATED (reset calibration before a session) so the fit
  /// recovers absolute constants rather than an increment.
  static List<CalibrationSample> pairByOrder(
    List<SwingMetrics> sensorSwingsOldestFirst,
    List<ReferenceShot> refShots,
  ) {
    final n = sensorSwingsOldestFirst.length < refShots.length
        ? sensorSwingsOldestFirst.length
        : refShots.length;
    return <CalibrationSample>[
      for (var i = 0; i < n; i++)
        CalibrationSample(
          clubId: sensorSwingsOldestFirst[i].clubId,
          sensorSpeedMph: sensorSwingsOldestFirst[i].clubSpeedMph,
          sensorFaceDeg: sensorSwingsOldestFirst[i].faceAngleDeg,
          sensorPathDeg: sensorSwingsOldestFirst[i].clubPathDeg,
          refSpeedMph: refShots[i].speedMph,
          refFaceDeg: refShots[i].faceDeg,
          refPathDeg: refShots[i].pathDeg,
        ),
    ];
  }

  static int _findCol(List<String> header, List<String> aliases) {
    for (var i = 0; i < header.length; i++) {
      if (aliases.contains(header[i])) return i;
    }
    return -1;
  }

  static List<String> _splitRow(String line) => line.split(',');

  static double? _num(List<String> cells, int col) {
    if (col < 0 || col >= cells.length) return null;
    return double.tryParse(cells[col].trim());
  }
}
