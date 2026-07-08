import '../models/club_profile.dart';
import '../models/swing_capture.dart';
import '../models/swing_metrics.dart';
import 'quaternion.dart';

/// Turns a raw [SwingCapture] into [SwingMetrics].
///
/// Frame conventions (must match firmware mounting):
///  - Sensor +Z points DOWN the shaft toward the clubhead.
///  - Orientation quaternions map body -> world (Game Rotation Vector).
///
/// Because the BHI260AP does orientation fusion in hardware, this stage is
/// pure geometry: no Kalman/complementary filter needed on the phone.
class SwingProcessor {
  /// Shaft axis in the sensor body frame.
  static const Vector3 shaftAxis = Vector3(0, 0, 1);

  /// When true, removes linear velocity drift by constraining the
  /// end-of-capture velocity to ~zero (the golfer is essentially still at
  /// the end of the follow-through window).
  final bool endDriftCorrection;

  const SwingProcessor({this.endDriftCorrection = true});

  SwingMetrics process(
    SwingCapture capture,
    ClubProfile club, {
    String deviceId = '',
    String deviceLabel = '',
  }) {
    final samples = capture.samples;
    if (samples.length < 3) {
      throw ArgumentError('Capture too short: ${samples.length} samples');
    }
    final dt = 1.0 / capture.sampleRateHz;

    // --- 1. Impact detection: peak gyro magnitude -----------------------
    var impactIndex = 0;
    var peakOmega = 0.0;
    for (var i = 0; i < samples.length; i++) {
      final m = samples[i].gyroRadS.length;
      if (m > peakOmega) {
        peakOmega = m;
        impactIndex = i;
      }
    }

    // --- 2. Club speed: v = omega * r ------------------------------------
    final clubSpeedMps = peakOmega * club.shaftLengthM;

    // --- 3. Face angle: twist about shaft, address -> impact --------------
    // Relative rotation in the body frame: r = qAddress^-1 * qImpact.
    final rel = (capture.addressReference.conjugate *
            samples[impactIndex].orientation)
        .normalized();
    final faceAngleDeg =
        rel.twistAngleAround(shaftAxis) * 180.0 / 3.141592653589793;

    // --- 4. Path: double-integrate world-frame linear acceleration -------
    // Rotate each body-frame linear acceleration into the world frame.
    final accelWorld = <Vector3>[
      for (final s in samples) s.orientation.rotate(s.linAccel)
    ];

    // Velocity (trapezoidal), assuming v = 0 at capture start (address).
    final vel = List<Vector3>.filled(samples.length, Vector3.zero);
    for (var i = 1; i < samples.length; i++) {
      vel[i] = vel[i - 1] + (accelWorld[i] + accelWorld[i - 1]) * (dt / 2);
    }

    // ZUPT-style drift correction: any residual velocity at the end of the
    // window is integration drift — remove it as a linear ramp.
    if (endDriftCorrection) {
      final vEnd = vel.last;
      final n = samples.length - 1;
      for (var i = 1; i < samples.length; i++) {
        vel[i] = vel[i] - vEnd * (i / n);
      }
    }

    // Position (trapezoidal), origin at address.
    final path = List<Vector3>.filled(samples.length, Vector3.zero);
    for (var i = 1; i < samples.length; i++) {
      path[i] = path[i - 1] + (vel[i] + vel[i - 1]) * (dt / 2);
    }

    return SwingMetrics(
      timestamp: capture.timestamp,
      clubId: club.id,
      clubSpeedMps: clubSpeedMps,
      faceAngleDeg: faceAngleDeg,
      pathM: path,
      impactIndex: impactIndex,
      deviceId: deviceId,
      deviceLabel: deviceLabel,
      sourceFlags: capture.sourceFlags,
    );
  }
}
