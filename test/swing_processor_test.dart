import 'package:flutter_test/flutter_test.dart';
import 'package:golf_tracker_app/src/calibration/calibration.dart';
import 'package:golf_tracker_app/src/models/club_profile.dart';
import 'package:golf_tracker_app/src/processing/quaternion.dart';
import 'package:golf_tracker_app/src/processing/swing_processor.dart';
import 'package:golf_tracker_app/src/sensor/mock_sensor_link.dart';

void main() {
  const driver = ClubProfile(id: 'driver', name: 'Driver', shaftLengthM: 1.143);
  const processor = SwingProcessor();

  group('SwingProcessor recovers known synthetic ground truth', () {
    test('club speed within 3% of injected value', () {
      final mock = MockSensorLink(seed: 1);
      final capture = mock.generateSwing(
          clubheadSpeedMph: 80, faceAngleDeg: 0, shaftLengthM: 1.143);
      final m = processor.process(capture, driver);
      expect(m.clubSpeedMph, closeTo(80, 80 * 0.03));
    });

    test('club path reads ~straight for the laterally-clean mock swing', () {
      final mock = MockSensorLink(seed: 1);
      final capture = mock.generateSwing(
          clubheadSpeedMph: 80, faceAngleDeg: 0, shaftLengthM: 1.143);
      final m = processor.process(capture, driver);
      // The mock injects no sideways path deviation, so the recovered club
      // path must sit near zero. A large value would mean the velocity or
      // frame handling is wrong.
      expect(m.clubPathDeg.abs(), lessThan(3.0));
    });

    test('applies a calibration to face and path', () {
      final mock = MockSensorLink(seed: 2);
      final capture = mock.generateSwing(
          clubheadSpeedMph: 75, faceAngleDeg: 4.0, shaftLengthM: 1.143);
      const cal =
          Calibration(faceOffset: 2.0, pathScale: -1.0, pathOffset: 1.0);
      final raw = processor.process(capture, driver);
      final cald = processor.process(capture, driver, calibration: cal);
      expect(cald.faceAngleDeg, closeTo(raw.faceAngleDeg + 2.0, 1e-9));
      expect(cald.clubPathDeg, closeTo(-1.0 * raw.clubPathDeg + 1.0, 1e-9));
    });

    test('face angle within 0.7 degrees (open)', () {
      final mock = MockSensorLink(seed: 2);
      final capture = mock.generateSwing(
          clubheadSpeedMph: 75, faceAngleDeg: 4.0, shaftLengthM: 1.143);
      final m = processor.process(capture, driver);
      expect(m.faceAngleDeg, closeTo(4.0, 0.7));
    });

    test('face angle sign flips for closed face', () {
      final mock = MockSensorLink(seed: 3);
      final capture = mock.generateSwing(
          clubheadSpeedMph: 75, faceAngleDeg: -6.0, shaftLengthM: 1.143);
      final m = processor.process(capture, driver);
      expect(m.faceAngleDeg, closeTo(-6.0, 0.7));
    });

    test('path is a plausible arc: monotonic bounds and impact position', () {
      final mock = MockSensorLink(seed: 4);
      final capture = mock.generateSwing(
          clubheadSpeedMph: 80, faceAngleDeg: 0, shaftLengthM: 1.143);
      final m = processor.process(capture, driver);

      // Grip pivot radius in the mock is 0.75 m — path extent must be in
      // that order of magnitude (not meters of drift, not millimeters).
      var maxDist = 0.0;
      for (final p in m.pathM) {
        if (p.length > maxDist) maxDist = p.length;
      }
      expect(maxDist, greaterThan(0.4));
      expect(maxDist, lessThan(2.5));

      // Impact happens mid-capture (t=1.45 s of 2.0 s at 400 Hz).
      expect(m.impactIndex, closeTo(1.45 * 400, 20));
    });

    test('impact position recovered to within 15 cm of ground truth', () {
      final mock = MockSensorLink(seed: 5);
      final capture = mock.generateSwing(
          clubheadSpeedMph: 80, faceAngleDeg: 2.0, shaftLengthM: 1.143);
      final m = processor.process(capture, driver);

      // Mock geometry guarantees the grip returns to the address position
      // at impact (theta(tImpact) = 0), so the true impact displacement is
      // ~zero. Anything large here means integration drift.
      // (Python mirror of this pipeline recovers it to ~5 mm.)
      expect(m.pathM[m.impactIndex].length, lessThan(0.15));
    });
  });

  group('Quaternion math', () {
    test('twist decomposition extracts pure twist', () {
      final q = Quaternion.axisAngle(const Vector3(1, 0, 0), 1.2) *
          Quaternion.axisAngle(const Vector3(0, 0, 1), 0.3);
      expect(q.twistAngleAround(const Vector3(0, 0, 1)), closeTo(0.3, 1e-9));
    });

    test('rotation round-trip', () {
      final q = Quaternion.axisAngle(const Vector3(0, 1, 0), 0.7);
      final v = const Vector3(1, 2, 3);
      final back = q.conjugate.rotate(q.rotate(v));
      expect((back - v).length, lessThan(1e-9));
    });
  });
}
