// GolfTracker — Phase 1 firmware for the Arduino Nicla Sense ME.
//
// Implements docs/BLE_PROTOCOL.md: a custom BLE Swing Service plus the standard
// Battery Service. The ICM-20649 (wide-range ±4000 dps / ±30 g) is the ONLY
// motion source. Firmware runs a Madgwick filter to produce
// quaternion + gravity-removed linear acceleration, detects swings, and streams
// an instant-metrics packet at impact followed by the full chunked capture.
//
// STATUS: first implementation — compiles against the libraries in README.md,
// but IMPACT DETECTION, GRAVITY REMOVAL and FACE-ANGLE SIGN
// are heuristics/stubs to be validated against a launch monitor / 240 fps
// video (plan Phase 2/5). Search for "TODO" for the tuning points.
//
// MEMORY (2026-09-30, measured on this board): the ANNA-B112 has 64 KB of
// RAM and the mbed core + ArduinoBLE statics alone take ~33 KB (a
// BLE-less sketch: 12 KB; BLEbringup: 33 KB). The Cordio BLE stack then
// mallocs more at BLE.begin() and hard-crashes the board with
// "Assertion failed: _stack_buffer != NULL" when it can't get it. That is
// why Arduino_BHY2 was REMOVED outright (its buffers are linked in even
// if never begun) and the capture ring was trimmed — keep the "Global
// variables ... leaving N bytes" compile line above ~20 KB. If the BHI260
// fallback is ever implemented, it must buy its RAM back elsewhere.
//
// Libraries — PINNED after the 2026-09-30 debugging session:
//   * Arduino Mbed OS Nicla Boards core 3.5.4 (4.6.0's BLE stack needs
//     ~21 KB static + ~18 KB heap and cannot coexist with this firmware
//     on 64 KB — BLE.begin() dies with the Cordio "_stack_buffer" assert)
//   * ArduinoBLE 1.3.7 (era-matched to the core)
//   * Adafruit ICM20X (Adafruit_ICM20649); Nicla_System ships with the core.
// See firmware/README.md.

#include <ArduinoBLE.h>
#include <Nicla_System.h>
#include <Adafruit_ICM20649.h>
#include <Wire.h>

#include "src/gatt_protocol.h"
#include "src/madgwick.h"

using namespace gatt;

// ---------------- capture geometry ----------------
// 250 Hz (was 400): dropped 2026-09-30 to shrink the capture ring — at
// 400 Hz the ring + the ~33 KB BLE/core baseline left only ~15.5 KB and
// the Cordio BLE stack STILL failed its startup allocation. The wire
// format is rate-agnostic (every sample carries t_us and the seq-0
// header carries sampleRateHz, which the app reads), so no app change.
// 250 Hz keeps 4 ms resolution through the downswing; if impact detail
// ever needs 400 Hz again, the RAM must come from somewhere else.
static const float    SAMPLE_RATE_HZ = 250.0f;
static const uint32_t SAMPLE_PERIOD_US = (uint32_t)(1e6f / SAMPLE_RATE_HZ); // 4000
// 1.0 s of pre-roll still covers a full backswing-to-impact.
static const int      PRE_SAMPLES  = (int)(1.0f * SAMPLE_RATE_HZ);  // 250
static const int      POST_SAMPLES = (int)(0.35f * SAMPLE_RATE_HZ); // 87
static const int      CAP = PRE_SAMPLES + POST_SAMPLES;             // 337 -> 8.1 KB

// ---------------- swing-detection thresholds (TODO: validate) ----------------
static const float START_THRESH_RADS  = 3.0f;   // gyro magnitude to begin a swing
static const float IMPACT_MIN_RADS     = 6.0f;   // must exceed this to count as impact
static const float IMPACT_DROP_FRAC    = 0.6f;   // impact latched when omega < peak*frac
static const float STILL_THRESH_RADS   = 0.25f;  // "quiet" for auto-calibration
static const uint32_t STILL_HOLD_US    = 1000000;// 1 s still hold
static const uint32_t SWING_TIMEOUT_US = 1200000;// abort a swing that never impacts
static const float GRAVITY_MS2         = 9.80665f;
static const float GYRO_SAT_RADS       = 81.0f;  // near the ±4000 dps wire limit


// ---------------- power management (TODO: tune; see README) ----------------
static const uint32_t SLEEP_AFTER_US   = 120000000UL; // 120 s still -> light sleep
static const uint32_t SLEEP_PERIOD_US  = 50000;       // 20 Hz motion poll while asleep
static const float    WAKE_THRESH_RADS = 1.5f;        // motion that wakes to full rate
static const uint32_t SHIP_AFTER_US    = 0;           // 0 = never; else deep-off after this idle

