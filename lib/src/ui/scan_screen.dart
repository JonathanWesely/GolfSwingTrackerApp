import 'dart:async';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../sensor/ble_sensor_link.dart';
import '../sensor/ble_transport.dart';

/// Scans for real GolfTracker sensors and adds the tapped one.
///
/// All devices advertise the same name ('GolfTracker'), so the list keys on
/// BLE identity (remoteId) — that's also how multi-sensor setups tell the
/// devices apart. Already-added sensors show as such and can't be re-added.
class ScanScreen extends StatefulWidget {
  final AppState state;

  /// Overridable in tests; defaults to the app-wide transport factory.
  final BleTransport? transport;

  const ScanScreen({super.key, required this.state, this.transport});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final Map<String, BleScanHit> _hits = {};
  StreamSubscription<BleScanHit>? _sub;
  bool _scanning = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _startScan();
  }

  void _startScan() {
    _sub?.cancel();
    setState(() {
      _hits.clear();
      _error = null;
      _scanning = true;
    });
    final transport = widget.transport ?? widget.state.bleTransportFactory();
    _sub = transport
        .scan(
            name: BleSensorLink.advertisedName,
            serviceUuid: BleSensorLink.advertisedService)
        .listen(
          (hit) => setState(() => _hits[hit.remoteId] = hit),
          onError: (Object e) => setState(() {
            _error = '$e';
            _scanning = false;
          }),
          onDone: () {
            if (mounted) setState(() => _scanning = false);
          },
        );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hits = _hits.values.toList()
      ..sort((a, b) => b.rssi.compareTo(a.rssi));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan for sensors'),
        actions: [
          if (_scanning)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Rescan',
              onPressed: _startScan,
            ),
        ],
      ),
      body: Column(
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Scan failed: $_error\n\nCheck that Bluetooth is on and the '
                'app has the required permissions.',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          Expanded(
            child: hits.isEmpty
                ? Center(
                    child: Text(
                      _scanning
                          ? 'Scanning for "${BleSensorLink.advertisedName}"…\n\n'
                              'Power the sensor and keep it nearby.'
                          : 'No sensors found.\n\nSensors appear here once '
                              'Phase 1 firmware is flashed and advertising.',
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.builder(
                    itemCount: hits.length,
                    itemBuilder: (context, i) {
                      final hit = hits[i];
                      final added = widget.state.hasSensor(hit.remoteId);
                      return ListTile(
                        leading: const Icon(Icons.sensors),
                        title: Text(hit.name),
                        subtitle:
                            Text('${hit.remoteId} · ${hit.rssi} dBm'),
                        trailing: added
                            ? const Text('Added')
                            : const Icon(Icons.add_circle_outline),
                        enabled: !added,
                        onTap: added
                            ? null
                            : () {
                                widget.state.addBleSensor(
                                    remoteId: hit.remoteId);
                                Navigator.pop(context);
                              },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
