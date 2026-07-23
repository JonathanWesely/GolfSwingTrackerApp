import 'package:flutter_test/flutter_test.dart';
import 'package:golf_tracker_app/src/calibration/calibration.dart';
import 'package:golf_tracker_app/src/models/club_profile.dart';
import 'package:golf_tracker_app/src/models/swing_metrics.dart';
import 'package:golf_tracker_app/src/processing/quaternion.dart';
import 'package:golf_tracker_app/src/storage/swing_database.dart';
import 'package:golf_tracker_app/src/storage/swing_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

SwingMetrics swing({
  double mph = 85,
  double face = 1.5,
  double clubPath = 0,
  String deviceId = 'mock-1',
  String deviceLabel = 'Jonathan',
  int sourceFlags = 0,
}) =>
    SwingMetrics(
      timestamp: DateTime.utc(2026, 7, 8, 12, 30),
      clubId: 'driver',
      clubSpeedMps: mph / 2.23694,
      faceAngleDeg: face,
      pathM: const [Vector3(0, 0, 0), Vector3(0.1, 0.2, -0.3)],
      impactIndex: 1,
      deviceId: deviceId,
      deviceLabel: deviceLabel,
      sourceFlags: sourceFlags,
      clubPathDeg: clubPath,
    );

void main() {
  sqfliteFfiInit();
  final factory = databaseFactoryFfi;

  Future<SwingDatabase> openDb() =>
      SwingDatabase.open(factory: factory, path: inMemoryDatabasePath);

  group('SwingDatabase', () {
    test('swings round-trip with full fidelity', () async {
      final db = await openDb();
      final m = swing(sourceFlags: 0x05, clubPath: -3.5);
      await db.insertSwing(m);

      final loaded = await db.loadSwings();
      expect(loaded, hasLength(1));
      final l = loaded.single;
      expect(l.timestamp, m.timestamp);
      expect(l.clubId, m.clubId);
      expect(l.deviceId, m.deviceId);
      expect(l.deviceLabel, m.deviceLabel);
      expect(l.clubSpeedMps, closeTo(m.clubSpeedMps, 1e-12));
      expect(l.faceAngleDeg, closeTo(m.faceAngleDeg, 1e-12));
      expect(l.impactIndex, m.impactIndex);
      expect(l.sourceFlags, 0x05);
      expect(l.clubPathDeg, closeTo(-3.5, 1e-12));
      expect(l.pathM.length, m.pathM.length);
      expect((l.pathM[1] - m.pathM[1]).length, lessThan(1e-12));
      await db.close();
    });

    test('loadSwings preserves insertion order (oldest first)', () async {
      final db = await openDb();
      await db.insertSwing(swing(mph: 70));
      await db.insertSwing(swing(mph: 80));
      await db.insertSwing(swing(mph: 90));
      final loaded = await db.loadSwings();
      expect([for (final s in loaded) s.clubSpeedMph.round()], [70, 80, 90]);
      await db.close();
    });

    test('clearSwings and replaceSwings', () async {
      final db = await openDb();
      await db.insertSwing(swing(mph: 70));
      await db.replaceSwings([swing(mph: 95), swing(mph: 96)]);
      expect((await db.loadSwings()).length, 2);
      await db.clearSwings();
      expect(await db.loadSwings(), isEmpty);
      await db.close();
    });

    test('clubs round-trip preserving order and edits', () async {
      final db = await openDb();
      final clubs = [
        const ClubProfile(
            id: 'driver',
            name: 'My Driver',
            shaftLengthM: 1.16,
            deviceToFaceDistanceM: 1.02),
        const ClubProfile(
            id: '7i',
            name: '7 Iron',
            shaftLengthM: 0.94,
            deviceToFaceDistanceM: 0.80),
      ];
      await db.saveClubs(clubs);
      final loaded = await db.loadClubs();
      expect([for (final c in loaded) c.id], ['driver', '7i']);
      expect(loaded.first.name, 'My Driver');
      expect(loaded.first.shaftLengthM, closeTo(1.16, 1e-12));
      expect(loaded.first.deviceToFaceDistanceM, closeTo(1.02, 1e-12));
      await db.close();
    });

    test('sensor registry round-trips', () async {
      final db = await openDb();
      await db.saveSensors(const [
        SensorRecord(
            id: 'mock-1', label: 'Jonathan', clubId: 'driver', isMock: true),
        SensorRecord(
            id: 'AA:BB:CC:11:22:33',
            label: 'Driver sensor',
            clubId: '7i',
            isMock: false),
      ]);
      final loaded = await db.loadSensors();
      expect(loaded, hasLength(2));
      expect(loaded[0].isMock, isTrue);
      expect(loaded[1].id, 'AA:BB:CC:11:22:33');
      expect(loaded[1].isMock, isFalse);
      expect(loaded[1].clubId, '7i');
      await db.close();
    });

    test('saveSensors replaces the registry (removals persist)', () async {
      final db = await openDb();
      await db.saveSensors(const [
        SensorRecord(id: 'mock-1', label: 'A', clubId: 'driver', isMock: true),
        SensorRecord(id: 'mock-2', label: 'B', clubId: 'driver', isMock: true),
      ]);
      await db.saveSensors(const [
        SensorRecord(id: 'mock-2', label: 'B', clubId: 'driver', isMock: true),
      ]);
      final loaded = await db.loadSensors();
      expect([for (final s in loaded) s.id], ['mock-2']);
      await db.close();
    });

    test('calibration round-trips (and is null before any is saved)',
        () async {
      final db = await openDb();
      expect(await db.loadCalibration(), isNull);
      await db.saveCalibration(const Calibration(
          faceOffset: -0.8, pathScale: -1.0, pathOffset: 1.2));
      final c = await db.loadCalibration();
      expect(c, isNotNull);
      expect(c!.faceOffset, closeTo(-0.8, 1e-12));
      expect(c.pathScale, closeTo(-1.0, 1e-12));
      expect(c.pathOffset, closeTo(1.2, 1e-12));
      // Replacing overwrites the single row.
      await db.saveCalibration(const Calibration(faceOffset: 0.3));
      expect((await db.loadCalibration())!.faceOffset, closeTo(0.3, 1e-12));
      await db.close();
    });
  });

  group('SwingRepository with persistence', () {
    test('add() writes through; restore() loads history newest-first via all',
        () async {
      final db = await openDb();

      final repo = SwingRepository(db: db);
      repo.add(swing(mph: 70));
      repo.add(swing(mph: 90));
      // Write-through is async fire-and-forget; give it a beat.
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // Simulate an app restart: new repository over the same database.
      final repo2 = SwingRepository(db: db);
      await repo2.restore();
      expect(repo2.count, 2);
      expect(repo2.all.first.clubSpeedMph, closeTo(90, 0.01)); // newest first
      expect(repo2.bestSpeedMph, closeTo(90, 0.01));
      await db.close();
    });

    test('clear() persists', () async {
      final db = await openDb();
      final repo = SwingRepository(db: db);
      repo.add(swing());
      await Future<void>.delayed(const Duration(milliseconds: 20));
      repo.clear();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final repo2 = SwingRepository(db: db);
      await repo2.restore();
      expect(repo2.count, 0);
      await db.close();
    });

    test('importJson replaces persisted archive', () async {
      final db = await openDb();
      final repo = SwingRepository(db: db);
      repo.add(swing(mph: 70));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final donor = SwingRepository();
      donor.add(swing(mph: 99, deviceLabel: 'Imported'));
      repo.importJson(donor.exportJson());
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final repo2 = SwingRepository(db: db);
      await repo2.restore();
      expect(repo2.count, 1);
      expect(repo2.all.single.deviceLabel, 'Imported');
      expect(repo2.all.single.clubSpeedMph, closeTo(99, 0.01));
      await db.close();
    });

    test('repository without a database stays purely in-memory', () async {
      final repo = SwingRepository();
      repo.add(swing());
      expect(repo.count, 1);
      repo.clear();
      expect(repo.count, 0);
    });
  });
}
