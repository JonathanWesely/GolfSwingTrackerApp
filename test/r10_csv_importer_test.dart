import 'package:flutter_test/flutter_test.dart';
import 'package:golf_tracker_app/src/calibration/r10_csv_importer.dart';
import 'package:golf_tracker_app/src/models/swing_metrics.dart';
import 'package:golf_tracker_app/src/processing/quaternion.dart';

SwingMetrics sensorSwing(double speedMph, double faceDeg, double pathDeg,
        {String clubId = 'driver'}) =>
    SwingMetrics(
      timestamp: DateTime.utc(2026, 7, 8),
      clubId: clubId,
      clubSpeedMps: speedMph / 2.23694,
      faceAngleDeg: faceDeg,
      pathM: const [Vector3.zero],
      impactIndex: 0,
      clubPathDeg: pathDeg,
    );

void main() {
  group('R10CsvImporter.parse', () {
    test('parses standard-ish R10 columns', () {
      const csv = 'Club,Club Speed,Club Path,Face Angle\n'
          'Driver,95.2,-1.5,0.8\n'
          '7 Iron,82.0,2.0,-1.0\n';
      final shots = R10CsvImporter.parse(csv);
      expect(shots, hasLength(2));
      expect(shots.first.clubId, 'Driver');
      expect(shots.first.speedMph, closeTo(95.2, 1e-9));
      expect(shots.first.pathDeg, closeTo(-1.5, 1e-9));
      expect(shots.first.faceDeg, closeTo(0.8, 1e-9));
    });

    test('matches header aliases case-insensitively', () {
      const csv = 'CLUB HEAD SPEED,PATH,CLUB FACE\n90,1,2\n';
      final shots = R10CsvImporter.parse(csv);
      expect(shots, hasLength(1));
      expect(shots.single.speedMph, 90);
      expect(shots.single.pathDeg, 1);
      expect(shots.single.faceDeg, 2);
      expect(shots.single.clubId, isNull);
    });

    test('throws when a required column is missing', () {
      const csv = 'Club,Club Speed,Face Angle\nDriver,90,1\n';
      expect(() => R10CsvImporter.parse(csv), throwsFormatException);
    });

    test('skips rows with non-numeric values', () {
      const csv = 'Club Speed,Club Path,Face Angle\n90,1,2\n-,-,-\n';
      expect(R10CsvImporter.parse(csv), hasLength(1));
    });

    test('ignores blank lines and trailing whitespace', () {
      const csv = 'Club Speed,Club Path,Face Angle\n\n 90 , 1 , 2 \n\n';
      final shots = R10CsvImporter.parse(csv);
      expect(shots, hasLength(1));
      expect(shots.single.speedMph, 90);
    });
  });

  group('R10CsvImporter.pairByOrder', () {
    test('zips sensor swings with reference shots up to the shorter length',
        () {
      final swings = [
        sensorSwing(90, 0.5, -1.0),
        sensorSwing(92, -0.5, 1.0),
      ];
      final shots = R10CsvImporter.parse(
          'Club Speed,Club Path,Face Angle\n95,-2,1\n96,2,-1\n97,0,0\n');
      final pairs = R10CsvImporter.pairByOrder(swings, shots);
      expect(pairs, hasLength(2)); // min(2 swings, 3 shots)
      expect(pairs.first.sensorSpeedMph, closeTo(90, 1e-9));
      expect(pairs.first.refSpeedMph, closeTo(95, 1e-9));
      expect(pairs.first.clubId, 'driver');
    });
  });
}
