import 'package:flutter_test/flutter_test.dart';
import 'package:golf_tracker_app/src/sensor/gatt_protocol.dart';
import 'package:golf_tracker_app/src/sensor/mock_sensor_link.dart';

void main() {
  test('SwingPacketCodec round-trip preserves capture within quantization',
      () {
    final mock = MockSensorLink(seed: 7);
    final capture = mock.generateSwing(
        clubheadSpeedMph: 80, faceAngleDeg: 3.0, radiusM: 1.143);

    final chunks = SwingPacketCodec.encode(capture);

    // Every chunk must fit a 185-byte BLE 4.2+ MTU payload.
    for (final c in chunks) {
      expect(c.length, lessThanOrEqualTo(185));
    }

    final decoded = SwingPacketCodec.decode(chunks);
    expect(decoded, isNotNull);
    expect(decoded!.samples.length, capture.samples.length);
    expect(decoded.sampleRateHz, capture.sampleRateHz);

    // Spot-check quantization error bounds.
    for (var i = 0; i < capture.samples.length; i += 97) {
      final a = capture.samples[i];
      final b = decoded.samples[i];
      expect((a.t - b.t).abs(), lessThan(2e-6));
      expect((a.gyroRadS - b.gyroRadS).length, lessThan(3e-3));
      // Accel fidelity only applies inside the codec's ±327 m/s² range.
      // (The ICM-20649 itself clips at ±30 g ≈ 294 m/s²; the mock's rigid-
      // arm model overshoots that near impact — see the saturation test.)
      if (a.linAccel.length < 300) {
        expect((a.linAccel - b.linAccel).length, lessThan(2e-2));
      }
      expect((a.orientation.w - b.orientation.w).abs(), lessThan(1e-3));
    }
  });

  test('out-of-range accel saturates cleanly instead of wrapping around', () {
    final mock = MockSensorLink(seed: 9);
    final capture = mock.generateSwing(
        clubheadSpeedMph: 110, faceAngleDeg: 0, radiusM: 1.143);
    final decoded = SwingPacketCodec.decode(SwingPacketCodec.encode(capture))!;

    // The mock's rigid-arm swing really does exceed the codec range…
    var maxIn = 0.0;
    for (final s in capture.samples) {
      if (s.linAccel.length > maxIn) maxIn = s.linAccel.length;
    }
    expect(maxIn, greaterThan(400));

    // …and every decoded axis clamps (same sign, magnitude ≤ ceiling) —
    // an i16 wraparound would flip signs and corrupt path integration.
    const ceiling = 32767 / SwingPacketCodec.accelScale; // ≈ 327.67 m/s²
    for (var i = 0; i < capture.samples.length; i++) {
      final a = capture.samples[i].linAccel;
      final b = decoded.samples[i].linAccel;
      for (final (va, vb) in [(a.x, b.x), (a.y, b.y), (a.z, b.z)]) {
        expect(vb.abs(), lessThanOrEqualTo(ceiling + 1e-9));
        if (va.abs() > 1.0) {
          expect(va.sign, vb.sign,
              reason: 'axis sign flipped at sample $i — wraparound?');
        }
      }
    }
  });

  test('decode returns null while chunks are missing', () {
    final mock = MockSensorLink(seed: 8);
    final capture = mock.generateSwing(
        clubheadSpeedMph: 60, faceAngleDeg: 0, radiusM: 1.0);
    final chunks = SwingPacketCodec.encode(capture);

    final partial = List.of(chunks.map((c) => c as dynamic)).cast<dynamic>();
    partial[1] = null;
    expect(
        SwingPacketCodec.decode(partial.cast()), isNull);
  });
}
