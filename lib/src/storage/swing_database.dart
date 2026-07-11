import 'dart:convert';

import 'package:sqflite_common/sqlite_api.dart';

import '../calibration/calibration.dart';
import '../models/club_profile.dart';
import '../models/swing_metrics.dart';
import '../processing/quaternion.dart';

/// A remembered sensor: enough to recreate it (and its identity) on the
/// next app launch. BLE sensors reconnect by [id] (their BLE address);
/// mock sensors are recreated as fresh simulators.
class SensorRecord {
  final String id;
  final String label;
  final String clubId;
  final bool isMock;

  const SensorRecord({
    required this.id,
    required this.label,
    required this.clubId,
    required this.isMock,
  });
}

/// SQLite persistence for the swing archive, club profiles, and the sensor
/// registry — the plan's "migrate to SQLite once field sessions need
/// persistence" step.
///
/// Deliberately imports only sqflite_common (pure Dart types), so the whole
/// class runs in plain unit tests via sqflite_common_ffi. The app opens it
/// with the real sqflite factory in main.dart; on-device this uses the
/// platform's native SQLite (Android/iOS).
class SwingDatabase {
  static const int schemaVersion = 3;

  final Database _db;
  SwingDatabase._(this._db);

  /// Opens (creating/migrating as needed). [path] may be
  /// [inMemoryDatabasePath] in tests.
  static Future<SwingDatabase> open({
    required DatabaseFactory factory,
    required String path,
  }) async {
    final db = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE swings(
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              timestamp TEXT NOT NULL,
              club_id TEXT NOT NULL,
              device_id TEXT NOT NULL DEFAULT '',
              device_label TEXT NOT NULL DEFAULT '',
              club_speed_mps REAL NOT NULL,
              face_angle_deg REAL NOT NULL,
              impact_index INTEGER NOT NULL,
              source_flags INTEGER NOT NULL DEFAULT 0,
              club_path_deg REAL NOT NULL DEFAULT 0,
              path_json TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE clubs(
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              shaft_length_m REAL NOT NULL,
              sort INTEGER NOT NULL DEFAULT 0
            )
          ''');
          await db.execute('''
            CREATE TABLE sensors(
              id TEXT PRIMARY KEY,
              label TEXT NOT NULL,
              club_id TEXT NOT NULL,
              is_mock INTEGER NOT NULL,
              sort INTEGER NOT NULL DEFAULT 0
            )
          ''');
          await db.execute('''
            CREATE TABLE calibration(
              id INTEGER PRIMARY KEY,
              face_scale REAL NOT NULL,
              face_offset REAL NOT NULL,
              path_scale REAL NOT NULL,
              path_offset REAL NOT NULL
            )
          ''');
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          // v1 -> v2: club path stored per swing.
          if (oldVersion < 2) {
            await db.execute('ALTER TABLE swings '
                'ADD COLUMN club_path_deg REAL NOT NULL DEFAULT 0');
          }
          // v2 -> v3: face/path calibration table.
          if (oldVersion < 3) {
            await db.execute('''
              CREATE TABLE calibration(
                id INTEGER PRIMARY KEY,
                face_scale REAL NOT NULL,
                face_offset REAL NOT NULL,
                path_scale REAL NOT NULL,
                path_offset REAL NOT NULL
              )
            ''');
          }
        },
      ),
    );
    return SwingDatabase._(db);
  }

  // --- Swings -------------------------------------------------------------

  Future<void> insertSwing(SwingMetrics m) async {
    await _db.insert('swings', _swingRow(m));
  }

  /// Oldest-first, matching SwingRepository's internal order.
  Future<List<SwingMetrics>> loadSwings() async {
    final rows = await _db.query('swings', orderBy: 'id ASC');
    return [for (final r in rows) _swingFromRow(r)];
  }

  Future<void> clearSwings() => _db.delete('swings').then((_) {});

  /// Replaces the whole archive (JSON import).
  Future<void> replaceSwings(List<SwingMetrics> swings) async {
    await _db.transaction((txn) async {
      await txn.delete('swings');
      final batch = txn.batch();
      for (final m in swings) {
        batch.insert('swings', _swingRow(m));
      }
      await batch.commit(noResult: true);
    });
  }

  Map<String, Object?> _swingRow(SwingMetrics m) => {
        'timestamp': m.timestamp.toIso8601String(),
        'club_id': m.clubId,
        'device_id': m.deviceId,
        'device_label': m.deviceLabel,
        'club_speed_mps': m.clubSpeedMps,
        'face_angle_deg': m.faceAngleDeg,
        'impact_index': m.impactIndex,
        'source_flags': m.sourceFlags,
        'club_path_deg': m.clubPathDeg,
        'path_json': jsonEncode(
            [for (final p in m.pathM) [p.x, p.y, p.z]]),
      };

  SwingMetrics _swingFromRow(Map<String, Object?> r) => SwingMetrics(
        timestamp: DateTime.parse(r['timestamp'] as String),
        clubId: r['club_id'] as String,
        deviceId: r['device_id'] as String? ?? '',
        deviceLabel: r['device_label'] as String? ?? '',
        clubSpeedMps: (r['club_speed_mps'] as num).toDouble(),
        faceAngleDeg: (r['face_angle_deg'] as num).toDouble(),
        impactIndex: (r['impact_index'] as num).toInt(),
        sourceFlags: (r['source_flags'] as num?)?.toInt() ?? 0,
        clubPathDeg: (r['club_path_deg'] as num?)?.toDouble() ?? 0.0,
        pathM: [
          for (final p in jsonDecode(r['path_json'] as String) as List)
            Vector3((p[0] as num).toDouble(), (p[1] as num).toDouble(),
                (p[2] as num).toDouble())
        ],
      );

  // --- Clubs ---------------------------------------------------------------

  Future<void> saveClubs(List<ClubProfile> clubs) async {
    await _db.transaction((txn) async {
      await txn.delete('clubs');
      final batch = txn.batch();
      for (var i = 0; i < clubs.length; i++) {
        batch.insert('clubs', {
          'id': clubs[i].id,
          'name': clubs[i].name,
          'shaft_length_m': clubs[i].shaftLengthM,
          'sort': i,
        });
      }
      await batch.commit(noResult: true);
    });
  }

  Future<List<ClubProfile>> loadClubs() async {
    final rows = await _db.query('clubs', orderBy: 'sort ASC');
    return [
      for (final r in rows)
        ClubProfile(
          id: r['id'] as String,
          name: r['name'] as String,
          shaftLengthM: (r['shaft_length_m'] as num).toDouble(),
        )
    ];
  }

  // --- Sensors ---------------------------------------------------------------

  Future<void> saveSensors(List<SensorRecord> sensors) async {
    await _db.transaction((txn) async {
      await txn.delete('sensors');
      final batch = txn.batch();
      for (var i = 0; i < sensors.length; i++) {
        batch.insert('sensors', {
          'id': sensors[i].id,
          'label': sensors[i].label,
          'club_id': sensors[i].clubId,
          'is_mock': sensors[i].isMock ? 1 : 0,
          'sort': i,
        });
      }
      await batch.commit(noResult: true);
    });
  }

  Future<List<SensorRecord>> loadSensors() async {
    final rows = await _db.query('sensors', orderBy: 'sort ASC');
    return [
      for (final r in rows)
        SensorRecord(
          id: r['id'] as String,
          label: r['label'] as String,
          clubId: r['club_id'] as String,
          isMock: (r['is_mock'] as num) != 0,
        )
    ];
  }

  // --- Calibration ---------------------------------------------------------

  Future<void> saveCalibration(Calibration c) async {
    await _db.insert(
      'calibration',
      {
        'id': 0,
        'face_scale': c.faceScale,
        'face_offset': c.faceOffset,
        'path_scale': c.pathScale,
        'path_offset': c.pathOffset,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Calibration?> loadCalibration() async {
    final rows = await _db.query('calibration', where: 'id = 0', limit: 1);
    if (rows.isEmpty) return null;
    final r = rows.first;
    return Calibration(
      faceScale: (r['face_scale'] as num).toDouble(),
      faceOffset: (r['face_offset'] as num).toDouble(),
      pathScale: (r['path_scale'] as num).toDouble(),
      pathOffset: (r['path_offset'] as num).toDouble(),
    );
  }

  Future<void> close() => _db.close();
}
