import 'dart:math' as math;

/// Minimal, dependency-free 3D vector.
class Vector3 {
  final double x, y, z;
  const Vector3(this.x, this.y, this.z);

  static const Vector3 zero = Vector3(0, 0, 0);

  Vector3 operator +(Vector3 o) => Vector3(x + o.x, y + o.y, z + o.z);
  Vector3 operator -(Vector3 o) => Vector3(x - o.x, y - o.y, z - o.z);
  Vector3 operator *(double s) => Vector3(x * s, y * s, z * s);

  double dot(Vector3 o) => x * o.x + y * o.y + z * o.z;

  Vector3 cross(Vector3 o) =>
      Vector3(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x);

  double get length => math.sqrt(dot(this));

  Vector3 normalized() {
    final l = length;
    return l == 0 ? zero : Vector3(x / l, y / l, z / l);
  }

  @override
  String toString() =>
      '(${x.toStringAsFixed(3)}, ${y.toStringAsFixed(3)}, ${z.toStringAsFixed(3)})';
}

/// Minimal, dependency-free quaternion (scalar-first: w, x, y, z).
///
/// Convention: quaternions map BODY-frame vectors into the WORLD frame,
/// i.e. `vWorld = q.rotate(vBody)`.
class Quaternion {
  final double w, x, y, z;
  const Quaternion(this.w, this.x, this.y, this.z);

  static const Quaternion identity = Quaternion(1, 0, 0, 0);

  factory Quaternion.axisAngle(Vector3 axis, double angleRad) {
    final a = axis.normalized();
    final half = angleRad / 2;
    final s = math.sin(half);
    return Quaternion(math.cos(half), a.x * s, a.y * s, a.z * s);
  }

  Quaternion operator *(Quaternion o) => Quaternion(
        w * o.w - x * o.x - y * o.y - z * o.z,
        w * o.x + x * o.w + y * o.z - z * o.y,
        w * o.y - x * o.z + y * o.w + z * o.x,
        w * o.z + x * o.y - y * o.x + z * o.w,
      );

  Quaternion get conjugate => Quaternion(w, -x, -y, -z);

  double get norm => math.sqrt(w * w + x * x + y * y + z * z);

  Quaternion normalized() {
    final n = norm;
    if (n == 0) return identity;
    return Quaternion(w / n, x / n, y / n, z / n);
  }

  /// Rotates a body-frame vector into the world frame: q * v * q?.
  Vector3 rotate(Vector3 v) {
    final qv = Vector3(x, y, z);
    final uv = qv.cross(v);
    final uuv = qv.cross(uv);
    return v + (uv * (2 * w)) + (uuv * 2);
  }

  /// Swing-twist decomposition: returns the signed twist angle (radians)
  /// of this rotation about [axis], in the range [-pi, pi].
  ///
  /// Decomposes `this = swing * twist`, where `twist` is a pure rotation
  /// about [axis] and `swing` is a rotation about an axis perpendicular
  /// to it. Used to extract face rotation about the club shaft.
  double twistAngleAround(Vector3 axis) {
    final a = axis.normalized();
    final proj = Vector3(x, y, z).dot(a);
    // Twist component (unnormalized) is (w, a*proj); its rotation angle is
    // 2*atan2(proj, w) — normalization cancels inside atan2.
    var angle = 2 * math.atan2(proj, w);
    while (angle > math.pi) {
      angle -= 2 * math.pi;
    }
    while (angle < -math.pi) {
      angle += 2 * math.pi;
    }
    return angle;
  }

  @override
  String toString() =>
      'q(${w.toStringAsFixed(4)}, ${x.toStringAsFixed(4)}, ${y.toStringAsFixed(4)}, ${z.toStringAsFixed(4)})';
}
