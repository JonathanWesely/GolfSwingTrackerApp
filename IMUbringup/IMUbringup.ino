#include "Nicla_System.h"
#include "Arduino_BHY2.h"
#include <Adafruit_ICM20649.h>

SensorQuaternion rotation(SENSOR_ID_GAMERV);  // BHI260 Game Rotation Vector
SensorXYZ        linacc(SENSOR_ID_LACC);      // BHI260 Linear Acceleration
Adafruit_ICM20649 icm;

void setup() {
  Serial.begin(115200);
  while (!Serial) {}

  nicla::begin();

  BHY2.begin();                 // onboard sensors, standalone
  rotation.begin();
  linacc.begin();

  // <-- set &Wire1 or &Wire and 0x68/0x69 to match the scanner result
  if (!icm.begin_I2C(0x68, &Wire)) {
    Serial.println("ICM-20649 NOT found — check bus/address/wiring");
    while (1) delay(10);
  }
  icm.setGyroRange(ICM20649_GYRO_RANGE_4000_DPS);   // +/-4000 dps
  icm.setAccelRange(ICM20649_ACCEL_RANGE_30_G);     // +/-30 g
  Serial.println("Both IMUs initialized.");
}

void loop() {
  BHY2.update();

  sensors_event_t a, g, t;
  icm.getEvent(&a, &g, &t);

  Serial.print("BHI quat w:"); Serial.print(rotation.w());
  Serial.print(" x:");         Serial.print(rotation.x());
  Serial.print("  |  ICM gyroZ:"); Serial.print(g.gyro.z);
  Serial.print(" accX:");          Serial.println(a.acceleration.x);

  delay(100);
}