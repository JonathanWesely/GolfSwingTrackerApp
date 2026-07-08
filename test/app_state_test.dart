import 'package:flutter_test/flutter_test.dart';
import 'package:golf_tracker_app/src/app_state.dart';
import 'package:golf_tracker_app/src/models/swing_metrics.dart';
import 'package:golf_tracker_app/src/processing/quaternion.dart';
import 'package:golf_tracker_app/src/sensor/sensor_link.dart';
import 'package:golf_tracker_app/src/storage/swing_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'fake_ble_transport.dart';

Future<void> pumpEventQueue2({int ms = 30}) =>
    Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  sqfliteFfiInit();
  final factory = databaseFactoryFfi;

  Future<SwingDatabase> openDb() =>
      SwingDatabase.open(factory: factory, path: inMemoryDatabasePath);

  test('first launch: restore() falls back to one simulated sensor', () async {
    final db = await openDb();
    final state = await AppState.restore(
        db: db, bleTransportFactory: FakeTransport.new);
    expect(state.sensors, hasLength(1));
    expect(state.sensors.single.isMock, isTrue);
    await pumpEventQueue2(ms: 700); // let hands-free auto-connect settle
    state.dispose();
    await db.close();
  });

  test('sensor registry, labels, and club assignments survive a restart',
      () async {
    final db = await openDb();
    final state = await AppState.restore(
        db: db, bleTransportFactory: FakeTransport.new);

    // User customizes: renames the default sensor, adds a BLE sensor with
    // a club assignment, edits a club profile.
    state.renameSensor(state.sensors.first, 'Jonathan');
    final ble =
        state.addBleSensor(remoteId: 'AA:BB:CC:11:22:33', label: 'Driver');
    final sevenIron = state.clubs.firstWhere((c) => c.id == '7i');
    state.assignClub(ble, sevenIron);
    state.updateClub(state.clubs.first.copyWith(shaftLengthM: 1.16));
    await pumpEventQueue2(ms: 700);
    state.dispose();

    // "Restart" the app on the same database.
    final state2 = await AppState.restore(
        db: db, bleTransportFactory: FakeTransport.new);
    expect(state2.sensors, hasLength(2));
    expect(state2.sensors[0].label, 'Jonathan');
    expect(state2.sensors[0].isMock, isTrue);
    expect(state2.sensors[1].id, 'AA:BB:CC:11:22:33');
    expect(state2.sensors[1].isMock, isFalse);
    expect(state2.sensors[1].club.id, '7i');
    expect(state2.clubs.first.shaftLengthM, closeTo(1.16, 1e-12));
    await pumpEventQueue2(ms: 700);
    state2.dispose();
    await db.close();
  });

  test('swing archive survives a restart', () async {
    final db = await openDb();
    final state = await AppState.restore(
        db: db, bleTransportFactory: FakeTransport.new);
    state.repository.add(SwingMetrics(
      timestamp: DateTime.utc(2026, 7, 8),
      clubId: 'driver',
      clubSpeedMps: 40,
      faceAngleDeg: 1.0,
      pathM: const [Vector3.zero],
      impactIndex: 0,
      deviceId: 'mock-1',
      deviceLabel: 'Sensor 1',
    ));
    await pumpEventQueue2(ms: 700);
    state.dispose();

    final state2 = await AppState.restore(
        db: db, bleTransportFactory: FakeTransport.new);
    expect(state2.repository.count, 1);
    expect(state2.repository.all.single.deviceLabel, 'Sensor 1');
    await pumpEventQueue2(ms: 700);
    state2.dispose();
    await db.close();
  });

  test('removing a sensor persists', () async {
    final db = await openDb();
    final state = await AppState.restore(
        db: db, bleTransportFactory: FakeTransport.new);
    state.addMockSensor();
    expect(state.sensors, hasLength(2));
    state.removeSensor(state.sensors.first);
    await pumpEventQueue2(ms: 700);
    state.dispose();

    final state2 = await AppState.restore(
        db: db, bleTransportFactory: FakeTransport.new);
    expect(state2.sensors, hasLength(1));
    await pumpEventQueue2(ms: 700);
    state2.dispose();
    await db.close();
  });

  test('mock swing flows through processor into repository and clears '
      'pendingInstant', () async {
    final state = AppState(
        startWithMock: true, bleTransportFactory: FakeTransport.new);
    final sensor = state.sensors.single;
    await pumpEventQueue2(ms: 700); // auto-connect (600 ms) + auto-arm
    expect(sensor.status, SensorStatus.armed);

    final mock = sensor.link as dynamic;
    await mock.simulateSwing(
        clubheadSpeedMph: 85.0,
        faceAngleDeg: 2.0,
        shaftLengthM: sensor.club.shaftLengthM);
    await pumpEventQueue2();

    expect(state.repository.count, 1);
    expect(state.latestSwing, isNotNull);
    expect(state.latestSwing!.clubSpeedMph, closeTo(85, 85 * 0.03));
    expect(state.latestSwing!.deviceLabel, 'Sensor 1');
    // Instant metrics preceded the capture, then were cleared by it.
    expect(state.pendingInstant, isNull);
    state.dispose();
  });
}
