import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'src/app_state.dart';
import 'src/storage/swing_database.dart';
import 'src/ui/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Swings, club profiles, and the sensor registry persist here.
  final db = await SwingDatabase.open(
    factory: databaseFactory,
    path: p.join(await getDatabasesPath(), 'golf_tracker.db'),
  );

  // First launch starts with one simulated sensor; add more (simulated or
  // real hardware) from the + button — real sensors via "Scan for
  // GolfTracker sensor" once Phase 1 firmware is flashed. Everything you
  // add, rename, and record is restored on the next launch.
  final state = await AppState.restore(db: db);

  runApp(GolfTrackerApp(state: state));
}

class GolfTrackerApp extends StatelessWidget {
  final AppState state;
  const GolfTrackerApp({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Golf Swing Tracker',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.teal, brightness: Brightness.dark),
        useMaterial3: true,
      ),
      home: HomeScreen(state: state),
    );
  }
}
