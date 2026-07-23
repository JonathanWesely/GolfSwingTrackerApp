import 'dart:math' as math;

import 'calibration.dart';

/// One shot as reported by the reference device (Garmin R10).
class ReferenceShot {
  /// Optional — the R10 export may or may not tag the club.
  final String? clubId;
  final double speedMph;
  final double faceDeg;
  final double pathDeg;

  const ReferenceShot({
    this.clubId,
    required this.speedMph,
    required this.faceDeg,
    required this.pathDeg,
  });
}

/// A reference shot paired with the sensor's RAW (uncalibrated) reading for
/// the same swing. Fit these to recover the calibration constants.
class CalibrationSample {
  final String clubId;
  final double sensorSpeedMph;
  final double sensorFaceDeg;
  final double sensorPathDeg;
  final double refSpeedMph;
  final double refFaceDeg;
  final double refPathDeg;

  const CalibrationSample({
    required this.clubId,
    required this.sensorSpeedMph,
    required this.sensorFaceDeg,
    required this.sensorPathDeg,
    required this.refSpeedMph,
    required this.refFaceDeg,
    required this.refPathDeg,
  });
}

/// The fitted calibration plus diagnostics.
class CalibrationResult {
  /// Multiply each club's current effective radius
  /// (`deviceToFaceDistanceM`) by this to match the reference club speed.
  /// Keyed by clubId.
  final Map<String, double> speedScaleByClub;

  /// Face/path correction to apply to future captures.
  final Calibration calibration;

  final int sampleCount;

  /// Pearson correlation of sensor vs reference path (NaN if not fit).
  final double pathCorrelation;
  final double pathResidualRmsDeg;
  final double faceResidualRmsDeg;

  /// False when the sensor's path barely varied across samples, so only an
  /// offset (not a slope) could be fit — e.g. calibrating against the mock,
  /// which injects no lateral deviation.
  final bool pathSlopeReliable;

  const CalibrationResult({
    required this.speedScaleByClub,
    required this.calibration,
    required this.sampleCount,
    required this.pathCorrelation,
    required this.pathResidualRmsDeg,
    required this.faceResidualRmsDeg,
    required this.pathSlopeReliable,
  });
}

/// Fits calibration constants from paired sensor/reference shots.
///
///  - **Speed** → per-club scale = mean(refSpeed / sensorSpeed). Applying it
///    multiplies the club's effective radius, since speed = ω · r.
///  - **Path** → least-squares line refPath = scale·sensorPath + offset
///    (captures sign flips and bias). Falls back to offset-only when the
///    sensor path has too little spread to fit a slope.
///  - **Face** → offset = mean(refFace − sensorFace); face is ~1:1 so no
///    slope is fit.
class CalibrationEngine {
  /// Minimum spread (deg) of sensor-path values below which a slope fit is
  /// unreliable and we fall back to an offset-only path correction.
  static const double minPathSpreadDeg = 1.0;

  static CalibrationResult fit(List<CalibrationSample> samples) {
    if (samples.isEmpty) {
      throw ArgumentError('Need at least one calibration sample.');
    }

    // --- Speed: per-club mean of ref/sensor -----------------------------
    final byClub = <String, List<CalibrationSample>>{};
    for (final s in samples) {
      (byClub[s.clubId] ??= <CalibrationSample>[]).add(s);
    }
    final speedScaleByClub = <String, double>{};
    byClub.forEach((club, list) {
      final ratios = <double>[
        for (final s in list)
          if (s.sensorSpeedMph.abs() > 1e-6) s.refSpeedMph / s.sensorSpeedMph
      ];
      if (ratios.isNotEmpty) speedScaleByClub[club] = _mean(ratios);
    });

    // --- Path: linear regression ref = scale*sensor + offset ------------
    final sx = <double>[for (final s in samples) s.sensorPathDeg];
    final sy = <double>[for (final s in samples) s.refPathDeg];
    final double pathScale;
    final double pathOffset;
    final double pathR;
    final bool pathReliable;
    if (_spread(sx) >= minPathSpreadDeg && samples.length >= 2) {
      final f = _linreg(sx, sy);
      pathScale = f.slope;
      pathOffset = f.intercept;
      pathR = f.r;
      pathReliable = true;
    } else {
      pathScale = 1.0;
      pathOffset = _mean(sy) - _mean(sx);
      pathR = double.nan;
      pathReliable = false;
    }
    final pathRms = _rms(<double>[
      for (var i = 0; i < samples.length; i++)
        sy[i] - (pathScale * sx[i] + pathOffset)
    ]);

    // --- Face: offset only (face is ~1:1) -------------------------------
    final faceOffset = _mean(<double>[for (final s in samples) s.refFaceDeg]) -
        _mean(<double>[for (final s in samples) s.sensorFaceDeg]);
    final faceRms = _rms(<double>[
      for (final s in samples) s.refFaceDeg - (s.sensorFaceDeg + faceOffset)
    ]);

    return CalibrationResult(
      speedScaleByClub: speedScaleByClub,
      calibration: Calibration(
        faceScale: 1.0,
        faceOffset: faceOffset,
        pathScale: pathScale,
        pathOffset: pathOffset,
      ),
      sampleCount: samples.length,
      pathCorrelation: pathR,
      pathResidualRmsDeg: pathRms,
      faceResidualRmsDeg: faceRms,
      pathSlopeReliable: pathReliable,
    );
  }

  static double _mean(List<double> xs) =>
      xs.isEmpty ? 0 : xs.reduce((a, b) => a + b) / xs.length;

  static double _spread(List<double> xs) {
    if (xs.isEmpty) return 0;
    var lo = xs.first, hi = xs.first;
    for (final x in xs) {
      if (x < lo) lo = x;
      if (x > hi) hi = x;
    }
    return hi - lo;
  }

  static double _rms(List<double> xs) =>
      xs.isEmpty ? 0 : math.sqrt(_mean(<double>[for (final x in xs) x * x]));

  static _LinFit _linreg(List<double> x, List<double> y) {
    final n = x.length;
    final mx = _mean(x), my = _mean(y);
    var sxx = 0.0, sxy = 0.0, syy = 0.0;
    for (var i = 0; i < n; i++) {
      final dx = x[i] - mx, dy = y[i] - my;
      sxx += dx * dx;
      sxy += dx * dy;
      syy += dy * dy;
    }
    final slope = sxx == 0 ? 0.0 : sxy / sxx;
    final intercept = my - slope * mx;
    final r = (sxx == 0 || syy == 0) ? 0.0 : sxy / math.sqrt(sxx * syy);
    return _LinFit(slope, intercept, r);
  }
}

class _LinFit {
  final double slope, intercept, r;
  const _LinFit(this.slope, this.intercept, this.r);
}
