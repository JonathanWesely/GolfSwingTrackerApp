import 'package:flutter_test/flutter_test.dart';
import 'package:golf_tracker_app/src/sensor/gatt_protocol.dart';
import 'package:golf_tracker_app/src/sensor/mock_sensor_link.dart';

void main() {
  test('SwingPacketCodec round-trip preserves capture within quantization',
      () {
    final mock = MockSensorLink(seed: 7);
    final capture = mock.generateSwing(
        clubheadSpeedMph: 80, faceAngleDeg: 3.0, shaftLengthM: 1.143);

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
      expect((a.linAccel - b.linAccel).length, lessThan(2e-2));
      expect((a.orientation.w - b.orientation.w).abs(), lessThan(1e-3));
    }
  });

  test('decode returns null while chunks are missing', () {
    final mock = MockSensorLink(seed: 8);
    final capture = mock.generateSwing(
        clubheadSpeedMph: 60, faceAngleDeg: 0, shaftLengthM: 1.0);
    final chunks = SwingPacketCodec.encode(capture);

    final partial = List.of(chunks.map((c) => c as dynamic)).cast<dynamic>();
    partial[1] = null;
    expect(
        SwingPacketCodec.decode(partial.cast()), isNull);
  });
}