// ---------------- ring buffer of wire-format samples ----------------
// Stored directly as SampleWire (24 B); t_us holds an ABSOLUTE micros()
// timestamp and is rebased on transmit. HEAP-ALLOCATED in setup() AFTER
// BLE.begin(): this core's Cordio stack takes a very large bite at BLE
// init (measured 2026-09-30: succeeds with ~31 KB free, fails with
// ~20 KB), so the ring must not statically occupy that RAM. The ring
// then adaptively takes what Cordio left (up to CAP samples, degrading
// the window instead of bricking the boot).
static SampleWire* ring = nullptr;
static int   ringCap = 0;    // samples actually allocated (<= CAP)
static int   postCap = POST_SAMPLES; // post-impact reserve, rescaled to
                                     // ringCap in setup() so a short ring
                                     // still spends most of itself on the
                                     // DOWNSWING before impact
static int   ringHead = 0;   // next write index
static int   ringCount = 0;  // valid samples (saturates at ringCap)

// ---------------- state machine ----------------
enum State { S_IDLE, S_ARMED, S_SWINGING, S_POST, S_SLEEP };
static State state = S_ARMED;   // hands-free: boot armed

static Madgwick filter;
static Adafruit_ICM20649 icm;
static bool icmOk = false;

static Quat  addressRef;                 // last calibrated square-face reference
static uint32_t stillSinceUs = 0;        // start of current quiet period (0 = none)

// swing tracking
static float    peakOmega = 0;
static Quat     impactQuat;
static uint32_t impactAbsUs = 0;
static uint32_t swingStartUs = 0;
static bool     impactLatched = false;
static uint8_t  sourceFlags = 0;

// timing
static uint32_t lastSampleUs = 0;
static uint32_t lastPreviewUs = 0;
static uint32_t lastBattUs = 0;

// ---------------- BLE objects ----------------
BLEService swingService(SWING_SERVICE);
BLECharacteristic swingData(SWING_DATA_CHAR, BLENotify, 185);
BLECharacteristic control(CONTROL_CHAR, BLEWrite, 1);
BLECharacteristic livePreview(LIVE_PREVIEW_CHAR, BLENotify, 16);
BLECharacteristic instantMetrics(INSTANT_METRICS_CHAR, BLENotify, 12);
BLEService batteryService(BATTERY_SERVICE);
BLEUnsignedCharCharacteristic batteryLevel(BATTERY_LEVEL_CHAR, BLERead | BLENotify);

// ---- forward declarations (Arduino auto-prototyping is unreliable with the
// custom Quat / SampleWire types, so declare these explicitly) ----
static int   oldestIndex();
static void  sendInstantMetrics();
static void  sendCapture();
static float faceAngleDeg();
static void  resetSwing();
static void  maybeNotifyBattery(uint32_t now);
static void  goToShipMode();
static void  onControlWrite(BLEDevice, BLECharacteristic);

// ================= helpers =================

static inline Quat readQuat(const SampleWire& s) {
  Quat q;
  q.w = s.qw / QUAT_SCALE; q.x = s.qx / QUAT_SCALE;
  q.y = s.qy / QUAT_SCALE; q.z = s.qz / QUAT_SCALE;
  return q;
}

// Face angle (deg) at impact relative to the address reference.
static float faceAngleDeg() {
  Quat delta = qMul(qConj(addressRef), impactQuat); // addressRef^-1 * impact
  float rad = twistAngleZ(delta);
  return rad * 57.2957795f; // TODO: confirm sign matches app (positive = open, RH)
}

// Send the 12-byte instant-metrics packet the moment impact is detected.
static void sendInstantMetrics() {
  InstantMetricsWire m = {};
  // In the final capture window impact sits PRE_SAMPLES in from the start
  // (we keep PRE before + POST after impact), so report that origin — keeps the
  // instant packet's t_us consistent with the burst's rebased timestamps.
  // Impact sits (ringCap - postCap) samples into the final window
  // (equals PRE_SAMPLES when the full ring was allocated).
  m.t_us = (uint32_t)((ringCap - postCap) * SAMPLE_PERIOD_US);
  m.peakOmega = sat16(peakOmega * OMEGA_SCALE);
  m.faceAngle = sat16(faceAngleDeg() * FACE_SCALE);
  m.sourceFlags = sourceFlags;
  instantMetrics.writeValue((uint8_t*)&m, sizeof(m));
}

static int oldestIndex() {
  // index of the oldest valid sample in the ring
  if (ringCount < ringCap) return 0;
  return ringHead; // full ring: head points at the oldest
}

