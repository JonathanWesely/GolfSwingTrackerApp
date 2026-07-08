# BLE Protocol — GolfTracker sensor <-> app contract

Implemented by: Phase 1 firmware (Nicla Sense ME) and `lib/src/sensor/gatt_protocol.dart`.
Keep both sides in sync with this document.

## Advertising

- Device name: `GolfTracker`
- Advertises the Swing Service UUID.

## Multi-device identity

Multiple sensors advertise the same name; clients distinguish them by BLE
address (`remoteId`). User-facing labels (player/club names) and per-sensor
club assignments live app-side — no firmware naming support required.
Firmware needs no changes for multi-device operation: each connection is
independent, and captures are attributed by which connection they arrived on.

## GATT layout

| Service / Characteristic | UUID | Props | Purpose |
|---|---|---|---|
| **Swing Service** | `f3641400-00b0-4240-ba50-05ca45bf8abc` | — | — |
| Swing Data | `f3641401-…` | notify | chunked post-impact capture burst |
| Control | `f3641402-…` | write | commands (below) |
| Live Preview | `f3641403-…` | notify | decimated ~25 Hz orientation stream (optional, for setup UX) |
| Instant Metrics | `f3641404-…` | notify | ~12 B sent the moment impact is detected: `u32 t_us \| i16 peakOmega (rad/s × 400) \| i16 faceAngle (deg × 100) \| u8 sourceFlags \| u8,u16 reserved`. Drives the HUD's <500 ms display while the full burst (2–4 s) follows |
| **Battery Service** | `0x180F` (standard) | — | — |
| Battery Level | `0x2A19` | read/notify | 0–100 (%) |

## Control opcodes (1 byte)

| Op | Value | Firmware action |
|---|---|---|
| CALIBRATE_ADDRESS | `0x01` | 1 s static hold: store orientation as address reference, zero gyro bias |
| ARM | `0x02` | watch for swing trigger (gyro magnitude > ~3 rad/s sustained) |
| DISARM | `0x03` | stop watching (disables auto re-arm until ARM) |

**Hands-free defaults**: firmware boots armed, **auto re-arms after every
capture burst**, and auto-calibrates the address reference whenever it
detects a still hold (gyro quiet + orientation stable ≥1 s) — the natural
pre-swing address. The ops above are manual overrides, not required flow.

## Swing capture burst

Sent over Swing Data after impact detection. Negotiate MTU ≥ 185 first.

**Chunk framing** (all little-endian): `u16 seq | u16 totalChunks | payload`

- Chunk `seq=0` payload (20 bytes): `u32 sampleCount | u16 sampleRateHz | i16 qw,qx,qy,qz (address ref × 32767) | u8 sourceFlags | u8 pad | u32 reserved`
  - `sourceFlags` bit 0: capture source (0 = ICM-20649 primary, 1 = BHY2 fallback);
    bit 1: ICM present but failed quality checks; bit 2: gyro saturation detected
    (speed extrapolated); bits 3–7 reserved.
- Chunks `seq=1..N`: up to **7 samples** of 24 bytes each:

| Field | Type | Scale |
|---|---|---|
| t_us | u32 | microseconds since capture start |
| qw qx qy qz | i16 ×4 | quaternion × 32767 |
| gx gy gz | i16 ×3 | gyro rad/s × 400 (saturates ±81.9 rad/s ≈ 4693 dps; covers the ICM-20649's ±4000 dps, resolution 0.14 dps) |
| ax ay az | i16 ×3 | linear accel m/s² × 200 (saturates ±163 m/s² ≈ 16.6 g) |

Capture window: ~1.5 s pre-impact + 0.5 s post at 400 Hz ≈ 800 samples
≈ 115 data chunks ≈ 21 kB — a 2–4 s transfer at realistic BLE throughput.

The app reassembles chunks in any order and accepts retransmits
(`SwingPacketCodec.decode` returns the capture once all chunks arrive).

## Frame conventions

- Sensor mounted with **+Z pointing down the shaft toward the clubhead**.
- **Single-IMU capture**: all sample fields come from the **ICM-20649**
  (±4000 dps / ±30 g) on one clock. Quaternions are computed by firmware
  (Madgwick over the ICM's gyro+accel, mag-free), body → world; linear
  acceleration is gravity-removed using that orientation.
- **Fallback build** (no ICM-20649): firmware fills the same fields from the
  BHI260AP (BHY2 Game Rotation Vector + Linear Acceleration) and applies
  pre-clip ramp extrapolation for speed. The packet format is identical —
  the app cannot tell which IMU produced a capture.
- Face angle = swing-twist of (address⁻¹ × impact) about body Z; positive = open (RH).
