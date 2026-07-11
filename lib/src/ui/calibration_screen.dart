import 'package:flutter/material.dart';

import '../app_state.dart';
import '../calibration/calibration_engine.dart';
import '../calibration/r10_csv_importer.dart';

/// Calibrate the sensor's speed, face, and club path against a Garmin R10.
///
/// Two ways to build the paired dataset:
///  - **Manual**: take a swing, read the three numbers off the R10, type them
///    in, tap "Add sample".
///  - **CSV**: paste a Garmin R10 session export; it pairs each row with this
///    session's swings, in order.
///
/// Then "Compute" fits the constants and "Apply" writes them (per-club
/// effective radius for speed; a face/path correction for the rest).
///
/// Calibrate from a clean state — tap "Reset" first so the sensor readings
/// are uncalibrated while you gather samples, otherwise the fit is applied on
/// top of an existing correction.
class CalibrationScreen extends StatefulWidget {
  final AppState state;
  const CalibrationScreen({super.key, required this.state});

  @override
  State<CalibrationScreen> createState() => _CalibrationScreenState();
}

class _CalibrationScreenState extends State<CalibrationScreen> {
  final List<CalibrationSample> _samples = [];
  final _speedCtrl = TextEditingController();
  final _faceCtrl = TextEditingController();
  final _pathCtrl = TextEditingController();
  CalibrationResult? _result;

  @override
  void dispose() {
    _speedCtrl.dispose();
    _faceCtrl.dispose();
    _pathCtrl.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _addManualSample() {
    final swing = widget.state.latestSwing;
    if (swing == null) return;
    final refSpeed = double.tryParse(_speedCtrl.text.trim());
    final refFace = double.tryParse(_faceCtrl.text.trim());
    final refPath = double.tryParse(_pathCtrl.text.trim());
    if (refSpeed == null || refFace == null || refPath == null) {
      _snack('Enter valid R10 speed, face, and path numbers.');
      return;
    }
    setState(() {
      _samples.add(CalibrationSample(
        clubId: swing.clubId,
        sensorSpeedMph: swing.clubSpeedMph,
        sensorFaceDeg: swing.faceAngleDeg,
        sensorPathDeg: swing.clubPathDeg,
        refSpeedMph: refSpeed,
        refFaceDeg: refFace,
        refPathDeg: refPath,
      ));
      _result = null;
      _speedCtrl.clear();
      _faceCtrl.clear();
      _pathCtrl.clear();
    });
  }

  Future<void> _importCsv() async {
    final controller = TextEditingController();
    final csv = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Paste R10 session CSV'),
        content: TextField(
          controller: controller,
          maxLines: 10,
          decoration: const InputDecoration(
            hintText: 'Paste the exported CSV here…',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Import')),
        ],
      ),
    );
    if (csv == null || csv.trim().isEmpty) return;
    try {
      final shots = R10CsvImporter.parse(csv);
      // Session swings oldest-first (repository.all is newest-first).
      final swings = widget.state.repository.all.reversed.toList();
      final paired = R10CsvImporter.pairByOrder(swings, shots);
      setState(() {
        _samples
          ..clear()
          ..addAll(paired);
        _result = null;
      });
      _snack('Imported ${shots.length} R10 shots; paired ${paired.length} '
          'with this session\'s swings.');
    } on FormatException catch (e) {
      _snack(e.message);
    }
  }

  void _compute() {
    if (_samples.isEmpty) return;
    setState(() => _result = CalibrationEngine.fit(_samples));
  }

