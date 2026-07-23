/// A club profile holds the physics constants used to scale grip angular
/// velocity into clubhead speed (v = omega * r) and to reconstruct the
/// clubhead path from the shaft-mounted sensor's motion.
class ClubProfile {
  final String id;
  final String name;

  /// Total club length, in meters. Informational since the sensor moved from
  /// the grip butt-end to a clamp on the bare shaft: it is no longer the
  /// effective radius. Kept for display and calibration diagnostics.
  final double shaftLengthM;

  /// Distance from the shaft-mounted sensor to the clubface, measured along
  /// the shaft, in meters. This is the effective radius `r` in v = omega * r
  /// AND the lever-arm length used to reconstruct the clubhead path
  /// (clubhead = sensor + orientation * (r along the shaft +Z axis)).
  final double deviceToFaceDistanceM;

  const ClubProfile({
    required this.id,
    required this.name,
    required this.shaftLengthM,
    this.deviceToFaceDistanceM = 1.0,
  });

  ClubProfile copyWith({
    String? name,
    double? shaftLengthM,
    double? deviceToFaceDistanceM,
  }) =>
      ClubProfile(
        id: id,
        name: name ?? this.name,
        shaftLengthM: shaftLengthM ?? this.shaftLengthM,
        deviceToFaceDistanceM:
            deviceToFaceDistanceM ?? this.deviceToFaceDistanceM,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'shaftLengthM': shaftLengthM,
        'deviceToFaceDistanceM': deviceToFaceDistanceM,
      };

  factory ClubProfile.fromJson(Map<String, dynamic> j) => ClubProfile(
        id: j['id'] as String,
        name: j['name'] as String,
        shaftLengthM: (j['shaftLengthM'] as num).toDouble(),
        // Back-compat: exports predating the sensor-on-shaft remount used
        // shaft length as the radius, so fall back to it.
        deviceToFaceDistanceM:
            (j['deviceToFaceDistanceM'] as num?)?.toDouble() ??
                (j['shaftLengthM'] as num).toDouble(),
      );

  @override
  bool operator ==(Object other) =>
      other is ClubProfile &&
      other.id == id &&
      other.name == name &&
      other.shaftLengthM == shaftLengthM &&
      other.deviceToFaceDistanceM == deviceToFaceDistanceM;

  @override
  int get hashCode =>
      Object.hash(id, name, shaftLengthM, deviceToFaceDistanceM);

  /// Standard men's club lengths (meters), with the sensor-to-clubface
  /// distance for a clamp mounted just below the grip (roughly the shaft
  /// length minus the grip). Refine per-club during field calibration.
  static const List<ClubProfile> defaults = [
    ClubProfile(
        id: 'driver',
        name: 'Driver',
        shaftLengthM: 1.143,
        deviceToFaceDistanceM: 1.0),
    ClubProfile(
        id: '3w',
        name: '3 Wood',
        shaftLengthM: 1.092,
        deviceToFaceDistanceM: 0.95),
    ClubProfile(
        id: '5i',
        name: '5 Iron',
        shaftLengthM: 0.972,
        deviceToFaceDistanceM: 0.83),
    ClubProfile(
        id: '7i',
        name: '7 Iron',
        shaftLengthM: 0.940,
        deviceToFaceDistanceM: 0.80),
    ClubProfile(
        id: '9i',
        name: '9 Iron',
        shaftLengthM: 0.914,
        deviceToFaceDistanceM: 0.78),
    ClubProfile(
        id: 'pw',
        name: 'Pitching Wedge',
        shaftLengthM: 0.902,
        deviceToFaceDistanceM: 0.77),
    ClubProfile(
        id: 'putter',
        name: 'Putter',
        shaftLengthM: 0.864,
        deviceToFaceDistanceM: 0.72),
  ];
}
