import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../models/swing_metrics.dart';
import 'swing_detail_screen.dart';

class SessionScreen extends StatefulWidget {
  final AppState state;
  const SessionScreen({super.key, required this.state});

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {
  /// null = all devices; otherwise a deviceLabel to filter on.
  String? _deviceFilter;

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final labels = state.repository.deviceLabels;
        final all = state.repository.all;
        final swings = _deviceFilter == null
            ? all
            : all.where((s) => s.deviceLabel == _deviceFilter).toList();

        return Scaffold(
          appBar: AppBar(
            title: const Text('Session history'),
            actions: [
              IconButton(
                icon: const Icon(Icons.copy_all),
                tooltip: 'Copy session JSON',
                onPressed: all.isEmpty
                    ? null
                    : () async {
                        await Clipboard.setData(ClipboardData(
                            text: state.repository.exportJson()));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content:
                                      Text('Session JSON copied to clipboard')));
                        }
                      },
              ),
            ],
          ),
          body: Column(
            children: [
              if (labels.length > 1)
                SizedBox(
                  height: 52,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          label: const Text('All'),
                          selected: _deviceFilter == null,
                          onSelected: (_) =>
                              setState(() => _deviceFilter = null),
                        ),
                      ),
                      for (final label in labels)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: FilterChip(
                            label: Text(label),
                            selected: _deviceFilter == label,
                            onSelected: (_) =>
                                setState(() => _deviceFilter = label),
                          ),
                        ),
                    ],
                  ),
                ),
              _StatsRow(swings: swings),
              const Divider(height: 1),
              Expanded(
                child: swings.isEmpty
                    ? const Center(
                        child: Text('No swings recorded this session.'))
                    : ListView.builder(
                        itemCount: swings.length,
                        itemBuilder: (context, i) {
                          final s = swings[i];
                          final club = state.clubs
                                  .where((c) => c.id == s.clubId)
                                  .firstOrNull
                                  ?.name ??
                              s.clubId;
                          final source = s.deviceLabel.isEmpty
                              ? club
                              : '${s.deviceLabel} · $club';
                          return ListTile(
                            leading: const Icon(Icons.sports_golf),
                            title: Text(
                                '${s.clubSpeedMph.toStringAsFixed(1)} mph · '
                                '${s.faceAngleDeg >= 0 ? '+' : ''}${s.faceAngleDeg.toStringAsFixed(1)}° ${s.faceLabel.toLowerCase()}'),
                            subtitle: Text(
                                '$source · ${TimeOfDay.fromDateTime(s.timestamp).format(context)}'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => SwingDetailScreen(
                                        swing: s, clubName: club))),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StatsRow extends StatelessWidget {
  final List<SwingMetrics> swings;
  const _StatsRow({required this.swings});

  @override
  Widget build(BuildContext context) {
    double? avg, best;
    if (swings.isNotEmpty) {
      final speeds = swings.map((s) => s.clubSpeedMph);
      best = speeds.reduce((a, b) => a > b ? a : b);
      avg = speeds.reduce((a, b) => a + b) / swings.length;
    }
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _Stat(label: 'Swings', value: '${swings.length}'),
          _Stat(label: 'Avg mph', value: avg?.toStringAsFixed(1) ?? '-'),
          _Stat(label: 'Best mph', value: best?.toStringAsFixed(1) ?? '-'),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text(value,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold)),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      );
}
