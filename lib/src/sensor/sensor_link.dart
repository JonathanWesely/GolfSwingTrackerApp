import '../models/swing_capture.dart';

enum SensorStatus { disconnected, connecting, connected, calibrating, armed }

/// Abstraction over the physical sensor. The app is written entirely
/// against this interface:
///  - [MockSensorLink] — synthetic swings, works today with no hardware.
///  - [BleSensorLink]  — real Nicla Sense ME over BLE (Phase 1 firmware).
///
/// Swapping implementations is a one-line change in main.dart.
abstract class SensorLink {
  SensorStatus get status;

  Stream<SensorStatus> get statusStream;

  /// Emits one complete capture per detected swing (post-impact burst).
  Stream<SwingCapture> get swings;

  /// Battery level 0.0–1.0, if the sensor reports it.
  Stream<double> get batteryLevel;

  Future<void> connect();

  Future<void> disconnect();

  /// 1-second static address hold: zeroes the face-angle reference.
  Future<void> calibrateAddress();

  /// Arms swing detection (sensor watches for the gyro threshold trigger).
  Future<void> arm();

  void dispose();
}
