// One-time platform setup after `flutter create`. Run from the project root:
//
//   flutter create . --platforms=android,ios --org com.jonwes --project-name golf_tracker_app
//   dart run tool/setup_platforms.dart
//
// What it does (idempotent — safe to run again):
//  1. AndroidManifest.xml: adds the BLE permissions flutter_blue_plus needs
//     (BLUETOOTH_SCAN/CONNECT for Android 12+, legacy set for <= 11).
//  2. ios/Runner/Info.plist: adds NSBluetoothAlwaysUsageDescription.
//  3. Removes the stock test/widget_test.dart counter-app template that
//     `flutter create` drops next to the real test suite.

// ignore_for_file: avoid_print — this is a CLI tool, print IS its output.

import 'dart:io';

const _androidPermissions = '''
    <!-- Bluetooth (flutter_blue_plus): Android 12+ -->
    <uses-permission android:name="android.permission.BLUETOOTH_SCAN"
        android:usesPermissionFlags="neverForLocation" />
    <uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
    <!-- Legacy Bluetooth: Android 11 and below -->
    <uses-permission android:name="android.permission.BLUETOOTH"
        android:maxSdkVersion="30" />
    <uses-permission android:name="android.permission.BLUETOOTH_ADMIN"
        android:maxSdkVersion="30" />
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"
        android:maxSdkVersion="30" />
''';

const _iosBluetoothKeys = '''
	<key>NSBluetoothAlwaysUsageDescription</key>
	<string>Connects to your GolfTracker swing sensor over Bluetooth.</string>
	<key>NSBluetoothPeripheralUsageDescription</key>
	<string>Connects to your GolfTracker swing sensor over Bluetooth.</string>
''';

void main() {
  var changes = 0;
  changes += _patchAndroidManifest() ? 1 : 0;
  changes += _patchInfoPlist() ? 1 : 0;
  changes += _removeTemplateWidgetTest() ? 1 : 0;
  print(changes == 0
      ? 'Nothing to do — platforms already set up.'
      : 'Platform setup complete ($changes change(s)).');
}

bool _patchAndroidManifest() {
  final f = File('android/app/src/main/AndroidManifest.xml');
  if (!f.existsSync()) {
    print('SKIP  android: ${f.path} not found — run flutter create first.');
    return false;
  }
  var xml = f.readAsStringSync();
  if (xml.contains('android.permission.BLUETOOTH_SCAN')) {
    print('OK    android: BLE permissions already present.');
    return false;
  }
  final open = RegExp(r'<manifest\b[^>]*>').firstMatch(xml);
  if (open == null) {
    print('FAIL  android: could not find <manifest> tag in ${f.path}.');
    return false;
  }
  xml = xml.replaceRange(
      open.end, open.end, '\n$_androidPermissions');
  f.writeAsStringSync(xml);
  print('DONE  android: BLE permissions added to AndroidManifest.xml.');
  return true;
}

bool _patchInfoPlist() {
  final f = File('ios/Runner/Info.plist');
  if (!f.existsSync()) {
    print('SKIP  ios: ${f.path} not found — run flutter create first.');
    return false;
  }
  var plist = f.readAsStringSync();
  if (plist.contains('NSBluetoothAlwaysUsageDescription')) {
    print('OK    ios: Bluetooth usage description already present.');
    return false;
  }
  final close = plist.lastIndexOf('</dict>');
  if (close < 0) {
    print('FAIL  ios: could not find closing </dict> in ${f.path}.');
    return false;
  }
  plist = plist.replaceRange(close, close, _iosBluetoothKeys);
  f.writeAsStringSync(plist);
  print('DONE  ios: Bluetooth usage descriptions added to Info.plist.');
  return true;
}

bool _removeTemplateWidgetTest() {
  final f = File('test/widget_test.dart');
  if (!f.existsSync()) return false;
  // Only delete the stock counter-app template, never a real test.
  final content = f.readAsStringSync();
  if (content.contains('MyApp') && content.contains('smoke test')) {
    f.deleteSync();
    print('DONE  test: removed stock widget_test.dart template.');
    return true;
  }
  print('OK    test: widget_test.dart is not the stock template; left as-is.');
  return false;
}
