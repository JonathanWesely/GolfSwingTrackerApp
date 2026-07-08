import 'dart:async';

import 'package:flutter/foundation.dart';

import 'models/club_profile.dart';
import 'models/swing_metrics.dart';
import 'processing/swing_processor.dart';
import 'sensor/ble_sensor_link.dart';
import 'sensor/mock_sensor_link.dart';
import 'sensor/sensor_link.dart';
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

  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    link.dispose();
  }
}

/// App-wide state: a list of sensors feeding one shared swing archive.
/// Swings are tagged with the source sensor's id + label, so per-device
/// views are just filters over the repository.
class AppState extends ChangeNotifier {
  final SwingRepository repository = SwingRepository();
  final SwingProcessor _processor = const SwingProcessor();
  final List<ClubProfile> clubs = List.of(ClubProfile.defaults);
  final List<ConnectedSensor> sensors = [];

  SwingMetrics? latestSwing;
  int _mockCounter = 0;

  /// Hands-free mode (default ON): sensors auto-connect when added and
  /// auto-(re)arm whenever they reach `connected` — including right after
  /// each capture — so swings stream in with zero button presses.
  bool handsFree = true;

  AppState({bool startWithMock = true}) {
    if (startWithMock) addMockSensor();
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
    if (handsFree) unawaited(sensor.link.connect());
    notifyListeners();
    return sensor;
  }

  /// Adds a real sensor by BLE identity. With multiple devices advertising
  /// the same name, the remoteId (BLE address) is what tells them apart.
  ConnectedSensor addBleSensor({String? remoteId, String? label}) {
    final sensor = ConnectedSensor(
      id: remoteId ?? 'ble-pending-${sensors.length}',
      link: BleSensorLink(targetRemoteId: remoteId),
      label: label ?? 'GolfTracker ${sensors.length + 1}',
      club: clubs.first,
    );
    _wire(sensor);
    sensors.add(sensor);
    if (handsFree) unawaited(sensor.link.connect());
    notifyListeners();
    return sensor;
  }

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
    s._subs.add(s.link.swings.listen((capture) {
      final metrics = _processor.process(
        capture,
        s.club,
        deviceId: s.id,
        deviceLabel: s.label,
      );
      repository.add(metrics);
      latestSwing = metrics;
      notifyListeners();
    }));
  }

  void renameSensor(ConnectedSensor s, String label) {
    if (label.trim().isEmpty) return;
    s.label = label.trim();
    notifyListeners();
  }

  void assignClub(ConnectedSensor s, ClubProfile club) {
    s.club = club;
    notifyListeners();
  }

  void removeSensor(ConnectedSensor s) {
    s.dispose();
    sensors.remove(s);
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
    notifyListeners();
  }

  @override
  void dispose() {
    for (final s in sensors) {
      s.dispose();
    }
    super.dispose();
  }
}
