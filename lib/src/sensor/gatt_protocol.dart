import 'dart:typed_data';

import '../models/swing_capture.dart';
import '../processing/quaternion.dart';

/// BLE GATT contract shared by the firmware and this app.
/// Keep this file in sync with firmware/src/gatt_protocol.h.
///
/// Service layout:
///   Swing Service          f3641400-00b0-4240-ba50-05ca45bf8abc
///     Swing Data    (notify)  f3641401-...  chunked capture burst
///     Control       (write)   f3641402-...  commands (calibrate/arm)
///     Live Preview  (notify)  f3641403-...  decimated 25 Hz stream
///   Battery Service (standard 0x180F / level 0x2A19)
class GattIds {
  static const String swingService = 'f3641400-00b0-4240-ba50-05ca45bf8abc';
  static const String swingDataChar = 'f3641401-00b0-4240-ba50-05ca45bf8abc';
  static const String controlChar = 'f3641402-00b0-4240-ba50-05ca45bf8abc';
  static const String livePreviewChar = 'f3641403-00b0-4240-ba50-05ca45bf8abc';

  /// Instant metrics (notify): ~12-byte packet sent the moment impact is
  /// detected, ahead of the full capture burst — the HUD's <500 ms source.
  /// Layout: u32 t_us | i16 peakOmega (rad/s x400) | i16 faceAngle (deg x100)
  ///         | u8 sourceFlags | u8,u16 reserved
  static const String instantMetricsChar =
      'f3641404-00b0-4240-ba50-05ca45bf8abc';
  static const String batteryService = '0000180f-0000-1000-8000-00805f9b34fb';
  static const String batteryLevelChar =
      '00002a19-0000-1000-8000-00805f9b34fb';
}

/// Control command opcodes (single byte written to Control characteristic).
class ControlOp {
  static const int calibrateAddress = 0x01;
  static const int arm = 0x02;
  static const int disarm = 0x03;
}

/// Decoded instant-metrics packet — the ~12-byte notification the firmware
/// sends the moment impact is detected, seconds before the full capture
/// burst finishes transferring. This is what makes a <500 ms HUD possible.
class InstantMetrics {
  /// Impact time, microseconds since capture start.
  final int tUs;

  /// Peak gyro magnitude at impact, rad/s. Multiply by the club's
  /// sensor-to-clubface distance for clubhead speed (v = omega * r).
  final double peakOmegaRadS;

  /// Face angle at impact relative to address, degrees (positive = open).
  final double faceAngleDeg;

  /// Same flag bits as SwingCapture.sourceFlags.
  final int sourceFlags;

  const InstantMetrics({
    required this.tUs,
    required this.peakOmegaRadS,
    required this.faceAngleDeg,
    this.sourceFlags = 0,
  });

  double clubSpeedMps(double radiusM) => peakOmegaRadS * radiusM;
  double clubSpeedMph(double radiusM) => clubSpeedMps(radiusM) * 2.23694;
}

/// Codec for the Instant Metrics characteristic (12 bytes, little-endian):
///   u32 t_us | i16 peakOmega (rad/s x400) | i16 faceAngle (deg x100)
///   | u8 sourceFlags | u8 pad | u16 reserved
class InstantMetricsCodec {
  static const int packetLength = 12;
  static const double omegaScale = 400.0;
  static const double faceScale = 100.0;

  static Uint8List encode(InstantMetrics m) {
    final b = ByteData(packetLength);
    b.setUint32(0, m.tUs, Endian.little);
    b.setInt16(4, (m.peakOmegaRadS * omegaScale).round().clamp(-32768, 32767),
        Endian.little);
    b.setInt16(6, (m.faceAngleDeg * faceScale).round().clamp(-32768, 32767),
        Endian.little);
    b.setUint8(8, m.sourceFlags & 0xff);
    // byte 9 pad, bytes 10-11 reserved
    return b.buffer.asUint8List();
  }

  /// Returns null for malformed (too-short) packets.
  static InstantMetrics? decode(Uint8List data) {
    if (data.length < packetLength) return null;
    final b = ByteData.sublistView(data);
    return InstantMetrics(
      tUs: b.getUint32(0, Endian.little),
      peakOmegaRadS: b.getInt16(4, Endian.little) / omegaScale,
      faceAngleDeg: b.getInt16(6, Endian.little) / faceScale,
      sourceFlags: b.getUint8(8),
    );
  }
}

/// Binary sample layout (little-endian, 24 bytes):
///   u32  t_us          microseconds since capture start
///   i16  qw,qx,qy,qz   quaternion * 32767
///   i16  gx,gy,gz      gyro rad/s * 400         (±81.9 rad/s ≈ ±4693 dps —
///                      covers the ICM-20649's full ±4000 dps range;
///                      resolution 0.14 dps)
///   i16  ax,ay,az      linear accel m/s^2 * 100 (±327 m/s^2 ≈ ±33.4 g —
///                      covers the ICM-20649's full ±30 g range;
///                      resolution 0.01 m/s^2)
///
/// Chunk layout (fits a 185-byte MTU):
///   u16 seq | u16 totalChunks | payload (N whole samples, ≤7 per chunk)
/// Chunk 0 payload is instead the 20-byte header:
///   u32 sampleCount | u16 sampleRateHz | i16 qw,qx,qy,qz (address ref) | u32 reserved
class SwingPacketCodec {
  static const int sampleBytes = 24;
  static const int samplesPerChunk = 7;
  static const double quatScale = 32767.0;
  static const double gyroScale = 400.0;
  static const double accelScale = 100.0;

