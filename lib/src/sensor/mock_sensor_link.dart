import 'dart:async';
import 'dart:math' as math;

import '../models/swing_capture.dart';
import '../processing/quaternion.dart';
import 'gatt_protocol.dart';
import 'sensor_link.dart';

/// Simulated Nicla Sense ME.
///
/// Generates physically self-consistent swings: a parametric grip-end path
/// and orientation profile are differentiated to produce exactly the gyro
/// and linear-acceleration streams a real sensor would emit (plus noise).
/// Because ground truth is known, the processing pipeline can be validated
/// end-to-end before hardware arrives.
class MockSensorLink implements SensorLink {
  static const double sampleRateHz = 400;

  final _statusCtrl = StreamController<SensorStatus>.broadcast();
  final _swingCtrl = StreamController<SwingCapture>.broadcast();
  final _instantCtrl = StreamController<InstantMetrics>.broadcast();
  final _batteryCtrl = StreamController<double>.broadcast();
  final math.Random _rng;

  SensorStatus _status = SensorStatus.disconnected;

  /// Gaussian noise sigmas approximating BHI260AP output noise.
  final double gyroNoiseRadS;
  final double accelNoiseMs2;

  MockSensorLink({int seed = 42, this.gyroNoiseRadS = 0.02, this.accelNoiseMs2 = 0.05})
      : _rng = math.Random(seed);

  @override
  SensorStatus get status => _status;

  @override
  Stream<SensorStatus> get statusStream => _statusCtrl.stream;

  @override
  Stream<SwingCapture> get swings => _swingCtrl.stream;

  @override
  Stream<InstantMetrics> get instantMetrics => _instantCtrl.stream;

  @override
  Stream<double> get batteryLevel => _batteryCtrl.stream;

  void _setStatus(SensorStatus s) {
    if (_statusCtrl.isClosed) return; // disposed mid-delay
    _status = s;
    _statusCtrl.add(s);
  }

  @override
  Future<void> connect() async {
    _setStatus(SensorStatus.connecting);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    _setStatus(SensorStatus.connected);
    _batteryCtrl.add(0.87);
  }

  @override
  Future<void> disconnect() async => _setStatus(SensorStatus.disconnected);

  @override
  Future<void> calibrateAddress() async {
    _setStatus(SensorStatus.calibrating);
    await Future<void>.delayed(const Duration(seconds: 1));
    _setStatus(SensorStatus.connected);
  }

  @override
  Future<void> arm() async => _setStatus(SensorStatus.armed);

  Timer? _autoTimer;

  bool get autoSwinging => _autoTimer != null;

  /// Hands-free demo: emits a randomized swing every [interval] while armed.
  /// [shaftLengthM] is read per-swing so club reassignment takes effect live.
  void startAutoSwings({
    Duration interval = const Duration(seconds: 6),
    required double Function() shaftLengthM,
  }) {
    _autoTimer?.cancel();
    _autoTimer = Timer.periodic(interval, (_) {
      if (_status != SensorStatus.armed) return;
      simulateSwing(
        clubheadSpeedMph: 68 + _rng.nextDouble() * 32,
        faceAngleDeg: -5 + _rng.nextDouble() * 10,
        shaftLengthM: shaftLengthM(),
      );
    });
  }

  void stopAutoSwings() {
    _autoTimer?.cancel();
    _autoTimer = null;
  }

  /// Triggers a synthetic swing. UI calls this from a "Simulate swing"
  /// button; tests call [generateSwing] directly for determinism.
  ///
  /// Mirrors real firmware timing: the instant-metrics packet arrives
  /// first (impact + <500 ms), then the full capture burst after a short
  /// simulated BLE transfer delay.
  Future<void> simulateSwing({
    double clubheadSpeedMph = 80,
    double faceAngleDeg = 2.0,
    double shaftLengthM = 1.143,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final capture = generateSwing(
      clubheadSpeedMph: clubheadSpeedMph,
      faceAngleDeg: faceAngleDeg,
      shaftLengthM: shaftLengthM,
    );

    // Instant metrics: what firmware knows the moment impact is detected.
    var peakOmega = 0.0;
    var peakT = 0.0;
    for (final s in capture.samples) {
      final m = s.gyroRadS.length;
      if (m > peakOmega) {
        peakOmega = m;
        peakT = s.t;
      }
    }
    _instantCtrl.add(InstantMetrics(
      tUs: (peakT * 1e6).round(),
      peakOmegaRadS: peakOmega,
      faceAngleDeg: faceAngleDeg,
      sourceFlags: capture.sourceFlags,
    ));

    // Full burst lands ~0.4 s later (real BLE takes ~2–4 s).
    await Future<void>.delayed(const Duration(milliseconds: 400));
    _swingCtrl.add(capture);
    _setStatus(SensorStatus.connected);
  }

  double _gauss(double sigma) {
    // Box-Muller
    final u1 = _rng.nextDouble().clamp(1e-12, 1.0);
    final u2 = _rng.nextDouble();
    return sigma * math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2);
  }

