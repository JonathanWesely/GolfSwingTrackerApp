import 'dart:async';

import 'package:flutter/foundation.dart';

import 'models/club_profile.dart';
import 'models/swing_metrics.dart';
import 'processing/swing_processor.dart';
import 'sensor/ble_sensor_link.dart';
import 'sensor/ble_transport.dart';
import 'sensor/flutter_blue_plus_transport.dart';
import 'sensor/gatt_protocol.dart';
import 'sensor/mock_sensor_link.dart';
import 'sensor/sensor_link.dart';
import 'storage/swing_database.dart';
import 'storage/swing_repository.dart';

/// One connected (or simulated) sensor with a user-assigned identity.
///
/// Identity model: the [id] is stable hardware identity (BLE remoteId, or a
/// mock counter); the [label] is whatever the user wants to see — a player's
/// name ("Jonathan") or a club's ("Driver sensor"). Each sensor also carries
/// its own [club] profile so swings are scaled with the right shaft length.
class ConnectedSensor {
  final String id;
  final SensorLink link;
  String label;
  ClubProfile club;
  SensorStatus status = SensorStatus.disconnected;
  double? battery;
  final List<StreamSubscription<dynamic>> _subs = [];

  ConnectedSensor({
    required this.id,
    required this.link,
    required this.label,
    required this.club,
  });

  bool get isMock => link is MockSensorLink;

  SensorRecord toRecord() =>
      SensorRecord(id: id, label: label, clubId: club.id, isMock: isMock);

  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    link.dispose();
  }
}

/// An instant-metrics packet waiting for its full capture — what a HUD
/// would show <500 ms after impact, while the burst is still transferring.
class PendingInstant {
  final String sensorId;
  final String sensorLabel;
  final ClubProfile club;
  final InstantMetrics metrics;

  const PendingInstant({
    required this.sensorId,
    required this.sensorLabel,
    required this.club,
    required this.metrics,
  });

  double get clubSpeedMph => metrics.clubSpeedMph(club.shaftLengthM);
  double get faceAngleDeg => metrics.faceAngleDeg;
}

/// App-wide state: a list of sensors feeding one shared swing archive.
/// Swings are tagged with the source sensor's id + label, so per-device
/// views are just filters over the repository.
///
/// With a [SwingDatabase] (production: see main.dart), swings, club
/// profiles, and the sensor registry all survive restarts — construct via
/// [AppState.restore]. Without one (most tests), everything is in-memory.
class AppState extends ChangeNotifier {
  final SwingDatabase? _db;
  final SwingRepository repository;
  final SwingProcessor _processor = const SwingProcessor();
  final List<ClubProfile> clubs = List.of(ClubProfile.defaults);
  final List<ConnectedSensor> sensors = [];

  /// Builds the BLE transport for real sensors (overridable in tests).
  final BleTransport Function() bleTransportFactory;

  SwingMetrics? latestSwing;

  /// Set the moment a sensor reports impact; cleared when that sensor's
  /// full capture arrives and is processed into [latestSwing].
  PendingInstant? pendingInstant;

  int _mockCounter = 0;

  /// Hands-free mode (default ON): sensors auto-connect when added and
  /// auto-(re)arm whenever they reach `connected` — including right after
  /// each capture — so swings stream in with zero button presses.
  bool handsFree = true;

  AppState({
    bool startWithMock = true,
    SwingDatabase? db,
    BleTransport Function()? bleTransportFactory,
  })  : _db = db,
        repository = SwingRepository(db: db),
        bleTransportFactory =
            bleTransportFactory ?? (() => FlutterBluePlusTransport()) {
    if (startWithMock) addMockSensor();
  }

  /// Production startup: restores the swing archive, club profiles, and
  /// sensor registry from [db]. Falls back to defaults (one simulated
  /// sensor) on first launch — or if the database can't be read.
  static Future<AppState> restore({
    required SwingDatabase db,
    BleTransport Function()? bleTransportFactory,
  }) async {
    final state = AppState(
      startWithMock: false,
      db: db,
      bleTransportFactory: bleTransportFactory,
    );
    try {
      await state.repository.restore();

      final storedClubs = await db.loadClubs();
      if (storedClubs.isNotEmpty) {
        state.clubs
          ..clear()
          ..addAll(storedClubs);
      }

      for (final rec in await db.loadSensors()) {
        state._restoreSensor(rec);
      }
    } catch (e) {
      debugPrint('AppState.restore: starting fresh ($e)');
    }
    if (state.sensors.isEmpty) state.addMockSensor();
    return state;
  }

  ClubProfile _clubById(String id) =>
      clubs.where((c) => c.id == id).firstOrNull ?? clubs.first;

