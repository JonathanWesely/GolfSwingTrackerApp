# GolfTrackerApp

Flutter companion app for the open-source AR golf swing tracker
(Arduino Nicla Sense ME sensor + Snap Spectacles HUD). See
`GolfSwingTracker.md` in the Obsidian vault for the full project plan.

**Status: Phase 2 complete (pre-hardware).** Everything the app can do
without real hardware is done and unit-tested: the full processing
pipeline, the complete BLE protocol implementation (chunk reassembly,
instant metrics, auto-reconnect — tested against a fake transport),
persistent storage (SQLite), multi-sensor management with a scan screen,
and the hands-free UI. When the sensor arrives, no app code changes are
needed — flash the Phase 1 firmware and add the sensor from the scan
screen.

## Quick start

```bash
# 1. Install Flutter (https://docs.flutter.dev/get-started/install/windows)
# 2. From this folder, generate the platform scaffolding (one time):
flutter create . --platforms=android,ios --org com.jonwes --project-name golf_tracker_app
dart run tool/setup_platforms.dart   # adds BLE permissions, removes stock template test
# 3. Fetch dependencies and run the tests:
flutter pub get
flutter test
# 4. Run the app (Android emulator, iOS simulator, or a real phone):
flutter run
```

`tool/setup_platforms.dart` is idempotent: it adds the flutter_blue_plus
Bluetooth permissions to `AndroidManifest.xml` (BLUETOOTH_SCAN/CONNECT for
Android 12+, the legacy set for ≤ 11) and
`NSBluetoothAlwaysUsageDescription` to the iOS `Info.plist`, and deletes
the counter-app `test/widget_test.dart` that `flutter create` drops next
to the real suite.

In the app: fully hands-free — sensors **auto-connect and auto-arm** when
added, and re-arm after every swing. Toggle **"Auto swings"** on a simulated
sensor to watch stats stream in live with zero clicks. (Manual
Calibrate/Arm/Simulate buttons remain as overrides.) The ⚡ instant-metrics
card flashes the moment a swing's impact packet arrives — the same numbers
the AR HUD will show <500 ms after contact — then resolves into the full
capture once the burst transfer completes.

**Multi-sensor**: the + button adds more sensors — simulated, or real ones
via **"Scan for GolfTracker sensor"**, which lists every advertising device
by BLE address and signal strength. Each sensor gets a user-assigned name
(player or club) and its own club profile; swings are tagged by source and
the history screen filters by device. Phones support ~7–10 simultaneous
BLE connections.

**Persistence**: swings, club profiles, and the sensor registry live in
SQLite (`golf_tracker.db`) and survive restarts — close the app mid-range-
session and everything is still there, including which sensors you'd
added and how you'd named them. JSON export (for Phase 3 Lens replay)
is unchanged.

## Architecture

```
lib/
  main.dart                     opens the database, restores AppState
  src/
    app_state.dart              multi-sensor manager: N sensors -> processor -> shared archive
    models/                     ClubProfile, SwingCapture, SwingMetrics (incl. quality flags)
    processing/
      quaternion.dart           dependency-free vector/quaternion math
      swing_processor.dart      capture -> metrics (speed, face angle, path)
    sensor/
      sensor_link.dart          abstract sensor interface (swings + instant metrics)
      mock_sensor_link.dart     synthetic swing generator (no hardware needed)
      ble_transport.dart        thin BLE abstraction (scan/connect/subscribe/write)
      flutter_blue_plus_transport.dart  the ONLY file that touches flutter_blue_plus
      ble_sensor_link.dart      full BLE_PROTOCOL.md implementation over BleTransport:
                                MTU negotiation, chunk reassembly, instant metrics,
                                control ops, auto-reconnect with backoff
      gatt_protocol.dart        BLE UUIDs + swing/instant-metrics codecs (shared contract)
    storage/
      swing_database.dart       SQLite persistence (swings, clubs, sensor registry)
      swing_repository.dart     in-memory archive w/ write-through + JSON export
    ui/                         home, scan, history, swing detail, club profiles
test/                           117-assertion suite: ground-truth recovery, codec
                                round-trips, BLE link vs fake firmware, persistence
tool/setup_platforms.dart       one-time platform patcher (permissions etc.)
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

The BLE layer gets the same treatment: `test/fake_ble_transport.dart`
implements the firmware side of `docs/BLE_PROTOCOL.md` in memory, so the
tests deliver real encoded capture bursts (in order, out of order, with
retransmits and stalls), drop the link mid-session, and assert the app
reassembles, recovers, and reconnects. The only code that can't run until
hardware arrives is the ~150-line flutter_blue_plus adapter.

## When the hardware arrives

1. Flash Phase 1 firmware implementing `docs/BLE_PROTOCOL.md`.
2. In the app: **+ → Scan for GolfTracker sensor → tap the device.**
   That's it — no code changes. The sensor is remembered (by BLE address)
   across app restarts and auto-reconnects when it comes in range.
3. First on-range task: compare app numbers against a launch monitor or
   240 fps slow-mo (Phase 2 validation step in the plan).

Swings captured via the BHY2 fallback path (glue joint failure) or with
gyro clipping show a ⚠ badge in the latest-swing card and history list —
the plan's early warning to re-glue the ICM's VIN joint.

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
