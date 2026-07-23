import 'package:flutter/material.dart';

import '../app_state.dart';
import '../sensor/mock_sensor_link.dart';
import '../sensor/sensor_link.dart';
import 'calibration_screen.dart';
import 'club_profile_screen.dart';
import 'scan_screen.dart';
import 'session_screen.dart';
import 'widgets/path_painter.dart';

class HomeScreen extends StatelessWidget {
  final AppState state;
  const HomeScreen({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final swing = state.latestSwing;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Golf Swing Tracker'),
            actions: [
              IconButton(
                icon: const Icon(Icons.add),
                tooltip: 'Add sensor',
                onPressed: () => _addSensor(context),
              ),
              IconButton(
                icon: const Icon(Icons.history),
                tooltip: 'Swing history',
                onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => SessionScreen(state: state))),
              ),
              IconButton(
                icon: const Icon(Icons.golf_course),
                tooltip: 'Club profiles',
                onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => ClubProfileScreen(state: state))),
              ),
              IconButton(
                icon: const Icon(Icons.tune),
                tooltip: 'Calibration (Garmin R10)',
                onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => CalibrationScreen(state: state))),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final sensor in state.sensors) ...[
                _SensorCard(state: state, sensor: sensor),
                const SizedBox(height: 12),
              ],
              if (state.sensors.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(
                        child: Text('No sensors. Tap + to add one.')),
                  ),
                ),
              const SizedBox(height: 4),
              if (state.pendingInstant != null) ...[
                _InstantMetricsCard(instant: state.pendingInstant!),
                const SizedBox(height: 12),
              ],
              if (swing != null) ...[
                _LatestSwingCard(state: state),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Swing path',
                            style: Theme.of(context).textTheme.titleSmall),
                        const SizedBox(height: 8),
                        SwingPathGauge(deviationDeg: swing.clubPathDeg),
                      ],
                    ),
                  ),
                ),
              ] else
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(28),
                    child: Center(
                        child: Text(
                            'No swings yet.\nConnect a sensor, calibrate at address, arm, then swing.',
                            textAlign: TextAlign.center)),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _addSensor(BuildContext context) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.bluetooth_searching),
              title: const Text('Scan for GolfTracker sensor'),
              subtitle: const Text('Real hardware over BLE'),
              onTap: () => Navigator.pop(context, 'ble'),
            ),
            ListTile(
              leading: const Icon(Icons.smart_toy_outlined),
              title: const Text('Add simulated sensor'),
              subtitle: const Text('No hardware needed'),
              onTap: () => Navigator.pop(context, 'mock'),
            ),
          ],
        ),
      ),
    );
    if (choice == 'mock') state.addMockSensor();
    if (choice == 'ble' && context.mounted) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ScanScreen(state: state)),
      );
    }
  }
}

/// Flashes up the moment a sensor reports impact — the same numbers the
/// AR HUD will show <500 ms after contact, while the full capture burst
/// is still transferring.
class _InstantMetricsCard extends StatelessWidget {
  final PendingInstant instant;
  const _InstantMetricsCard({required this.instant});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.bolt, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${instant.clubSpeedMph.toStringAsFixed(1)} mph · '
                '${instant.faceAngleDeg >= 0 ? '+' : ''}'
                '${instant.faceAngleDeg.toStringAsFixed(1)}°  '
                '(instant — full capture incoming)',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
        ),
      ),
    );
  }
}

class _SensorCard extends StatelessWidget {
  final AppState state;
  final ConnectedSensor sensor;
  const _SensorCard({required this.state, required this.sensor});

