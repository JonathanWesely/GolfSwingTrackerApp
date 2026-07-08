# GolfTrackerApp

Flutter companion app for the open-source AR golf swing tracker
(Arduino Nicla Sense ME sensor + Snap Spectacles HUD). See
`GolfSwingTracker.md` in the Obsidian vault for the full project plan.

**Status: Phase 2 (pre-hardware).** The app runs entirely on a simulated
sensor (`MockSensorLink`) that generates physically self-consistent swings,
so every layer above BLE — processing math, storage, UI — is testable today.

## Quick start

```bash
# 1. Install Flutter (https://docs.flutter.dev/get-started/install/windows)
# 2. From this folder, generate the platform scaffolding (one time):
flutter create . --platforms=android,ios --org com.jonwes
# 3. Fetch dependencies and run the tests:
flutter pub get
flutter test
# 4. Run the app (Android emulator, iOS simulator, or a real phone):
flutter run
```

In the app: fully hands-free — sensors **auto-connect and auto-arm** when
added, and re-arm after every swing. Toggle **"Auto swings"** on a simulated
sensor to watch stats stream in live with zero clicks. (Manual
Calibrate/Arm/Simulate buttons remain as overrides.)

**Multi-sensor**: the + button adds more sensors (simulated or BLE). Each
gets a user-assigned name (player or club) and its own club profile; swings
are tagged by source and the history screen filters by device. Real devices
are told apart by BLE address even though they advertise the same name.
Phones support ~7–10 simultaneous BLE connections.

## Architecture

```
lib/
  main.dart                     <- HARDWARE SWAP POINT (mock vs BLE)
  src/
    app_state.dart              multi-sensor manager: N sensors -> processor -> shared archive
    models/                     ClubProfile, SwingCapture, SwingMetrics
    processing/
      quaternion.dart           dependency-free vector/quaternion math
      swing_processor.dart      capture -> metrics (speed, face angle, path)
    sensor/
      sensor_link.dart          abstract sensor interface
      mock_sensor_link.dart     synthetic swing generator (no hardware needed)
      ble_sensor_link.dart      real Nicla link (finish in Phase 1/2 integration)
      gatt_protocol.dart        BLE UUIDs + swing packet codec (shared contract)
    storage/swing_repository.dart  in-memory archive + JSON export
    ui/                         home, history, swing detail, club profiles
test/                           unit tests incl. ground-truth recovery checks
docs/BLE_PROTOCOL.md            firmware <-> app contract
```

## How the mock enables pre-hardware development

`MockSensorLink.generateSwing()` builds a parametric swing (grip arc +
face twist), then **differentiates** it into exactly the quaternion, gyro,
and linear-acceleration streams the sensor firmware emits (the packet
format is IMU-agnostic — ICM-20649 primary or BHY2 fallback), plus noise.
Because ground truth is known, `flutter test` proves the pipeline recovers:

- club speed within 3% (validated at ~0.15% in practice)
- face angle within 0.7 deg (validated at ~0.01 deg)
- impact position within 15 cm (validated at ~5 mm)

## When the hardware arrives

1. Flash Phase 1 firmware implementing `docs/BLE_PROTOCOL.md`.
2. In `main.dart`, swap `MockSensorLink()` -> `BleSensorLink()`.
3. Add BLE permissions (Android `AndroidManifest.xml`: `BLUETOOTH_SCAN`,
   `BLUETOOTH_CONNECT`; iOS `Info.plist`: `NSBluetoothAlwaysUsageDescription`)
   per the flutter_blue_plus docs.

## Gyro range note (resolved by hardware)

A ~95 mph driver swing peaks around **2130 dps** at the grip; 110 mph hits
~2465 dps — past the BHI260AP's ±2000 dps range (simulation showed a 110 mph
swing loses the last ~100 ms of the downswing to clipping, and curve
extrapolation across that gap is unreliable). The build therefore includes an
**ICM-20649 wide-range IMU (±4000 dps / ±30 g)** as the *primary motion
sensor for all metrics* (single clock, no cross-IMU sync error; ±30 g accel
headroom for path integration) — clean speed readings to ~175 mph. The BLE
packet gyro scale (×400) is sized for it. Firmware without the ICM-20649
falls back to the BHI260AP + pre-clip ramp extrapolation (fine below
~95 mph); the packet format is identical either way, so this app never
needs to know which IMU produced a capture.
