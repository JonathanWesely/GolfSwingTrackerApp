// BLEbringup — minimal ArduinoBLE health check for the Nicla Sense ME.
//
// Purpose (2026-09-30): firmware.ino kept dying at BLE.begin() with
// "Assertion failed: _stack_buffer != NULL" (NRFCordioHCIDriver.cpp —
// the core's Cordio BLE driver failing to allocate its buffer). This
// sketch uses almost no RAM, so it splits the world in two:
//
//   * It ALSO crashes  -> the board core's BLE half is broken; no sketch
//     will ever advertise. Fix versions in Boards Manager (core
//     "Arduino Mbed OS Nicla Boards") — don't touch firmware.ino.
//   * It advertises    -> the core is fine; the problem is inside the
//     big firmware and gets bisected there.
//
// Expected serial output:
//   BLE bringup: calling BLE.begin()...
//   advertising as NiclaBLEtest
// then the board shows up as "NiclaBLEtest" in any BLE scanner app.

#include <ArduinoBLE.h>

void setup() {
  Serial.begin(115200);
  delay(2500); // give the serial monitor a moment to attach

  Serial.println("BLE bringup: calling BLE.begin()...");
  if (!BLE.begin()) {
    Serial.println("BLE.begin() returned false");
    while (1) delay(1000);
  }
  BLE.setLocalName("NiclaBLEtest");
  BLE.setDeviceName("NiclaBLEtest");
  BLE.advertise();
  Serial.println("advertising as NiclaBLEtest");
}

void loop() {
  BLE.poll();
  delay(10);
}
