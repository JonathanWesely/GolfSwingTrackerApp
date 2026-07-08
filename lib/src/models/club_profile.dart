/// A club profile holds the physics constant (shaft length) used to scale
/// grip angular velocity into clubhead speed: v = omega * r.
class ClubProfile {
  final String id;
  final String name;

  /// Effective radius from swing rotation to clubhead, in meters.
  /// Approximated by club length; refine per-club during field calibration.
  final double shaftLengthM;

  const ClubProfile({
    required this.id,
    required this.name,
    required this.shaftLengthM,
  });

  ClubProfile copyWith({String? name, double? shaftLengthM}) => ClubProfile(
        id: id,
        name: name ?? this.name,
        shaftLengthM: shaftLengthM ?? this.shaftLengthM,
      );

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'shaftLengthM': shaftLengthM};

  factory ClubProfile.fromJson(Map<String, dynamic> j) => ClubProfile(
        id: j['id'] as String,
        name: j['name'] as String,
        shaftLengthM: (j['shaftLengthM'] as num).toDouble(),
      );

  /// Standard men's club lengths (meters).
  static const List<ClubProfile> defaults = [
    ClubProfile(id: 'driver', name: 'Driver', shaftLengthM: 1.143),
    ClubProfile(id: '3w', name: '3 Wood', shaftLengthM: 1.092),
    ClubProfile(id: '5i', name: '5 Iron', shaftLengthM: 0.972),
    ClubProfile(id: '7i', name: '7 Iron', shaftLengthM: 0.940),
    ClubProfile(id: '9i', name: '9 Iron', shaftLengthM: 0.914),
    ClubProfile(id: 'pw', name: 'Pitching Wedge', shaftLengthM: 0.902),
    ClubProfile(id: 'putter', name: 'Putter', shaftLengthM: 0.864),
  ];
}