// Transmit the frozen capture window as chunks (header + samples).
static void sendCapture() {
  const int n = ringCount;
  const uint16_t dataChunks = (uint16_t)((n + SAMPLES_PER_CHUNK - 1) / SAMPLES_PER_CHUNK);
  const uint16_t totalChunks = dataChunks + 1; // + header chunk
  const uint32_t startUs = ring[oldestIndex()].t_us;

  // --- header chunk (seq 0) ---
  {
    uint8_t buf[sizeof(ChunkFrame) + sizeof(Seq0Payload)];
    ChunkFrame f = { 0, totalChunks };
    Seq0Payload h = {};
    h.sampleCount = (uint32_t)n;
    h.sampleRateHz = (uint16_t)SAMPLE_RATE_HZ;
    h.qw = sat16(addressRef.w * QUAT_SCALE);
    h.qx = sat16(addressRef.x * QUAT_SCALE);
    h.qy = sat16(addressRef.y * QUAT_SCALE);
    h.qz = sat16(addressRef.z * QUAT_SCALE);
    h.sourceFlags = sourceFlags;
    memcpy(buf, &f, sizeof(f));
    memcpy(buf + sizeof(f), &h, sizeof(h));
    swingData.writeValue(buf, sizeof(buf));
  }

  // --- sample chunks (seq 1..dataChunks) ---
  int idx = oldestIndex();
  for (uint16_t chunk = 0; chunk < dataChunks; chunk++) {
    int count = n - chunk * SAMPLES_PER_CHUNK;
    if (count > (int)SAMPLES_PER_CHUNK) count = SAMPLES_PER_CHUNK;

    uint8_t buf[sizeof(ChunkFrame) + SAMPLES_PER_CHUNK * sizeof(SampleWire)];
    ChunkFrame f = { (uint16_t)(chunk + 1), totalChunks };
    memcpy(buf, &f, sizeof(f));

    for (int i = 0; i < count; i++) {
      SampleWire s = ring[idx];
      s.t_us -= startUs; // rebase absolute -> since-capture-start
      memcpy(buf + sizeof(f) + i * sizeof(SampleWire), &s, sizeof(SampleWire));
      idx = (idx + 1) % ringCap;
    }
    swingData.writeValue(buf, sizeof(f) + count * sizeof(SampleWire));
    BLE.poll(); // keep the stack serviced during the burst
  }
}

static void resetSwing() {
  peakOmega = 0;
  impactLatched = false;
  impactAbsUs = 0;
  // fallback/quality flags recomputed per swing; keep hard-fault bit sticky
  sourceFlags &= SRC_BHY2_FALLBACK;
}

// Notify battery level at most every 30 s (0-100%, skips unknown readings).
static void maybeNotifyBattery(uint32_t now) {
  if ((uint32_t)(now - lastBattUs) >= 30000000UL || lastBattUs == 0) {
    lastBattUs = now;
    // Core 3.5.4's Nicla_System has no battery-percentage API (that
    // arrived with core 4.x, whose BLE stack no longer fits this board —
    // see the MEMORY note). The Battery Service stays registered but no
    // readings are pushed. TODO: read the BQ25120A PMIC directly.
  }
}

// Deep-off for storage: isolates the battery via the PMIC. Wakes on USB / reset.
static void goToShipMode() {
  BLE.stopAdvertise();
  BLE.disconnect();
  nicla::enterShipMode();
}

// ================= control characteristic =================
static void onControlWrite(BLEDevice, BLECharacteristic c) {
  if (c.valueLength() < 1) return;
  uint8_t op = c.value()[0];
  switch (op) {
    case OP_CALIBRATE_ADDRESS:
      addressRef = filter.quat(); // TODO: also zero gyro bias over the hold
      break;
    case OP_ARM:
      state = S_ARMED; resetSwing();
      break;
    case OP_DISARM:
      state = S_IDLE;
      break;
    case OP_SHIP_MODE:
      goToShipMode(); // deep-off for storage (protocol extension; app TODO)
      break;
  }
}