  void _restoreSensor(SensorRecord rec) {
    final ConnectedSensor sensor;
    if (rec.isMock) {
      final n = int.tryParse(rec.id.replaceFirst('mock-', '')) ?? 0;
      if (n > _mockCounter) _mockCounter = n;
      sensor = ConnectedSensor(
        id: rec.id,
        link: MockSensorLink(seed: 40 + n),
        label: rec.label,
        club: _clubById(rec.clubId),
      );
    } else {
      sensor = ConnectedSensor(
        id: rec.id,
        link: BleSensorLink(
            targetRemoteId: rec.id, transport: bleTransportFactory()),
        label: rec.label,
        club: _clubById(rec.clubId),
      );
    }
    _wire(sensor);
    sensors.add(sensor);
    if (handsFree) unawaited(_tryConnect(sensor));
    notifyListeners();
  }

  /// Connect, swallowing failures (sensor may be off / out of range —
  /// status stays `disconnected` and the card offers a Connect button).
  Future<void> _tryConnect(ConnectedSensor s) async {
    try {
      await s.link.connect();
    } catch (_) {/* reflected in status stream */}
  }

  /// Adds a simulated sensor (works with no hardware).
  ConnectedSensor addMockSensor() {
    _mockCounter++;
    final sensor = ConnectedSensor(
      id: 'mock-$_mockCounter',
      link: MockSensorLink(seed: 40 + _mockCounter),
      label: 'Sensor $_mockCounter',
      club: clubs.first,
    );
    _wire(sensor);
    sensors.add(sensor);
    if (handsFree) unawaited(_tryConnect(sensor));
    _saveSensors();
    notifyListeners();
    return sensor;
  }

  /// Adds a real sensor by BLE identity. With multiple devices advertising
  /// the same name, the remoteId (BLE address) is what tells them apart.
  ConnectedSensor addBleSensor({String? remoteId, String? label}) {
    final sensor = ConnectedSensor(
      id: remoteId ?? 'ble-pending-${sensors.length}',
      link: BleSensorLink(
          targetRemoteId: remoteId, transport: bleTransportFactory()),
      label: label ?? 'GolfTracker ${sensors.length + 1}',
      club: clubs.first,
    );
    _wire(sensor);
    sensors.add(sensor);
    if (handsFree) unawaited(_tryConnect(sensor));
    _saveSensors();
    notifyListeners();
    return sensor;
  }

  /// True if a sensor with this BLE identity is already in the list.
  bool hasSensor(String remoteId) => sensors.any((s) => s.id == remoteId);

  void _wire(ConnectedSensor s) {
    s._subs.add(s.link.statusStream.listen((st) {
      s.status = st;
      // Hands-free: (re)arm whenever the sensor settles at `connected` —
      // on first connect, after calibration, and after every capture.
      if (handsFree && st == SensorStatus.connected) {
        unawaited(s.link.arm());
      }
      notifyListeners();
    }));
    s._subs.add(s.link.batteryLevel.listen((b) {
      s.battery = b;
      notifyListeners();
    }));
    s._subs.add(s.link.instantMetrics.listen((m) {
      pendingInstant = PendingInstant(
        sensorId: s.id,
        sensorLabel: s.label,
        club: s.club,
        metrics: m,
      );
      notifyListeners();
    }));
    s._subs.add(s.link.swings.listen((capture) {
      final metrics = _processor.process(
        capture,
        s.club,
        deviceId: s.id,
        deviceLabel: s.label,
      );
      repository.add(metrics);
      latestSwing = metrics;
      if (pendingInstant?.sensorId == s.id) pendingInstant = null;
      notifyListeners();
    }));
  }

  void renameSensor(ConnectedSensor s, String label) {
    if (label.trim().isEmpty) return;
    s.label = label.trim();
    _saveSensors();
    notifyListeners();
  }

  void assignClub(ConnectedSensor s, ClubProfile club) {
    s.club = club;
    _saveSensors();
    notifyListeners();
  }

  void removeSensor(ConnectedSensor s) {
    s.dispose();
    sensors.remove(s);
    if (pendingInstant?.sensorId == s.id) pendingInstant = null;
    _saveSensors();
    notifyListeners();
  }

  /// Demo mode for simulated sensors: periodic randomized swings so stats
  /// stream in live with zero interaction. Reads the sensor's *current*
  /// club at each swing, so reassigning the club mid-stream is respected.
  void toggleAutoSwings(ConnectedSensor s, bool on) {
    final link = s.link;
    if (link is! MockSensorLink) return;
    if (on) {
      link.startAutoSwings(shaftLengthM: () => s.club.shaftLengthM);
    } else {
      link.stopAutoSwings();
    }
    notifyListeners();
  }

  /// Edits a club profile's constants and propagates to sensors using it.
  void updateClub(ClubProfile updated) {
    final i = clubs.indexWhere((c) => c.id == updated.id);
    if (i < 0) return;
    clubs[i] = updated;
    for (final s in sensors) {
      if (s.club.id == updated.id) s.club = updated;
    }
    unawaited(_db?.saveClubs(List.of(clubs)));
    notifyListeners();
  }

  void _saveSensors() {
    unawaited(_db?.saveSensors([for (final s in sensors) s.toRecord()]));
  }

  @override
  void dispose() {
    for (final s in sensors) {
      s.dispose();
    }
    super.dispose();
  }
}
