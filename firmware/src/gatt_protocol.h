// GolfTracker firmware <-> app BLE contract.
// Keep this file in sync with ../../lib/src/sensor/gatt_protocol.dart and
// ../../docs/BLE_PROTOCOL.md. The Dart codec is the reference; these structs
// must byte-for-byte match it (little-endian; the Nicla's Cortex-M4 is
// little-endian, so packed structs map directly onto the wire).
#pragma once
#include <Arduino.h>

namespace gatt {

// ---- 128-bit service / characteristic UUIDs ----
constexpr const char* SWING_SERVICE        = "f3641400-00b0-4240-ba50-05ca45bf8abc";
constexpr const char* SWING_DATA_CHAR      = "f3641401-00b0-4240-ba50-05ca45bf8abc"; // notify
constexpr const char* CONTROL_CHAR         = "f3641402-00b0-4240-ba50-05ca45bf8abc"; // write
constexpr const char* LIVE_PREVIEW_CHAR    = "f3641403-00b0-4240-ba50-05ca45bf8abc"; // notify
constexpr const char* INSTANT_METRICS_CHAR = "f3641404-00b0-4240-ba50-05ca45bf8abc"; // notify

// Standard Battery Service (16-bit UUIDs, ArduinoBLE shorthand).
constexpr const char* BATTERY_SERVICE      = "180F";
constexpr const char* BATTERY_LEVEL_CHAR   = "2A19"; // read | notify, 0-100 (%)

// ---- Control opcodes (single byte written to Control characteristic) ----
enum ControlOp : uint8_t {
  OP_CALIBRATE_ADDRESS = 0x01, // store orientation as address ref, zero gyro bias
  OP_ARM               = 0x02, // watch for swing trigger
  OP_DISARM            = 0x03, // stop watching (disables auto re-arm until ARM)
  // Firmware extension (NOT yet in BLE_PROTOCOL.md or the app's ControlOp):
  OP_SHIP_MODE         = 0x04, // deep-off / battery isolation for storage
};

// ---- sourceFlags bits (shared by capture header and instant metrics) ----
enum SourceFlag : uint8_t {
  SRC_BHY2_FALLBACK    = 1 << 0, // 0 = ICM-20649 primary, 1 = BHY2 fallback
  SRC_ICM_QUALITY_FAIL = 1 << 1, // ICM present but failed quality checks
  SRC_GYRO_SATURATION  = 1 << 2, // gyro saturation detected (speed extrapolated)
};

// ---- fixed-point scales (must match the Dart codec exactly) ----
constexpr float QUAT_SCALE  = 32767.0f; // quaternion * 32767
constexpr float GYRO_SCALE  = 400.0f;   // gyro rad/s * 400   (sat ±81.9 rad/s)
constexpr float ACCEL_SCALE = 100.0f;   // lin accel m/s^2 * 100 (sat ±327 m/s^2)
constexpr float OMEGA_SCALE = 400.0f;   // instant-metrics peak omega rad/s * 400
constexpr float FACE_SCALE  = 100.0f;   // instant-metrics face angle deg * 100

constexpr uint16_t SAMPLES_PER_CHUNK = 7; // 7 * 24B = 168B payload -> 172B chunk

// Saturating float -> int16 (mirrors SwingPacketCodec._sat).
static inline int16_t sat16(float v) {
  long r = lroundf(v);
  if (r >  32767) r =  32767;
  if (r < -32768) r = -32768;
  return (int16_t)r;
}

#pragma pack(push, 1)
// Every chunk starts with this 4-byte frame: u16 seq | u16 totalChunks.
struct ChunkFrame {
  uint16_t seq;
  uint16_t totalChunks;
};

// Chunk seq=0 payload (20 bytes) — the capture header.
struct Seq0Payload {
  uint32_t sampleCount;
  uint16_t sampleRateHz;
  int16_t  qw, qx, qy, qz; // address-reference quaternion * 32767
  uint8_t  sourceFlags;
  uint8_t  pad;
  uint32_t reserved;
};

// Chunks seq=1..N payload: up to SAMPLES_PER_CHUNK of these (24 bytes each).
struct SampleWire {
  uint32_t t_us;            // microseconds since capture start
  int16_t  qw, qx, qy, qz;  // quaternion * 32767 (body -> world)
  int16_t  gx, gy, gz;      // gyro rad/s * 400
  int16_t  ax, ay, az;      // linear accel m/s^2 * 100 (gravity removed)
};

// Instant Metrics characteristic payload (12 bytes).
struct InstantMetricsWire {
  uint32_t t_us;        // impact time, microseconds since capture start
  int16_t  peakOmega;   // rad/s * 400
  int16_t  faceAngle;   // deg * 100 (positive = open, RH)
  uint8_t  sourceFlags;
  uint8_t  reserved8;
  uint16_t reserved16;
};
#pragma pack(pop)

static_assert(sizeof(ChunkFrame) == 4,           "ChunkFrame must be 4 bytes");
static_assert(sizeof(Seq0Payload) == 20,         "Seq0Payload must be 20 bytes");
static_assert(sizeof(SampleWire) == 24,          "SampleWire must be 24 bytes");
static_assert(sizeof(InstantMetricsWire) == 12,  "InstantMetrics must be 12 bytes");

} // namespace gatt
