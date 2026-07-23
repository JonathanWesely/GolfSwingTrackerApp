import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models/club_profile.dart';

/// Edits club profiles. The sensor-to-clubface distance is the effective
/// radius the physics uses (v = ω × r) now that the sensor clamps to the
/// shaft rather than the grip butt-end. Which club a given SENSOR uses is
/// assigned per-sensor on the home screen (multi-device support).
class ClubProfileScreen extends StatelessWidget {
  final AppState state;
  const ClubProfileScreen({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: const Text('Club profiles')),
        body: ListView(
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                  'The sensor-to-clubface distance is the effective radius '
                  'that scales grip rotation into clubhead speed (v = ω × r) '
                  'and reconstructs the clubhead path. Measure it along the '
                  'shaft from the mounted sensor — with the clamp slid up '
                  'against the bottom of the grip (its repeatable position) — '
                  'to the face. Assign a club to '
                  'each sensor from the home screen.'),
            ),
            for (final club in state.clubs)
              ListTile(
                leading: const Icon(Icons.golf_course),
                title: Text(club.name),
                subtitle: Text(
                    'Sensor→face: ${club.deviceToFaceDistanceM.toStringAsFixed(3)} m '
                    '(${(club.deviceToFaceDistanceM / 0.0254).toStringAsFixed(1)}")'
                    '  ·  Shaft: ${club.shaftLengthM.toStringAsFixed(3)} m'),
                trailing: const Icon(Icons.edit),
                onTap: () => _edit(context, club),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _edit(BuildContext context, ClubProfile club) async {
    final distanceCtrl = TextEditingController(
        text: club.deviceToFaceDistanceM.toStringAsFixed(3));
    final shaftCtrl =
        TextEditingController(text: club.shaftLengthM.toStringAsFixed(3));
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(club.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: distanceCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Sensor-to-clubface distance (m)',
                helperText: 'Clamp seated against the grip → measured to the face',
                suffixText: 'm',
              ),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: shaftCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Total club length (m)',
                suffixText: 'm',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (saved != true) return;
    final distance = double.tryParse(distanceCtrl.text);
    final shaft = double.tryParse(shaftCtrl.text);
    var updated = club;
    if (distance != null && distance > 0.3 && distance < 1.5) {
      updated = updated.copyWith(deviceToFaceDistanceM: distance);
    }
    if (shaft != null && shaft > 0.3 && shaft < 1.5) {
      updated = updated.copyWith(shaftLengthM: shaft);
    }
    if (updated != club) state.updateClub(updated);
  }
}
