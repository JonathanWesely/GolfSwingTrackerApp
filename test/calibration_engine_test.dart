import 'package:flutter_test/flutter_test.dart';
import 'package:golf_tracker_app/src/calibration/calibration_engine.dart';

void main() {
  group('CalibrationEngine.fit', () {
    test('recovers per-club speed scale', () {
      final samples = [
        for (var i = 0; i < 6; i++)
          CalibrationSample(
            clubId: 'driver',
            sensorSpeedMph: 90.0 + i,
            sensorFaceDeg: 0,
            sensorPathDeg: (i - 3).toDouble(), // spread so path also fits
            refSpeedMph: (90.0 + i) * 1.05,
            refFaceDeg: 0,
            refPathDeg: (i - 3).toDouble(),
          ),
      ];
      final r = CalibrationEngine.fit(samples);
      expect(r.speedScaleByClub['driver'], closeTo(1.05, 1e-9));
    });

    test('keeps speed scales separate per club', () {
      final samples = [
        const CalibrationSample(
            clubId: 'driver',
            sensorSpeedMph: 100,
            sensorFaceDeg: 0,
            sensorPathDeg: 0,
            refSpeedMph: 110,
            refFaceDeg: 0,
            refPathDeg: 0),
        const CalibrationSample(
            clubId: '7i',
            sensorSpeedMph: 80,
            sensorFaceDeg: 0,
            sensorPathDeg: 0,
            refSpeedMph: 76,
            refFaceDeg: 0,
            refPathDeg: 0),
      ];
      final r = CalibrationEngine.fit(samples);
      expect(r.speedScaleByClub['driver'], closeTo(1.10, 1e-9));
      expect(r.speedScaleByClub['7i'], closeTo(0.95, 1e-9));
    });

    test('recovers path sign-flip and offset via regression', () {
      final samples = [
        for (final p in [-4.0, -2.0, 0.0, 2.0, 4.0, 6.0])
          CalibrationSample(
            clubId: 'driver',
            sensorSpeedMph: 90,
            sensorFaceDeg: 0,
            sensorPathDeg: p,
            refSpeedMph: 90,
            refFaceDeg: 0,
            refPathDeg: -1.0 * p + 2.0, // sign flip + 2° bias
          ),
      ];
      final r = CalibrationEngine.fit(samples);
      expect(r.pathSlopeReliable, isTrue);
      expect(r.calibration.pathScale, closeTo(-1.0, 1e-6));
      expect(r.calibration.pathOffset, closeTo(2.0, 1e-6));
      expect(r.pathCorrelation.abs(), closeTo(1.0, 1e-6));
      // Applying the fit reproduces the reference.
      expect(r.calibration.applyPath(3.0), closeTo(-1.0 * 3.0 + 2.0, 1e-6));
    });

    test('recovers face offset', () {
      final samples = [
        for (var i = 0; i < 5; i++)
          CalibrationSample(
            clubId: 'driver',
            sensorSpeedMph: 90,
            sensorFaceDeg: (i - 2).toDouble(),
            sensorPathDeg: (i - 2).toDouble(),
            refSpeedMph: 90,
            refFaceDeg: (i - 2).toDouble() - 0.8, // constant -0.8° bias
            refPathDeg: (i - 2).toDouble(),
          ),
      ];
      final r = CalibrationEngine.fit(samples);
      expect(r.calibration.faceOffset, closeTo(-0.8, 1e-9));
    });

    test('falls back to offset-only path fit when sensor path has no spread',
        () {
      final samples = [
        for (var i = 0; i < 5; i++)
          const CalibrationSample(
            clubId: 'driver',
            sensorSpeedMph: 90,
            sensorFaceDeg: 0,
            sensorPathDeg: 0, // no variation, like the mock
            refSpeedMph: 90,
            refFaceDeg: 0,
            refPathDeg: 1.5,
          ),
      ];
      final r = CalibrationEngine.fit(samples);
      expect(r.pathSlopeReliable, isFalse);
      expect(r.calibration.pathScale, 1.0);
      expect(r.calibration.pathOffset, closeTo(1.5, 1e-9));
    });

    test('throws on empty input', () {
      expect(() => CalibrationEngine.fit(const []), throwsArgumentError);
    });
  });
}
