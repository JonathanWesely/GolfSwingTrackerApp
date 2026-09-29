import 'dart:async';
import 'dart:typed_data';

import '../models/swing_capture.dart';
import 'ble_transport.dart';
import 'flutter_blue_plus_transport.dart';
import 'gatt_protocol.dart';
import 'sensor_link.dart';

/// Real Nicla Sense ME link, implementing docs/BLE_PROTOCOL.md over a
/// [BleTransport]. All protocol logic lives here and is covered by unit
/// tests against a fake transport; the only untested code path is the thin
/// flutter_blue_plus adapter itself.
///
/// Behavior:
///  - connect(): scan for the advertised name (or go straight to
///    [targetRemoteId]), connect, negotiate MTU >= 185, subscribe to
///    swing-data, instant-metrics, and battery characteristics.
///  - Swing bursts are reassembled from chunks in any order, tolerating
///    retransmits; a stalled partial capture is dropped after
///    [captureStallTimeout] so the next swing starts clean.
///  - Unexpected disconnects trigger automatic reconnection with backoff
///    ([reconnectDelays], capped at its last entry) until [disconnect] or
///    [dispose] is called. Firmware auto-(re)arms on boot/connect, and
///    AppState re-arms on `connected` in hands-free mode, so a reconnect
///    resumes hands-free capture without user action.
class BleSensorLink implements SensorLink {
  static const String advertisedName = 'GolfTracker';

  /// The Swing Service UUID the firmware puts in its advertising packet —
  /// scans match on THIS (iOS can report a device without its name; see
  /// BleTransport.scan).
  static const String advertisedService = GattIds.swingService;

  /// Protocol minimum for 7-samples-per-chunk bursts (see BLE_PROTOCOL.md).
  static const int desiredMtu = 185;

  /// When set, connect() targets this exact device (BLE address) — required
  /// for multi-sensor setups where several devices advertise the same name.
  /// When null, connects to the first device matching [advertisedName].
  final String? targetRemoteId;

  final BleTransport _transport;
  final Duration scanTimeout;
  final Duration captureStallTimeout;
  final Duration calibrateSettle;
  final List<Duration> reconnectDelays;

  BleSensorLink({
    this.targetRemoteId,
    BleTransport? transport,
    this.scanTimeout = const Duration(seconds: 10),
    this.captureStallTimeout = const Duration(seconds: 10),
    this.calibrateSettle = const Duration(milliseconds: 1200),
    this.reconnectDelays = const [
      Duration(seconds: 1),
      Duration(seconds: 2),
      Duration(seconds: 4),
      Duration(seconds: 8),
      Duration(seconds: 15),
    ],
  }) : _transport = transport ?? FlutterBluePlusTransport();

  final _statusCtrl = StreamController<SensorStatus>.broadcast();
  final _swingCtrl = StreamController<SwingCapture>.broadcast();
  final _instantCtrl = StreamController<InstantMetrics>.broadcast();
  final _batteryCtrl = StreamController<double>.broadcast();

  SensorStatus _status = SensorStatus.disconnected;
  BleDeviceSession? _session;
  final List<StreamSubscription<dynamic>> _subs = [];

  /// The remoteId we actually connected to (== targetRemoteId when set).
  String? connectedRemoteId;

  /// MTU negotiated on the current connection (null before connect).
  int? negotiatedMtu;

  bool _userDisconnected = false;
  bool _disposed = false;
  int _reconnectAttempt = 0;
  Timer? _reconnectTimer;

  List<Uint8List?> _chunks = [];
  Timer? _captureStallTimer;

  @override
  SensorStatus get status => _status;
  @override
  Stream<SensorStatus> get statusStream => _statusCtrl.stream;
  @override
  Stream<SwingCapture> get swings => _swingCtrl.stream;
  @override
  Stream<InstantMetrics> get instantMetrics => _instantCtrl.stream;
  @override
  Stream<double> get batteryLevel => _batteryCtrl.stream;

  void _setStatus(SensorStatus s) {
    if (_disposed) return;
    _status = s;
    _statusCtrl.add(s);
  }

  @override
  Future<void> connect() async {
    if (_disposed) throw StateError('BleSensorLink is disposed');
    _userDisconnected = false;
    _reconnectTimer?.cancel();
    _setStatus(SensorStatus.connecting);
    try {
      final remoteId = targetRemoteId ?? await _findDevice();
      final session = await _transport.connect(remoteId);
      _session = session;
      connectedRemoteId = session.remoteId;

      // Chunked bursts carry up to 7 samples (172 B); the protocol requires
      // an MTU of at least 185. iOS auto-negotiates; Android needs the ask.
      negotiatedMtu = await session.requestMtu(desiredMtu + 62);

      _subs.add(session
          .subscribe(GattIds.swingService, GattIds.swingDataChar)
          .listen(_onSwingChunk));
      _subs.add(session
          .subscribe(GattIds.swingService, GattIds.instantMetricsChar)
          .listen(_onInstantMetrics));
      _subs.add(session
          .subscribe(GattIds.batteryService, GattIds.batteryLevelChar)
          .listen(_onBattery));
      _subs.add(session.disconnected.take(1).listen((_) => _onLinkDropped()));

      // Initial battery level (notifications only fire on change).
      try {
        _onBattery(
            await session.read(GattIds.batteryService, GattIds.batteryLevelChar));
      } catch (_) {/* battery read is best-effort */}

      _reconnectAttempt = 0;
      _setStatus(SensorStatus.connected);
    } catch (e) {
      await _teardownSession();
      _setStatus(SensorStatus.disconnected);
      rethrow;
    }
  }

