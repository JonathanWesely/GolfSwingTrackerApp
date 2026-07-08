import 'package:flutter_test/flutter_test.dart';
import 'package:golf_tracker_app/main.dart';
import 'package:golf_tracker_app/src/app_state.dart';

import 'fake_ble_transport.dart';

void main() {
  testWidgets('app boots, auto-connects the default simulated sensor, '
      'and shows the home screen', (tester) async {
    final state = AppState(
        startWithMock: true, bleTransportFactory: FakeTransport.new);
    await tester.pumpWidget(GolfTrackerApp(state: state));

    expect(find.text('Golf Swing Tracker'), findsOneWidget);
    expect(find.textContaining('Sensor 1'), findsOneWidget);

    // Hands-free: connect (600 ms) then auto-arm with zero taps.
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.text('armed  ·  '), findsOneWidget);

    state.dispose();
  });
}