  /// Raised-cosine lobe helper: 0 at [a] and [b], [peak] in the middle...
  /// asymmetric: peak position controlled by [peakT].
  static double _lobe(double t, double a, double peakT, double b, double peak) {
    if (t <= a || t >= b) return 0;
    if (t <= peakT) {
      final u = (t - a) / (peakT - a);
      return peak * 0.5 * (1 - math.cos(math.pi * u));
    }
    final u = (t - peakT) / (b - peakT);
    return peak * 0.5 * (1 + math.cos(math.pi * u));
  }

  /// Smoothstep 0->1 between [a] and [b].
  static double _smooth(double t, double a, double b) {
    if (t <= a) return 0;
    if (t >= b) return 1;
    final u = (t - a) / (b - a);
    return u * u * (3 - 2 * u);
  }

  /// Builds one capture. Timeline (seconds):
  ///   0.00–0.30 address (still)
  ///   0.30–1.10 backswing (negative omega lobe)
  ///   1.10–1.45 downswing (positive lobe peaking AT impact t=1.45)
  ///   1.45–2.00 follow-through (decaying lobe)
  SwingCapture generateSwing({
    required double clubheadSpeedMph,
    required double faceAngleDeg,
    required double shaftLengthM,
  }) {
    const tImpact = 1.45;
    const tEnd = 2.0;
    final dt = 1.0 / sampleRateHz;
    final n = (tEnd * sampleRateHz).round() + 1;

    final omegaPeak = (clubheadSpeedMph / 2.23694) / shaftLengthM; // rad/s
    // Backswing peak scaled so total backswing rotation equals the
    // downswing rotation up to impact — i.e. the club RETURNS TO THE
    // ADDRESS POSITION at impact, like a real swing. (Validated: with
    // this ratio, theta(tImpact) = 0 to within integration error.)
    final omegaBack = -omegaPeak * 0.4375;
    final faceRad = faceAngleDeg * math.pi / 180.0;

    // Swing-plane rotation rate profile theta'(t) (about world X axis):
    // backswing lobe (negative), then downswing lobe peaking AT impact
    // and decaying through the follow-through.
    double thetaDot(double t) =>
        _lobe(t, 0.30, 0.80, 1.10, omegaBack) +
        _lobe(t, 1.10, tImpact, tImpact + 0.35, omegaPeak);

    // Face twist phi(t) about body Z: ramps during downswing, completes
    // slightly BEFORE impact so phi' doesn't inflate |gyro| at the peak.
    double phi(double t) => faceRad * _smooth(t, 1.12, tImpact - 0.03);

    // Integrate theta numerically (trapezoid) and build orientation, path.
    final thetas = List<double>.filled(n, 0);
    for (var i = 1; i < n; i++) {
      final t0 = (i - 1) * dt, t1 = i * dt;
      thetas[i] = thetas[i - 1] + (thetaDot(t0) + thetaDot(t1)) * dt / 2;
    }

    const swingAxis = Vector3(1, 0, 0); // world X = swing plane normal
    const gripRadius = 0.75; // m, pivot (sternum) to grip end

    // Grip path: circle of radius gripRadius about a fixed pivot in the
    // world Y-Z plane. theta = 0 puts the grip at the bottom of the arc.
    Vector3 gripPos(double theta) => Vector3(
        0, gripRadius * math.sin(theta), -gripRadius * math.cos(theta));

    final orientations = List<Quaternion>.filled(n, Quaternion.identity);
    final positions = List<Vector3>.filled(n, Vector3.zero);
    for (var i = 0; i < n; i++) {
      final t = i * dt;
      orientations[i] = (Quaternion.axisAngle(swingAxis, thetas[i]) *
              Quaternion.axisAngle(const Vector3(0, 0, 1), phi(t)))
          .normalized();
      positions[i] = gripPos(thetas[i]);
    }

    // World acceleration: second central difference of the path.
    final accelWorld = List<Vector3>.filled(n, Vector3.zero);
    for (var i = 1; i < n - 1; i++) {
      accelWorld[i] =
          (positions[i + 1] - positions[i] * 2 + positions[i - 1]) *
              (1 / (dt * dt));
    }

    // Body-frame gyro: q^-1 * (theta' * X) + phi' * Z.
    final samples = <SensorSample>[];
    for (var i = 0; i < n; i++) {
      final t = i * dt;
      final phiDot =
          (phi(math.min(t + dt, tEnd)) - phi(math.max(t - dt, 0))) / (2 * dt);
      final gyroBody =
          orientations[i].conjugate.rotate(swingAxis * thetaDot(t)) +
              Vector3(0, 0, phiDot);
      final accelBody = orientations[i].conjugate.rotate(accelWorld[i]);
      samples.add(SensorSample(
        t: t,
        orientation: orientations[i],
        gyroRadS: gyroBody +
            Vector3(_gauss(gyroNoiseRadS), _gauss(gyroNoiseRadS),
                _gauss(gyroNoiseRadS)),
        linAccel: accelBody +
            Vector3(_gauss(accelNoiseMs2), _gauss(accelNoiseMs2),
                _gauss(accelNoiseMs2)),
      ));
    }

    return SwingCapture(
      timestamp: DateTime.now(),
      sampleRateHz: sampleRateHz,
      addressReference: orientations[0], // captured during address hold
      samples: samples,
    );
  }

  @override
  void dispose() {
    stopAutoSwings();
    _statusCtrl.close();
    _swingCtrl.close();
    _instantCtrl.close();
    _batteryCtrl.close();
  }
}
