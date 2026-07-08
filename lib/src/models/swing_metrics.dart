import '../processing/quaternion.dart';

/// Computed results for one swing — what the HUD and history screens show.
class SwingMetrics {
  final DateTime timestamp;
  final String clubId;

  /// Which sensor produced this swing (BLE remoteId or mock id) and its
  /// user-assigned label (player or club name). Empty for single-sensor use.
  final String deviceId;
  final String deviceLabel;

  /// Estimated clubhead speed at impact, m/s (v = omega * r).
  final double clubSpeedMps;

  /// Face angle at impact relative to address, degrees.
  /// Positive = open (RH golfer), negative = closed.
  final double faceAngleDeg;

  /// Grip-end path in world frame, meters, from address to follow-through.
  final List<Vector3> pathM;

  /// Index into [pathM] of the impact moment.
  final int impactIndex;

  /// Source/quality flags carried through from the capture
  /// (docs/BLE_PROTOCOL.md): bit0 = BHY2 fallback capture, bit1 = ICM
  /// present but failed quality checks, bit2 = gyro saturation detected.
  /// Repeated fallback flags are the early warning that the ICM's glued
  /// VIN joint needs attention.
  final int sourceFlags;

  const SwingMetrics({
    required this.timestamp,
    required this.clubId,
    required this.clubSpeedMps,
    required this.faceAngleDeg,
    required this.pathM,
    required this.impactIndex,
    this.deviceId = '',
    this.deviceLabel = '',
    this.sourceFlags = 0,
  });

  double get clubSpeedMph => clubSpeedMps * 2.23694;

  String get faceLabel {
    if (faceAngleDeg.abs() < 1.0) return 'Square';
    return faceAngleDeg > 0 ? 'Open' : 'Closed';
  }

  bool get isFallbackCapture => sourceFlags & 0x01 != 0;
  bool get failedQualityChecks => sourceFlags & 0x02 != 0;
  bool get speedExtrapolated => sourceFlags & 0x04 != 0;

  /// True when any quality flag is set — the UI shows a warning badge.
  bool get hasQualityFlags => sourceFlags != 0;

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'clubId': clubId,
        'deviceId': deviceId,
        'deviceLabel': deviceLabel,
        'clubSpeedMps': clubSpeedMps,
        'faceAngleDeg': faceAngleDeg,
        'impactIndex': impactIndex,
        'sourceFlags': sourceFlags,
        'pathM': pathM.map((p) => [p.x, p.y, p.z]).toList(),
      };

  factory SwingMetrics.fromJson(Map<String, dynamic> j) => SwingMetrics(
        timestamp: DateTime.parse(j['timestamp'] as String),
        clubId: j['clubId'] as String,
        deviceId: (j['deviceId'] as String?) ?? '',
        deviceLabel: (j['deviceLabel'] as String?) ?? '',
        clubSpeedMps: (j['clubSpeedMps'] as num).toDouble(),
        faceAngleDeg: (j['faceAngleDeg'] as num).toDouble(),
        impactIndex: j['impactIndex'] as int,
        sourceFlags: (j['sourceFlags'] as int?) ?? 0,
        pathM: (j['pathM'] as List)
            .map((p) => Vector3((p[0] as num).toDouble(),
                (p[1] as num).toDouble(), (p[2] as num).toDouble()))
            .toList(),
      );
}