  /// Scans for the first device advertising [advertisedName].
  Future<String> _findDevice() async {
    final hit = await _transport
        .scan(
            name: advertisedName,
            serviceUuid: advertisedService,
            timeout: scanTimeout)
        .firstWhere((h) => targetRemoteId == null || h.remoteId == targetRemoteId,
            orElse: () => throw TimeoutException(
                'No $advertisedName sensor found within '
                '${scanTimeout.inSeconds}s — is it powered and in range?'));
    return hit.remoteId;
  }

  // --- Incoming data ------------------------------------------------------

  void _onSwingChunk(Uint8List data) {
    if (data.length < 4) return;
    final bd = ByteData.sublistView(data);
    final seq = bd.getUint16(0, Endian.little);
    final total = bd.getUint16(2, Endian.little);
    if (total == 0) return;

    // New capture (or first chunk ever): size the reassembly buffer.
    if (_chunks.length != total) {
      _chunks = List<Uint8List?>.filled(total, null);
    }
    if (seq < total) _chunks[seq] = data; // retransmits simply overwrite

    // Drop a stalled partial capture so the next burst starts clean.
    _captureStallTimer?.cancel();
    _captureStallTimer = Timer(captureStallTimeout, () => _chunks = []);

    final capture = SwingPacketCodec.decode(_chunks);
    if (capture != null) {
      _captureStallTimer?.cancel();
      _chunks = [];
      _swingCtrl.add(capture);
      // Firmware auto re-arms after every burst; reflect that by settling
      // at `connected` so hands-free mode (AppState) re-issues ARM, which
      // is idempotent firmware-side.
      _setStatus(SensorStatus.connected);
    }
  }

  void _onInstantMetrics(Uint8List data) {
    final m = InstantMetricsCodec.decode(data);
    if (m != null) _instantCtrl.add(m);
  }

  void _onBattery(Uint8List v) {
    if (v.isNotEmpty) _batteryCtrl.add((v[0].clamp(0, 100)) / 100);
  }

  // --- Reconnect ----------------------------------------------------------

  void _onLinkDropped() {
    _teardownSession();
    _setStatus(SensorStatus.disconnected);
    if (!_userDisconnected && !_disposed) _scheduleReconnect();
  }

  void _scheduleReconnect() {
    final delay = reconnectDelays[
        _reconnectAttempt.clamp(0, reconnectDelays.length - 1)];
    _reconnectAttempt++;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () async {
      if (_userDisconnected || _disposed) return;
      try {
        await connect();
      } catch (_) {
        // connect() already reset status; try again with longer backoff.
        if (!_userDisconnected && !_disposed) _scheduleReconnect();
      }
    });
  }

  Future<void> _teardownSession() async {
    _captureStallTimer?.cancel();
    _chunks = [];
    // Snapshot-and-clear first: teardown can be re-entered (dispose racing
    // a link-drop event), and awaiting inside a loop over the live list
    // would be a concurrent-modification hazard.
    final subs = List.of(_subs);
    _subs.clear();
    for (final s in subs) {
      await s.cancel();
    }
    final session = _session;
    _session = null;
    negotiatedMtu = null;
    if (session != null) {
      try {
        await session.close();
      } catch (_) {/* already gone */}
    }
  }

  // --- Commands -----------------------------------------------------------

  Future<void> _writeControl(int op) async {
    final session = _session;
    if (session == null) throw StateError('Not connected');
    await session.write(GattIds.swingService, GattIds.controlChar, [op]);
  }

  @override
  Future<void> calibrateAddress() async {
    _setStatus(SensorStatus.calibrating);
    try {
      await _writeControl(ControlOp.calibrateAddress);
      await Future<void>.delayed(calibrateSettle);
      _setStatus(SensorStatus.connected);
    } catch (e) {
      _setStatus(
          _session == null ? SensorStatus.disconnected : SensorStatus.connected);
      rethrow;
    }
  }

  @override
  Future<void> arm() async {
    await _writeControl(ControlOp.arm);
    _setStatus(SensorStatus.armed);
  }

  @override
  Future<void> disconnect() async {
    _userDisconnected = true;
    _reconnectTimer?.cancel();
    await _teardownSession();
    _setStatus(SensorStatus.disconnected);
  }

  @override
  void dispose() {
    _disposed = true;
    _userDisconnected = true;
    _reconnectTimer?.cancel();
    _teardownSession();
    _statusCtrl.close();
    _swingCtrl.close();
    _instantCtrl.close();
    _batteryCtrl.close();
  }
}
