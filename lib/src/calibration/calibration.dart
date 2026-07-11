/// Correction applied to the sensor's computed face angle and club path so
/// they match a trusted reference (a Garmin Approach R10 launch monitor).
///
/// Club **speed** is calibrated separately — by adjusting each club's
/// effective radius (`ClubProfile.shaftLengthM`), see [CalibrationResult] —
/// so it does not appear here.
///
/// Applied in [SwingProcessor]:
///   calibratedFace = faceScale * rawFace + faceOffset
///   calibratedPath = pathScale * rawPath + pathOffset
class Calibration {
  final double faceScale;
  final double faceOffset;
  final double pathScale;
  final double pathOffset;

  const Calibration({
    this.faceScale = 1.0,
    this.faceOffset = 0.0,
    this.pathScale = 1.0,
    this.pathOffset = 0.0,
  });

  /// No correction — raw sensor values pass through unchanged.
  const Calibration.identity() : this();

  bool get isIdentity =>
      faceScale == 1.0 &&
      faceOffset == 0.0 &&
      pathScale == 1.0 &&
      pathOffset == 0.0;

  double applyFace(double rawFaceDeg) => faceScale * rawFaceDeg + faceOffset;
  double applyPath(double rawPathDeg) => pathScale * rawPathDeg + pathOffset;

  Map<String, dynamic> toJson() => {
        'faceScale': faceScale,
        'faceOffset': faceOffset,
        'pathScale': pathScale,
        'pathOffset': pathOffset,
      };

  factory Calibration.fromJson(Map<String, dynamic> j) => Calibration(
        faceScale: (j['faceScale'] as num?)?.toDouble() ?? 1.0,
        faceOffset: (j['faceOffset'] as num?)?.toDouble() ?? 0.0,
        pathScale: (j['pathScale'] as num?)?.toDouble() ?? 1.0,
        pathOffset: (j['pathOffset'] as num?)?.toDouble() ?? 0.0,
      );

  @override
  String toString() => 'Calibration(face ×${faceScale.toStringAsFixed(3)} '
      '+${faceOffset.toStringAsFixed(2)}°, '
      'path ×${pathScale.toStringAsFixed(3)} +${pathOffset.toStringAsFixed(2)}°)';
}