  @override
  Widget build(BuildContext context) {
    final status = sensor.status;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.circle,
                    size: 12,
                    color: switch (status) {
                      SensorStatus.disconnected => Colors.red,
                      SensorStatus.connecting => Colors.orange,
                      SensorStatus.calibrating => Colors.orange,
                      SensorStatus.connected => Colors.green,
                      SensorStatus.armed => Colors.tealAccent,
                    }),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${sensor.label}${sensor.isMock ? '  (simulated)' : ''}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (sensor.battery != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Text('${(sensor.battery! * 100).round()}%',
                        style: Theme.of(context).textTheme.bodySmall),
                  ),
                PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'rename') _rename(context);
                    if (v == 'remove') state.removeSensor(sensor);
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'rename', child: Text('Rename')),
                    PopupMenuItem(value: 'remove', child: Text('Remove')),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text('${status.name}  ·  ',
                    style: Theme.of(context).textTheme.bodySmall),
                DropdownButton<String>(
                  value: sensor.club.id,
                  isDense: true,
                  underline: const SizedBox.shrink(),
                  items: [
                    for (final c in state.clubs)
                      DropdownMenuItem(value: c.id, child: Text(c.name)),
                  ],
                  onChanged: (id) {
                    final club =
                        state.clubs.where((c) => c.id == id).firstOrNull;
                    if (club != null) state.assignClub(sensor, club);
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (status == SensorStatus.disconnected)
                  FilledButton.icon(
                    onPressed: sensor.link.connect,
                    icon: const Icon(Icons.bluetooth, size: 18),
                    label: const Text('Connect'),
                  ),
                if (status == SensorStatus.connected ||
                    status == SensorStatus.armed) ...[
                  OutlinedButton(
                    onPressed: sensor.link.calibrateAddress,
                    child: const Text('Calibrate'),
                  ),
                  if (status == SensorStatus.connected)
                    FilledButton(
                      onPressed: sensor.link.arm,
                      child: const Text('Arm'),
                    ),
                  if (sensor.isMock && status == SensorStatus.armed)
                    FilledButton.tonal(
                      onPressed: () =>
                          (sensor.link as MockSensorLink).simulateSwing(
                        radiusM: sensor.club.deviceToFaceDistanceM,
                      ),
                      child: const Text('Simulate swing'),
                    ),
                ],
                if (sensor.isMock)
                  FilterChip(
                    label: const Text('Auto swings'),
                    selected: (sensor.link as MockSensorLink).autoSwinging,
                    onSelected: (on) => state.toggleAutoSwings(sensor, on),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _rename(BuildContext context) async {
    final controller = TextEditingController(text: sensor.label);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sensor name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
              hintText: 'Player or club name, e.g. "Jonathan" or "Driver"'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name != null) state.renameSensor(sensor, name);
  }
}

class _LatestSwingCard extends StatelessWidget {
  final AppState state;
  const _LatestSwingCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final s = state.latestSwing!;
    final club =
        state.clubs.where((c) => c.id == s.clubId).firstOrNull?.name ?? '';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (s.deviceLabel.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('${s.deviceLabel} · $club',
                    style: Theme.of(context).textTheme.bodySmall),
              ),
            if (s.hasQualityFlags)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        size: 16,
                        color: Theme.of(context).colorScheme.tertiary),
                    const SizedBox(width: 4),
                    Text(
                      s.isFallbackCapture
                          ? 'BHY2 fallback capture — check ICM wiring'
                          : s.speedExtrapolated
                              ? 'Gyro clipped — speed extrapolated'
                              : 'Quality checks failed on primary IMU',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(
                              color: Theme.of(context).colorScheme.tertiary),
                    ),
                  ],
                ),
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Column(
                  children: [
                    Text(s.clubSpeedMph.toStringAsFixed(1),
                        style: Theme.of(context)
                            .textTheme
                            .displaySmall
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    const Text('mph club speed'),
                  ],
                ),
                Column(
                  children: [
                    Text(
                        '${s.faceAngleDeg >= 0 ? '+' : ''}${s.faceAngleDeg.toStringAsFixed(1)}°',
                        style: Theme.of(context)
                            .textTheme
                            .displaySmall
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    Text('face ${s.faceLabel.toLowerCase()}'),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