  /// Encodes a capture into BLE-sized chunks (used by tests and by the
  /// firmware simulator; the real encoder lives in firmware).
  static List<Uint8List> encode(SwingCapture c) {
    final dataChunks =
        (c.samples.length / samplesPerChunk).ceil() + 1; // +1 header
    final out = <Uint8List>[];

    // Header chunk (seq 0)
    final h = ByteData(4 + 20);
    h.setUint16(0, 0, Endian.little);
    h.setUint16(2, dataChunks, Endian.little);
    h.setUint32(4, c.samples.length, Endian.little);
    h.setUint16(8, c.sampleRateHz.round(), Endian.little);
    h.setInt16(10, (c.addressReference.w * quatScale).round(), Endian.little);
    h.setInt16(12, (c.addressReference.x * quatScale).round(), Endian.little);
    h.setInt16(14, (c.addressReference.y * quatScale).round(), Endian.little);
    h.setInt16(16, (c.addressReference.z * quatScale).round(), Endian.little);
    h.setUint8(18, c.sourceFlags & 0xff);
    // byte 19 pad, bytes 20-23 reserved (zero-initialized)
    out.add(h.buffer.asUint8List());

    for (var chunk = 0; chunk * samplesPerChunk < c.samples.length; chunk++) {
      final start = chunk * samplesPerChunk;
      final count =
          (c.samples.length - start).clamp(0, samplesPerChunk).toInt();
      final b = ByteData(4 + count * sampleBytes);
      b.setUint16(0, chunk + 1, Endian.little);
      b.setUint16(2, dataChunks, Endian.little);
      for (var i = 0; i < count; i++) {
        final s = c.samples[start + i];
        final o = 4 + i * sampleBytes;
        b.setUint32(o, (s.t * 1e6).round(), Endian.little);
        b.setInt16(o + 4, (s.orientation.w * quatScale).round(), Endian.little);
        b.setInt16(o + 6, (s.orientation.x * quatScale).round(), Endian.little);
        b.setInt16(o + 8, (s.orientation.y * quatScale).round(), Endian.little);
        b.setInt16(o + 10, (s.orientation.z * quatScale).round(), Endian.little);
        b.setInt16(o + 12, _sat(s.gyroRadS.x * gyroScale), Endian.little);
        b.setInt16(o + 14, _sat(s.gyroRadS.y * gyroScale), Endian.little);
        b.setInt16(o + 16, _sat(s.gyroRadS.z * gyroScale), Endian.little);
        b.setInt16(o + 18, _sat(s.linAccel.x * accelScale), Endian.little);
        b.setInt16(o + 20, _sat(s.linAccel.y * accelScale), Endian.little);
        b.setInt16(o + 22, _sat(s.linAccel.z * accelScale), Endian.little);
      }
      out.add(b.buffer.asUint8List());
    }
    return out;
  }

  static int _sat(double v) => v.round().clamp(-32768, 32767);

  /// Reassembles chunks (any order) into a capture. Returns null until all
  /// chunks have arrived.
  static SwingCapture? decode(List<Uint8List?> received) {
    if (received.isEmpty || received.any((c) => c == null)) return null;
    final header = ByteData.sublistView(received[0]!);
    final sampleCount = header.getUint32(4, Endian.little);
    final rate = header.getUint16(8, Endian.little).toDouble();
    final addressRef = Quaternion(
      header.getInt16(10, Endian.little) / quatScale,
      header.getInt16(12, Endian.little) / quatScale,
      header.getInt16(14, Endian.little) / quatScale,
      header.getInt16(16, Endian.little) / quatScale,
    ).normalized();

    final samples = <SensorSample>[];
    for (var chunk = 1; chunk < received.length; chunk++) {
      final b = ByteData.sublistView(received[chunk]!);
      final count = (received[chunk]!.length - 4) ~/ sampleBytes;
      for (var i = 0; i < count; i++) {
        final o = 4 + i * sampleBytes;
        samples.add(SensorSample(
          t: b.getUint32(o, Endian.little) / 1e6,
          orientation: Quaternion(
            b.getInt16(o + 4, Endian.little) / quatScale,
            b.getInt16(o + 6, Endian.little) / quatScale,
            b.getInt16(o + 8, Endian.little) / quatScale,
            b.getInt16(o + 10, Endian.little) / quatScale,
          ).normalized(),
          gyroRadS: Vector3(
            b.getInt16(o + 12, Endian.little) / gyroScale,
            b.getInt16(o + 14, Endian.little) / gyroScale,
            b.getInt16(o + 16, Endian.little) / gyroScale,
          ),
          linAccel: Vector3(
            b.getInt16(o + 18, Endian.little) / accelScale,
            b.getInt16(o + 20, Endian.little) / accelScale,
            b.getInt16(o + 22, Endian.little) / accelScale,
          ),
        ));
      }
    }
    if (samples.length != sampleCount) return null;
    return SwingCapture(
      timestamp: DateTime.now(),
      sampleRateHz: rate,
      addressReference: addressRef,
      samples: samples,
      sourceFlags: header.getUint8(18),
    );
  }
}
