# GolfTracker firmware (Phase 1)

Arduino firmware for the **Nicla Sense ME** that turns the assembled sensor into
a BLE device the companion app can talk to. It implements the contract in
[`../docs/BLE_PROTOCOL.md`](../docs/BLE_PROTOCOL.md); the app's Dart codec in
`../lib/src/sensor/gatt_protocol.dart` is the reference these packets match.

> **Status: first implementation, not yet hardware-tested.** It's structured to
> the full protocol and the wire format is byte-for-byte matched to the app, but
> several pieces are heuristics/stubs that must be tuned against a launch monitor
> or 240 fps video (plan Phase 2/5). See **What still needs work** below. Treat
> this as the starting point to flash, iterate, and validate — not a final build.

## Files

```
firmware/
  firmware.ino          main: sampling, fusion, swing detection, BLE service
  src/
    gatt_protocol.h      UUIDs, opcodes, packed wire structs + scales
                         (mirror of lib/src/sensor/gatt_protocol.dart)
    madgwick.h           6-axis Madgwick filter + quaternion helpers
```

## Dependencies

Install via the Arduino IDE (same setup as the bench-test guide):

1. **Boards Manager** → *Arduino Mbed OS Nicla Boards* (provides the Nicla core
   and `Nicla_System.h`).
2. **Library Manager**:
   - **ArduinoBLE**
   - **Arduino_BHY2**
   - **Adafruit ICM20X** (contains `Adafruit_ICM20649`; accept the Adafruit
     BusIO + Unified Sensor dependencies)

## Build & flash

1. Open `firmware/firmware.ino` in the Arduino IDE (the `src/` folder compiles
   automatically).
2. **Tools → Board →** Nicla Sense ME; **Tools → Port →** its COM port
   (double-tap reset if it doesn't appear).
3. Upload. On boot the device advertises as **`GolfTracker`**.

## Verify without the app

Use a generic BLE client (nRF Connect, LightBlue):

- Confirm the device advertises as `GolfTracker` and exposes the Swing Service
  `f3641400-…` plus the standard Battery Service `0x180F`.
- Subscribe to **Instant Metrics** (`…1404`) and **Swing Data** (`…1401`),
  then make a swinging motion — you should get a 12-byte instant packet followed
  by a burst of chunks (seq 0 header, then sample chunks).
- Negotiate an **MTU ≥ 185** first (the app does this automatically; some BLE
  clients need it set manually) so the 172-byte sample chunks fit.

## How it maps to the protocol

| Protocol element | Where |
|---|---|
| Swing/Battery services & characteristics | `setup()` in `firmware.ino` |
| Control opcodes (calibrate/arm/disarm) | `onControlWrite()` |
| Capture header (seq 0) + sample chunks | `sendCapture()` |
| Instant-metrics packet | `sendInstantMetrics()` |
| Auto-arm / auto re-arm / still-hold auto-calibrate | `loop()` state machine |
| ICM-20649 primary, ±4000 dps / ±30 g | `setup()` + `loop()` read |
| Quaternion + gravity-removed linear accel | `madgwick.h` + `loop()` |

Fixed-point scales, chunk sizes, and struct layouts live in `gatt_protocol.h`
with `static_assert`s guaranteeing the byte sizes match the Dart codec.

## What still needs work (search `TODO` in the source)

These are correct-enough to stream real captures, but need validation/tuning:

- **Auto-sleep (added, needs tuning)** — after `SLEEP_AFTER_US` (default 120 s)
  of stillness the firmware drops to a ~20 Hz motion-watch and wakes to full
  400 Hz when gyro motion exceeds `WAKE_THRESH_RADS`. This is a *software*
  light-sleep (low-rate I2C polling), **not** a true MCU deep sleep: the ICM's
  INT pin isn't wired in the current build, so there's no hardware wake. TODO:
  tune the thresholds; for maximum battery life, wire the ICM INT line (or use
  the BHI260 wake-on-motion sensor) so the MCU can truly sleep between swings.
- **Ship mode (added)** — `OP_SHIP_MODE` (control opcode `0x04`) and an optional
  auto-ship after `SHIP_AFTER_US` idle (default `0` = disabled) call
  `nicla::enterShipMode()` to isolate the battery for storage; wake via USB or
  reset. TODO: this opcode is a **firmware extension not yet in
  `BLE_PROTOCOL.md` or the app's `ControlOp`** — add it app-side to expose a
  "power off / store" button. Note: idle timers use `micros()`, which rolls over
  at ~71 min, so keep long-storage ship-off manual rather than timer-driven.
- **Charging (added)** — `setup()` now calls `nicla::enableCharging(100)` with a
  9-hour safety timer, so the device charges (~0.4C) whenever USB is connected.
- **Impact detection** — currently latches on the gyro-magnitude peak +
  deceleration. Should become an accelerometer-spike detector for accurate
  impact timing.
- **Gravity removal / linear-accel frame** — uses the Madgwick gravity estimate;
  the exact frame and sign want checking against the app's path integration.
- **Face-angle sign** — the swing-twist about +Z is computed, but the sign
  convention (positive = open, RH) must be confirmed against the app.
- **BHY2 fallback path** — the fallback source flag is set on ICM failure, but
  the code doesn't yet fill samples from the BHI260 Game Rotation Vector +
  Linear Acceleration. Also missing: per-swing quality cross-checks against the
  BHY2 shadow, and gyro-clip speed extrapolation.
- **Gyro-bias zeroing** — auto-calibration stores the address orientation but
  does not yet subtract a measured gyro bias over the still hold.
- **Sample-rate / ODR** — the loop paces at 400 Hz, but the ICM ODR isn't
  explicitly pinned to a matching rate; set it and verify no aliasing.
- **RAM** — the 800-sample ring is stored in wire format (~19 KB) to fit the
  ANNA-B112; watch headroom as the BHY2 fallback buffer is added.

## First on-hardware tasks

1. Flash, confirm it advertises and streams to a BLE client.
2. Connect the app: **+ → Scan for GolfTracker sensor → tap the device.**
3. Compare app speed/face/path numbers against a launch monitor or 240 fps
   slow-mo and tune the TODO items above.