// ================= setup =================
void setup() {
  Serial.begin(115200);
  delay(2500); // let the serial monitor attach — boot lines kept getting cut off
  nicla::begin();
  // Core 3.5.4 API (see the MEMORY note): enableCharge, not the 4.x
  // enableCharging, and no charging safety-timer API.
  nicla::enableCharge(100); // charge from USB whenever connected (~0.4C)

  // BLE FIRST: the Cordio stack must allocate its buffers while the heap
  // is still whole, or it asserts ("_stack_buffer != NULL") and the board
  // never advertises. Sensors init after.
  if (!BLE.begin()) {
    Serial.println("GolfTracker firmware: BLE.begin() FAILED");
    while (1) delay(100);
  }
  BLE.setLocalName("GolfTracker");
  BLE.setDeviceName("GolfTracker");
  BLE.setAdvertisedService(swingService);

  swingService.addCharacteristic(swingData);
  swingService.addCharacteristic(control);
  swingService.addCharacteristic(livePreview);
  swingService.addCharacteristic(instantMetrics);
  BLE.addService(swingService);

  batteryService.addCharacteristic(batteryLevel);
  BLE.addService(batteryService);

  control.setEventHandler(BLEWritten, onControlWrite);
  BLE.advertise();
  // One boot line so a healthy board is distinguishable from a dead one
  // at a glance — a silent monitor once read as "broken" when it meant
  // "running fine".
  Serial.println("GolfTracker firmware: advertising (BLE up)");

  // Measure the largest contiguous heap block the BLE stack left behind
  // (binary search on malloc), print it, then take it for the ring minus
  // slack for the connection's own runtime allocations. This turns the
  // memory fight into a number instead of a guess.
  size_t lo = 0, hi = 40960;
  while (hi - lo > 128) {
    size_t mid = (lo + hi) / 2;
    void* p = malloc(mid);
    if (p != nullptr) {
      free(p);
      lo = mid;
    } else {
      hi = mid;
    }
  }
  Serial.print("GolfTracker firmware: largest free block after BLE: ");
  Serial.print((unsigned)lo);
  Serial.println(" B");

  const size_t slack = 2560;
  int cap = (lo > slack) ? (int)((lo - slack) / sizeof(SampleWire)) : 0;
  if (cap > CAP) cap = CAP;
  if (cap >= 72) {
    ring = (SampleWire*)malloc((size_t)cap * sizeof(SampleWire));
  }
  if (ring == nullptr) {
    Serial.println("GolfTracker firmware: ring allocation FAILED");
    while (1) delay(1000);
  }
  ringCap = cap;
  // Rescale the post-impact reserve so a short ring still spends ~3/4 of
  // itself on the downswing BEFORE impact.
  postCap = (ringCap >= CAP) ? POST_SAMPLES
                             : (ringCap * POST_SAMPLES) / CAP;
  if (postCap < 10) postCap = 10;
  Serial.print("GolfTracker firmware: ring ");
  Serial.print(ringCap);
  Serial.print("/");
  Serial.print(CAP);
  Serial.print(" samples (");
  Serial.print((ringCap - postCap) / SAMPLE_RATE_HZ, 2);
  Serial.print(" s pre + ");
  Serial.print(postCap / SAMPLE_RATE_HZ, 2);
  Serial.println(" s post impact)");

  Wire.begin();
  icmOk = icm.begin_I2C(0x68, &Wire);
  if (icmOk) {
    icm.setGyroRange(ICM20649_GYRO_RANGE_4000_DPS);
    icm.setAccelRange(ICM20649_ACCEL_RANGE_30_G);
    // TODO: set the highest stable ODR; default output is fine for bring-up.
  } else {
    sourceFlags |= SRC_BHY2_FALLBACK; // no ICM -> whole session is fallback
  }

  lastSampleUs = micros();
}

