// Minimal Madgwick IMU (6-axis, gyro+accel, magnetometer-free) filter plus the
// small quaternion helpers the firmware needs for gravity removal and the
// swing-twist face-angle calculation. Dependency-free; matches the mag-free
// fusion the app assumes (quaternions are body -> world).
#pragma once
#include <math.h>

struct Quat {
  float w = 1, x = 0, y = 0, z = 0;
};

class Madgwick {
public:
  float q0 = 1, q1 = 0, q2 = 0, q3 = 0; // body -> world
  float beta = 0.1f;                     // fusion gain (tune during validation)

  void setBeta(float b) { beta = b; }

  Quat quat() const {
    Quat q;
    q.w = q0; q.x = q1; q.y = q2; q.z = q3;
    return q;
  }

  // gyro in rad/s, accel in any consistent unit (normalized internally),
  // dt in seconds.
  void update(float gx, float gy, float gz,
              float ax, float ay, float az, float dt) {
    float recipNorm;
    float s0, s1, s2, s3;
    float qDot1, qDot2, qDot3, qDot4;
    float _2q0, _2q1, _2q2, _2q3, _4q0, _4q1, _4q2, _8q1, _8q2;
    float q0q0, q1q1, q2q2, q3q3;

    qDot1 = 0.5f * (-q1 * gx - q2 * gy - q3 * gz);
    qDot2 = 0.5f * ( q0 * gx + q2 * gz - q3 * gy);
    qDot3 = 0.5f * ( q0 * gy - q1 * gz + q3 * gx);
    qDot4 = 0.5f * ( q0 * gz + q1 * gy - q2 * gx);

    // Only apply the accel correction when the reading is non-zero.
    if (!(ax == 0.0f && ay == 0.0f && az == 0.0f)) {
      recipNorm = invSqrt(ax * ax + ay * ay + az * az);
      ax *= recipNorm; ay *= recipNorm; az *= recipNorm;

      _2q0 = 2 * q0; _2q1 = 2 * q1; _2q2 = 2 * q2; _2q3 = 2 * q3;
      _4q0 = 4 * q0; _4q1 = 4 * q1; _4q2 = 4 * q2;
      _8q1 = 8 * q1; _8q2 = 8 * q2;
      q0q0 = q0 * q0; q1q1 = q1 * q1; q2q2 = q2 * q2; q3q3 = q3 * q3;

      s0 = _4q0 * q2q2 + _2q2 * ax + _4q0 * q1q1 - _2q1 * ay;
      s1 = _4q1 * q3q3 - _2q3 * ax + 4 * q0q0 * q1 - _2q0 * ay - _4q1
           + _8q1 * q1q1 + _8q1 * q2q2 + _4q1 * az;
      s2 = 4 * q0q0 * q2 + _2q0 * ax + _4q2 * q3q3 - _2q3 * ay - _4q2
           + _8q2 * q1q1 + _8q2 * q2q2 + _4q2 * az;
      s3 = 4 * q1q1 * q3 - _2q1 * ax + 4 * q2q2 * q3 - _2q2 * ay;

      recipNorm = invSqrt(s0 * s0 + s1 * s1 + s2 * s2 + s3 * s3);
      s0 *= recipNorm; s1 *= recipNorm; s2 *= recipNorm; s3 *= recipNorm;

      qDot1 -= beta * s0;
      qDot2 -= beta * s1;
      qDot3 -= beta * s2;
      qDot4 -= beta * s3;
    }

    q0 += qDot1 * dt;
    q1 += qDot2 * dt;
    q2 += qDot3 * dt;
    q3 += qDot4 * dt;

    recipNorm = invSqrt(q0 * q0 + q1 * q1 + q2 * q2 + q3 * q3);
    q0 *= recipNorm; q1 *= recipNorm; q2 *= recipNorm; q3 *= recipNorm;
  }

  static float invSqrt(float x) { return 1.0f / sqrtf(x); }
};

// ---- quaternion helpers ----

static inline Quat qMul(const Quat& a, const Quat& b) {
  Quat r;
  r.w = a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z;
  r.x = a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y;
  r.y = a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x;
  r.z = a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w;
  return r;
}

static inline Quat qConj(const Quat& q) {
  Quat r; r.w = q.w; r.x = -q.x; r.y = -q.y; r.z = -q.z; return r;
}

// Gravity unit vector expressed in the body frame, from a body->world quat.
// (When static, the accelerometer's specific-force direction matches this.)
static inline void gravityBody(const Quat& q, float& gx, float& gy, float& gz) {
  gx = 2.0f * (q.x * q.z - q.w * q.y);
  gy = 2.0f * (q.w * q.x + q.y * q.z);
  gz = q.w * q.w - q.x * q.x - q.y * q.y + q.z * q.z;
}

// Swing-twist angle (radians) of a delta quaternion about the body +Z axis.
// Used for face angle: delta = addressRef^-1 * impact; positive = open (RH).
static inline float twistAngleZ(const Quat& delta) {
  // Project onto the Z axis (swing-twist decomposition), then extract angle.
  float w = delta.w, z = delta.z;
  float n = sqrtf(w * w + z * z);
  if (n < 1e-9f) return 0.0f;
  w /= n; z /= n;
  return 2.0f * atan2f(z, w);
}
