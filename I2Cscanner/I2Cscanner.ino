#include <Wire.h>

void scan(TwoWire &bus, const char *name) {
  Serial.print("Scanning "); Serial.println(name);
  bus.begin();
  for (uint8_t a = 1; a < 127; a++) {
    bus.beginTransmission(a);
    if (bus.endTransmission() == 0) {
      Serial.print("  device at 0x");
      Serial.println(a, HEX);
    }
  }
}

void setup() {
  Serial.begin(115200);
  while (!Serial) {}
  scan(Wire, "Wire");
  scan(Wire1, "Wire1");
}

void loop() {}