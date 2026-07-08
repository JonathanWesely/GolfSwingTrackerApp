import 'package:flutter/material.dart';

import 'src/app_state.dart';
import 'src/ui/home_screen.dart';

void main() {
  // Starts with one simulated sensor. Add more (simulated or real BLE)
  // from the + button — each sensor gets a user-assigned name and club.
  // When hardware arrives: + -> "Scan for GolfTracker sensor".
  final state = AppState(startWithMock: true);

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