  void _apply() {
    final r = _result;
    if (r == null) return;
    widget.state.applyCalibration(r);
    _snack('Calibration applied.');
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.state,
      builder: (context, _) {
        final cal = widget.state.calibration;
        final swing = widget.state.latestSwing;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Calibration'),
            actions: [
              TextButton(
                onPressed: () {
                  widget.state.resetCalibration();
                  setState(() {
                    _samples.clear();
                    _result = null;
                  });
                },
                child: const Text('Reset'),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                color: cal.isIdentity
                    ? null
                    : Theme.of(context).colorScheme.secondaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Current calibration',
                          style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 4),
                      Text(cal.isIdentity
                          ? 'Uncalibrated (raw sensor values). Gather your R10 '
                              'reference swings from here.'
                          : 'Face ×${cal.faceScale.toStringAsFixed(2)} '
                              '${cal.faceOffset >= 0 ? '+' : ''}${cal.faceOffset.toStringAsFixed(2)}°   ·   '
                              'Path ×${cal.pathScale.toStringAsFixed(2)} '
                              '${cal.pathOffset >= 0 ? '+' : ''}${cal.pathOffset.toStringAsFixed(2)}°'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text('1 · Gather paired swings',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (swing == null)
                        const Text('Take a swing to see the sensor reading '
                            'here, then enter the R10 numbers for it.')
                      else ...[
                        Text('Latest sensor swing',
                            style: Theme.of(context).textTheme.bodySmall),
                        const SizedBox(height: 4),
                        Text(
                          '${swing.clubSpeedMph.toStringAsFixed(1)} mph · '
                          'face ${swing.faceAngleDeg.toStringAsFixed(1)}° · '
                          'path ${swing.clubPathDeg.toStringAsFixed(1)}°',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(child: _numField(_speedCtrl, 'R10 speed')),
                          const SizedBox(width: 8),
                          Expanded(child: _numField(_faceCtrl, 'R10 face')),
                          const SizedBox(width: 8),
                          Expanded(child: _numField(_pathCtrl, 'R10 path')),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.icon(
                            onPressed: swing == null ? null : _addManualSample,
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Add sample'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _importCsv,
                            icon: const Icon(Icons.upload_file, size: 18),
                            label: const Text('Import CSV'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                  '${_samples.length} sample${_samples.length == 1 ? '' : 's'} '
                  'collected',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              for (final s in _samples.reversed.take(8))
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.compare_arrows, size: 18),
                  title: Text(
                    '${s.clubId} · '
                    'spd ${s.sensorSpeedMph.toStringAsFixed(0)}→${s.refSpeedMph.toStringAsFixed(0)}  '
                    'face ${s.sensorFaceDeg.toStringAsFixed(1)}→${s.refFaceDeg.toStringAsFixed(1)}  '
                    'path ${s.sensorPathDeg.toStringAsFixed(1)}→${s.refPathDeg.toStringAsFixed(1)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _samples.length >= 3 ? _compute : null,
                child: Text(_samples.length >= 3
                    ? '2 · Compute calibration'
                    : 'Add at least 3 samples to compute'),
              ),
              if (_result != null) ...[
                const SizedBox(height: 16),
                _ResultCard(result: _result!, onApply: _apply),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _numField(TextEditingController c, String label) => TextField(
        controller: c,
        keyboardType:
            const TextInputType.numberWithOptions(decimal: true, signed: true),
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
      );
}

class _ResultCard extends StatelessWidget {
  final CalibrationResult result;
  final VoidCallback onApply;
  const _ResultCard({required this.result, required this.onApply});

  @override
  Widget build(BuildContext context) {
    final cal = result.calibration;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Fitted calibration (${result.sampleCount} samples)',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            for (final e in result.speedScaleByClub.entries)
              Text('Speed · ${e.key}: effective radius ×'
                  '${e.value.toStringAsFixed(3)}'),
            Text('Face offset: ${cal.faceOffset >= 0 ? '+' : ''}'
                '${cal.faceOffset.toStringAsFixed(2)}°  '
                '(RMS ${result.faceResidualRmsDeg.toStringAsFixed(2)}°)'),
            Text('Path: ×${cal.pathScale.toStringAsFixed(3)} '
                '${cal.pathOffset >= 0 ? '+' : ''}'
                '${cal.pathOffset.toStringAsFixed(2)}°  '
                '(RMS ${result.pathResidualRmsDeg.toStringAsFixed(2)}°)'),
            if (!result.pathSlopeReliable)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Path: sensor values barely varied, so only an offset was '
                  'fit (no slope). Gather swings across a range of paths for a '
                  'full fit — expected when calibrating against the simulator.',
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.tertiary),
                ),
              ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onApply,
              icon: const Icon(Icons.check, size: 18),
              label: const Text('Apply calibration'),
            ),
          ],
        ),
      ),
    );
  }
}
