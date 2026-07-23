#include "Nicla_System.h"

void setup() {
  Serial.begin(115200);
  while (!Serial) {}
  nicla::begin();
  nicla::enableCharging(100);   // 100 mA (~0.4C, safe for a 250mAh cell; valid 40–300mA)
  nicla::configureChargingSafetyTimer(ChargingSafetyTimerOption::NineHours);
}

void loop() {
  OperatingStatus s = nicla::getOperatingStatus();
  Serial.print("Status: ");
  if      (s == OperatingStatus::Charging)         Serial.print("Charging");
  else if (s == OperatingStatus::ChargingComplete) Serial.print("Complete");
  else if (s == OperatingStatus::Ready)            Serial.print("Ready");
  else                                             Serial.print("Error");

  Serial.print("  |  Battery: ");
  Serial.print(nicla::getCurrentBatteryVoltage());
  Serial.print(" V  |  on battery? ");
  Serial.println(nicla::runsOnBattery());
  delay(5000);
}
