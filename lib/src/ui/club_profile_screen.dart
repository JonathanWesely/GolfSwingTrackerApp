import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models/club_profile.dart';

/// Edits club shaft-length constants. Which club a given SENSOR uses is
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
                  'Shaft length scales grip rotation into clubhead speed '
                  '(v = ω × r). Adjust to match your actual clubs. '
                  'Assign a club to each sensor from the home screen.'),
            ),
            for (final club in state.clubs)
              ListTile(
                leading: const Icon(Icons.golf_course),
                title: Text(club.name),
                subtitle: Text(
                    '${club.shaftLengthM.toStringAsFixed(3)} m '
                    '(${(club.shaftLengthM / 0.0254).toStringAsFixed(1)}")'),
                trailing: const Icon(Icons.edit),
                onTap: () => _editLength(context, club),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _editLength(BuildContext context, ClubProfile club) async {
    final controller =
        TextEditingController(text: club.shaftLengthM.toStringAsFixed(3));
    final result = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${club.name} shaft length'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(suffixText: 'm'),
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, double.tryParse(controller.text)),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result != null && result > 0.3 && result < 1.5) {
      state.updateClub(club.copyWith(shaftLengthM: result));
    }
  }
}
