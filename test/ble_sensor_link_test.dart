import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:golf_tracker_app/src/models/swing_capture.dart';
import 'package:golf_tracker_app/src/sensor/ble_sensor_link.dart';
import 'package:golf_tracker_app/src/sensor/ble_transport.dart';
import 'package:golf_tracker_app/src/sensor/gatt_protocol.dart';
import 'package:golf_tracker_app/src/sensor/mock_sensor_link.dart';
import 'package:golf_tracker_app/src/sensor/sensor_link.dart';

import 'fake_ble_transport.dart';

SwingCapture testCapture({int seed = 11}) =>
    MockSensorLink(seed: seed).generateSwing(
        clubheadSpeedMph: 85, faceAngleDeg: 2.5, radiusM: 1.143);

BleSensorLink makeLink(FakeTransport t, {String? targetRemoteId}) =>
    BleSensorLink(
      targetRemoteId: targetRemoteId ?? 'AA:BB:CC:DD:EE:FF',
      transport: t,
      calibrateSettle: const Duration(milliseconds: 1),
      reconnectDelays: const [Duration(milliseconds: 5)],
      captureStallTimeout: const Duration(milliseconds: 200),
    );

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 30));

void main() {
  group('connect', () {
    test('subscribes to swing data, instant metrics, and battery; '
        'negotiates MTU >= 185', () async {
      final t = FakeTransport();
      final link = makeLink(t);
      await link.connect();

      expect(link.status, SensorStatus.connected);
      expect(t.current.subscribed,
          containsAll([GattIds.swingDataChar, GattIds.instantMetricsChar,
            GattIds.batteryLevelChar]));
      expect(t.current.requestedMtu, greaterThanOrEqualTo(185));
      expect(link.negotiatedMtu, 247);
      link.dispose();
    });

    test('finds device by scan when no targetRemoteId is set', () async {
      final t = FakeTransport(advertised: const [
        BleScanHit(remoteId: '11:22', name: 'SomethingElse', rssi: -40),
        BleScanHit(
            remoteId: '33:44', name: BleSensorLink.advertisedName, rssi: -50),
      ]);
      final link = BleSensorLink(
          transport: t, reconnectDelays: const [Duration(milliseconds: 5)]);
      await link.connect();
      expect(link.connectedRemoteId, '33:44');
      link.dispose();
    });

    test('reads initial battery level', () async {
      final t = FakeTransport();
      final link = makeLink(t);
      final levels = <double>[];
      link.batteryLevel.listen(levels.add);
      await link.connect();
      await settle();
      expect(levels, [0.87]);
      link.dispose();
    });

    test('scan timeout with no device surfaces an error and resets status',
        () async {
      final t = FakeTransport(advertised: const []); // nothing advertising
      final link = BleSensorLink(
          transport: t, reconnectDelays: const [Duration(milliseconds: 5)]);
      await expectLater(link.connect(), throwsA(isA<TimeoutException>()));
      expect(link.status, SensorStatus.disconnected);
      link.dispose();
    });
  });

  group('swing capture reassembly', () {
    test('in-order chunks produce one capture', () async {
      final t = FakeTransport();
      final link = makeLink(t);
      final received = <SwingCapture>[];
      link.swings.listen(received.add);
      await link.connect();

      final capture = testCapture();
      for (final c in SwingPacketCodec.encode(capture)) {
        t.current.swingData.add(c);
      }
      await settle();

      expect(received, hasLength(1));
      expect(received.single.samples.length, capture.samples.length);
      // After a burst the link settles at `connected` (firmware re-arms).
      expect(link.status, SensorStatus.connected);
      link.dispose();
    });

    test('out-of-order + duplicated chunks still decode exactly once',
        () async {
      final t = FakeTransport();
      final link = makeLink(t);
      final received = <SwingCapture>[];
      link.swings.listen(received.add);
      await link.connect();

      final chunks = SwingPacketCodec.encode(testCapture());
      final shuffled = List.of(chunks.reversed);
      for (final c in shuffled) {
        t.current.swingData.add(c);
        t.current.swingData.add(c); // retransmit every chunk
      }
      await settle();

      expect(received, hasLength(1));
      link.dispose();
    });

    test('a stalled partial capture is dropped, next capture decodes',
        () async {
      final t = FakeTransport();
      final link = makeLink(t);
      final received = <SwingCapture>[];
      link.swings.listen(received.add);
      await link.connect();

      // Deliver an incomplete burst (drop one chunk), then stall.
      final chunks = SwingPacketCodec.encode(testCapture(seed: 12));
      for (final c in chunks.take(chunks.length - 1)) {
        t.current.swingData.add(c);
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(received, isEmpty);

      // A full burst afterwards decodes cleanly.
      for (final c in SwingPacketCodec.encode(testCapture(seed: 13))) {
        t.current.swingData.add(c);
      }
      await settle();
      expect(received, hasLength(1));
      link.dispose();
    });
  });

  group('instant metrics', () {
    test('decoded and emitted the moment the packet arrives', () async {
      final t = FakeTransport();
      final link = makeLink(t);
      final received = <InstantMetrics>[];
      link.instantMetrics.listen(received.add);
      await link.connect();

      t.current.instant.add(InstantMetricsCodec.encode(const InstantMetrics(
        tUs: 1450000,
        peakOmegaRadS: 31.5,
        faceAngleDeg: -2.25,
        sourceFlags: 0x04,
      )));
      await settle();

      expect(received, hasLength(1));
      expect(received.single.tUs, 1450000);
      expect(received.single.peakOmegaRadS, closeTo(31.5, 0.01));
      expect(received.single.faceAngleDeg, closeTo(-2.25, 0.01));
      expect(received.single.sourceFlags, 0x04);
      // v = omega * r
      expect(received.single.clubSpeedMph(1.143),
          closeTo(31.5 * 1.143 * 2.23694, 0.1));
      link.dispose();
    });

    test('malformed (short) packets are ignored', () async {
      final t = FakeTransport();
      final link = makeLink(t);
      final received = <InstantMetrics>[];
      link.instantMetrics.listen(received.add);
      await link.connect();

      t.current.instant.add(Uint8List.fromList([1, 2, 3]));
      await settle();
      expect(received, isEmpty);
      link.dispose();
    });
  });

  group('control ops', () {
    test('arm writes ARM opcode and sets status', () async {
      final t = FakeTransport();
      final link = makeLink(t);
      await link.connect();
      await link.arm();
      expect(t.current.controlWrites, [
        [ControlOp.arm]
      ]);
      expect(link.status, SensorStatus.armed);
      link.dispose();
    });

    test('calibrateAddress writes opcode and settles back to connected',
        () async {
      final t = FakeTransport();
      final link = makeLink(t);
      await link.connect();
      final statuses = <SensorStatus>[];
      link.statusStream.listen(statuses.add);
      await link.calibrateAddress();
      await settle(); // broadcast-stream delivery is async
      expect(t.current.controlWrites, [
        [ControlOp.calibrateAddress]
      ]);
      expect(statuses,
          [SensorStatus.calibrating, SensorStatus.connected]);
      link.dispose();
    });

    test('battery notifications map 0-100 to 0.0-1.0', () async {
      final t = FakeTransport();
      final link = makeLink(t);
      final levels = <double>[];
      link.batteryLevel.listen(levels.add);
      await link.connect();
      t.current.battery.add(Uint8List.fromList([42]));
      await settle();
      expect(levels.last, closeTo(0.42, 1e-9));
      link.dispose();
    });
  });

  group('reconnect', () {
    test('unexpected link drop reconnects automatically and keeps working',
        () async {
      final t = FakeTransport();
      final link = makeLink(t);
      final received = <SwingCapture>[];
      link.swings.listen(received.add);
      await link.connect();
      expect(t.connectCalls, 1);

      t.current.dropLink();
      await settle();

      expect(t.connectCalls, 2);
      expect(link.status, SensorStatus.connected);
      expect(t.sessions.first.closed, isTrue);

      // The new session delivers captures like nothing happened.
      for (final c in SwingPacketCodec.encode(testCapture(seed: 21))) {
        t.current.swingData.add(c);
      }
      await settle();
      expect(received, hasLength(1));
      link.dispose();
    });

    test('keeps retrying with backoff while connects fail', () async {
      final t = FakeTransport();
      final link = makeLink(t);
      await link.connect();

      t.failNextConnect = true;
      t.current.dropLink();
      await Future<void>.delayed(const Duration(milliseconds: 60));

      // First retry failed, a later one succeeded.
      expect(t.connectCalls, greaterThanOrEqualTo(3));
      expect(link.status, SensorStatus.connected);
      link.dispose();
    });

    test('user-initiated disconnect does NOT reconnect', () async {
      final t = FakeTransport();
      final link = makeLink(t);
      await link.connect();
      await link.disconnect();
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(t.connectCalls, 1);
      expect(link.status, SensorStatus.disconnected);
      expect(t.current.closed, isTrue);
      link.dispose();
    });

    test('dispose during connected life does not reconnect', () async {
      final t = FakeTransport();
      final link = makeLink(t);
      await link.connect();
      final session = t.current;
      link.dispose();
      session.dropLink();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(t.connectCalls, 1);
    });
  });

  test('InstantMetricsCodec round-trips within quantization', () {
    const m = InstantMetrics(
        tUs: 123456, peakOmegaRadS: 45.67, faceAngleDeg: 3.21, sourceFlags: 5);
    final decoded = InstantMetricsCodec.decode(InstantMetricsCodec.encode(m))!;
    expect(decoded.tUs, m.tUs);
    expect(decoded.peakOmegaRadS, closeTo(m.peakOmegaRadS, 1 / 400));
    expect(decoded.faceAngleDeg, closeTo(m.faceAngleDeg, 1 / 100));
    expect(decoded.sourceFlags, m.sourceFlags);
    expect(InstantMetricsCodec.encode(m).length,
        InstantMetricsCodec.packetLength);
  });
}
