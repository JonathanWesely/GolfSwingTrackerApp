import '../processing/quaternion.dart';

/// One fused sensor sample from the Nicla Sense ME (BHI260AP virtual sensors).
class SensorSample {
  /// Seconds since capture start.
  final double t;

  /// Game Rotation Vector: body -> world orientation (mag-free 6-axis fusion).
  final Quaternion orientation;

  /// Raw gyro, body frame, rad/s.
  final Vector3 gyroRadS;

  /// Hardware Linear Acceleration (gravity removed), body frame, m/s^2.
  final Vector3 linAccel;

  const SensorSample({
    required this.t,
    required this.orientation,
    required this.gyroRadS,
    required this.linAccel,
  });
}

/// A complete captured swing window (~1.5 s pre-impact to ~0.5 s post),
/// delivered by the sensor as a post-impact BLE burst.
class SwingCapture {
  final DateTime timestamp;
  final double sampleRateHz;

  /// Orientation captured during the 1 s static address hold.
  /// Face angle is measured relative to this reference.
  final Quaternion addressReference;

  final List<SensorSample> samples;

  /// Source/quality flags (docs/BLE_PROTOCOL.md): bit0 = BHY2 fallback
  /// capture, bit1 = ICM present but failed quality checks, bit2 = gyro
  /// saturation detected (speed extrapolated).
  final int sourceFlags;

  const SwingCapture({
    required this.timestamp,
    required this.sampleRateHz,
    required this.addressReference,
    required this.samples,
    this.sourceFlags = 0,
  });

  bool get isFallbackCapture => sourceFlags & 0x01 != 0;
  bool get failedQualityChecks => sourceFlags & 0x02 != 0;
  bool get speedExtrapolated => sourceFlags & 0x04 != 0;
}