// ================= main loop =================
void loop() {
  BLE.poll();

  uint32_t now = micros();
  // Pace at 400 Hz normally, but only ~20 Hz while asleep (motion-watch).
  uint32_t periodUs = (state == S_SLEEP) ? SLEEP_PERIOD_US : SAMPLE_PERIOD_US;
  if ((uint32_t)(now - lastSampleUs) < periodUs) return;
  float dt = (now - lastSampleUs) * 1e-6f;
  lastSampleUs = now;


  // ---- read the primary IMU ----
  float gx = 0, gy = 0, gz = 0, ax = 0, ay = 0, az = 0;
  if (icmOk) {
    sensors_event_t a, g, t;
    if (icm.getEvent(&a, &g, &t)) {
      gx = g.gyro.x; gy = g.gyro.y; gz = g.gyro.z;                 // rad/s
      ax = a.acceleration.x; ay = a.acceleration.y; az = a.acceleration.z; // m/s^2
    } else {
      // TODO: hard-fault failover — switch capture source to BHY2 stream.
      sourceFlags |= SRC_BHY2_FALLBACK;
    }
  }
  // TODO: when SRC_BHY2_FALLBACK, fill gx..az from BHY2 Game Rotation Vector +
  // Linear Acceleration instead (the packet format is identical).

  float omega = sqrtf(gx * gx + gy * gy + gz * gz);
  if (omega > GYRO_SAT_RADS) sourceFlags |= SRC_GYRO_SATURATION;

  // ---- light sleep: skip fusion/capture, just watch for motion ----
  if (state == S_SLEEP) {
    if (omega > WAKE_THRESH_RADS) {   // picked up / moved -> wake to full rate
      state = S_ARMED;
      stillSinceUs = 0;
      resetSwing();
      filter = Madgwick();            // reset stale orientation; re-converges fast
    } else if (SHIP_AFTER_US > 0 && stillSinceUs != 0 &&
               (uint32_t)(now - stillSinceUs) >= SHIP_AFTER_US) {
      goToShipMode();                 // optional deep-off for long storage
    }
    maybeNotifyBattery(now);
    return;
  }

  // ---- fuse orientation & remove gravity ----
  filter.update(gx, gy, gz, ax, ay, az, dt);
  Quat q = filter.quat();
  float grx, gry, grz;
  gravityBody(q, grx, gry, grz);
  float lax = ax - grx * GRAVITY_MS2;
  float lay = ay - gry * GRAVITY_MS2;
  float laz = az - grz * GRAVITY_MS2;

  // ---- push into the ring (wire format, absolute timestamp) ----
  SampleWire& s = ring[ringHead];
  s.t_us = now;
  s.qw = sat16(q.w * QUAT_SCALE); s.qx = sat16(q.x * QUAT_SCALE);
  s.qy = sat16(q.y * QUAT_SCALE); s.qz = sat16(q.z * QUAT_SCALE);
  s.gx = sat16(gx * GYRO_SCALE);  s.gy = sat16(gy * GYRO_SCALE);  s.gz = sat16(gz * GYRO_SCALE);
  s.ax = sat16(lax * ACCEL_SCALE); s.ay = sat16(lay * ACCEL_SCALE); s.az = sat16(laz * ACCEL_SCALE);
  ringHead = (ringHead + 1) % ringCap;
  if (ringCount < ringCap) ringCount++;

  // ---- auto-calibration on a still hold (hands-free) ----
  if (omega < STILL_THRESH_RADS) {
    if (stillSinceUs == 0) stillSinceUs = now;
    else if ((uint32_t)(now - stillSinceUs) >= STILL_HOLD_US) {
      addressRef = q;      // silently zero the square-face reference
      // TODO: also compute & subtract a gyro-bias offset over the hold window
    }
  } else {
    stillSinceUs = 0;
  }

  // ---- live preview (decimated ~25 Hz) ----
  if (state != S_IDLE && (uint32_t)(now - lastPreviewUs) >= 40000) {
    lastPreviewUs = now;
    int16_t pv[4] = { s.qw, s.qx, s.qy, s.qz };
    livePreview.writeValue((uint8_t*)pv, sizeof(pv));
  }

  // ---- battery level notify (every 30 s) ----
  maybeNotifyBattery(now);

  // ---- swing state machine ----
  switch (state) {
    case S_IDLE:
      break;

    case S_ARMED:
      if (omega > START_THRESH_RADS) {
        state = S_SWINGING;
        swingStartUs = now;
        resetSwing();
      } else if (stillSinceUs != 0 &&
                 (uint32_t)(now - stillSinceUs) >= SLEEP_AFTER_US) {
        state = S_SLEEP;   // auto-sleep after prolonged stillness
      }
      break;

    case S_SWINGING:
      if (omega > peakOmega) {          // track the peak = impact candidate
        peakOmega = omega;
        impactQuat = q;
        impactAbsUs = now;
      }
      // Latch impact once we've clearly peaked and started decelerating.
      // TODO: replace with an accelerometer-spike impact detector for accuracy.
      if (!impactLatched && peakOmega > IMPACT_MIN_RADS &&
          omega < peakOmega * IMPACT_DROP_FRAC) {
        impactLatched = true;
        sendInstantMetrics();           // <500 ms HUD packet
        state = S_POST;
      }
      if ((uint32_t)(now - swingStartUs) > SWING_TIMEOUT_US) {
        state = S_ARMED;                // false trigger; re-arm
        resetSwing();
      }
      break;

    case S_POST:
      // Keep sampling until postCap samples have accrued past impact, so the ring
      // holds the full [-1.5 s, +0.5 s] window, then freeze and transmit.
      if ((uint32_t)(now - impactAbsUs) >= (uint32_t)(postCap * SAMPLE_PERIOD_US)) {
        sendCapture();
        state = S_ARMED;                // auto re-arm
        resetSwing();
      }
      break;
  }
}
