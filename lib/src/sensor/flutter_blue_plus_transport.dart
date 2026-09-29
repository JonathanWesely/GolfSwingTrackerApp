import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'ble_transport.dart';

/// Production [BleTransport] backed by flutter_blue_plus.
///
/// This is deliberately the ONLY file in the app that imports
/// flutter_blue_plus — everything above it (BleSensorLink, UI, tests)
/// talks to the [BleTransport] abstraction instead.
class FlutterBluePlusTransport implements BleTransport {
  @override
  Stream<BleScanHit> scan({
    required String name,
    String? serviceUuid,
    Duration timeout = const Duration(seconds: 15),
  }) {
    final ctrl = StreamController<BleScanHit>();
    final Guid? service = serviceUuid == null ? null : Guid(serviceUuid);
    StreamSubscription<List<ScanResult>>? resultsSub;
    StreamSubscription<bool>? scanningSub;

    Future<void> stop() async {
      await resultsSub?.cancel();
      await scanningSub?.cancel();
      try {
        await FlutterBluePlus.stopScan();
      } catch (_) {/* radio already off / never started */}
    }

    ctrl.onListen = () async {
      resultsSub = FlutterBluePlus.scanResults.listen((results) {
        for (final r in results) {
          final advName = r.advertisementData.advName.isNotEmpty
              ? r.advertisementData.advName
              : r.device.platformName;
          // Unfiltered scan (see startScan below), so match here on
          // EITHER the advertised service id OR the name — whichever of
          // the two the platform managed to hear for this report.
          final byService = service != null &&
              r.advertisementData.serviceUuids.contains(service);
          if ((byService || advName == name) && !ctrl.isClosed) {
            ctrl.add(BleScanHit(
              remoteId: r.device.remoteId.str,
              name: advName.isNotEmpty ? advName : name,
              rssi: r.rssi,
            ));
          }
        }
      }, onError: (Object e, StackTrace st) {
        if (!ctrl.isClosed) ctrl.addError(e, st);
      });

      // Close our stream when the platform reports the scan has ended.
      // isScanning REPLAYS its latest value (false) to every new
      // listener, so only treat false as "ended" after we have seen the
      // scan actually running — otherwise the stream closes the instant
      // it opens and every scan comes back empty in ~0 s (the root cause
      // of 2026-09-30's "no sensors found", through three matcher
      // rewrites that never got to run).
      var sawScanning = false;
      scanningSub = FlutterBluePlus.isScanning.listen((scanning) {
        if (scanning) {
          sawScanning = true;
        } else if (sawScanning && !ctrl.isClosed) {
          ctrl.close();
        }
      });

      try {
        // NO platform filters — scan wide open, exactly like a generic
        // scanner app, and filter in Dart above. Native filtering burned
        // us twice on iOS (2026-09-30): name-filtered scans miss reports
        // that arrive without the name, and service-filtered scans
        // delivered nothing at all for this sensor. continuousUpdates
        // keeps reports coming so a late scan-response (which carries
        // the name) still produces a match.
        await FlutterBluePlus.startScan(
          continuousUpdates: true,
          timeout: timeout,
        );
      } catch (e, st) {
        if (!ctrl.isClosed) {
          ctrl.addError(e, st);
          await ctrl.close();
        }
      }
    };
    ctrl.onCancel = stop;
    return ctrl.stream;
  }

  @override
  Future<BleDeviceSession> connect(
    String remoteId, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final device = BluetoothDevice.fromId(remoteId);
    await device.connect(timeout: timeout);
    final services = await device.discoverServices();
    return _FbpSession(device, services);
  }
}

class _FbpSession implements BleDeviceSession {
  final BluetoothDevice _device;
  final List<BluetoothService> _services;

  _FbpSession(this._device, this._services);

  @override
  String get remoteId => _device.remoteId.str;

  BluetoothCharacteristic _char(String serviceUuid, String charUuid) {
    for (final s in _services) {
      if (s.uuid.str128.toLowerCase() != serviceUuid.toLowerCase()) continue;
      for (final c in s.characteristics) {
        if (c.uuid.str128.toLowerCase() == charUuid.toLowerCase()) return c;
      }
    }
    throw StateError('Characteristic $charUuid not found on $remoteId — '
        'is the Phase 1 firmware flashed?');
  }

  @override
  Future<int> requestMtu(int desired) async {
    try {
      return await _device.requestMtu(desired); // Android
    } catch (_) {
      return _device.mtuNow; // iOS auto-negotiates; requestMtu throws
    }
  }

  @override
  Stream<Uint8List> subscribe(String serviceUuid, String charUuid) {
    final c = _char(serviceUuid, charUuid);
    final ctrl = StreamController<Uint8List>();
    StreamSubscription<List<int>>? sub;
    ctrl.onListen = () async {
      sub = c.onValueReceived
          .listen((v) => ctrl.add(Uint8List.fromList(v)), onError: (Object e) {
        if (!ctrl.isClosed) ctrl.addError(e);
      });
      _device.cancelWhenDisconnected(sub!);
      await c.setNotifyValue(true);
    };
    ctrl.onCancel = () => sub?.cancel();
    return ctrl.stream;
  }

  @override
  Future<Uint8List> read(String serviceUuid, String charUuid) async {
    final v = await _char(serviceUuid, charUuid).read();
    return Uint8List.fromList(v);
  }

  @override
  Future<void> write(
      String serviceUuid, String charUuid, List<int> data) async {
    await _char(serviceUuid, charUuid).write(data);
  }

  @override
  Stream<void> get disconnected => _device.connectionState
      .where((s) => s == BluetoothConnectionState.disconnected)
      .map((_) {});

  @override
  Future<void> close() => _device.disconnect();
}
