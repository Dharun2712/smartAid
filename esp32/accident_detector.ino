#include <Wire.h>
#include <WiFi.h>
#include <HTTPClient.h>
#include <math.h>

// ================= MPU =================
#define MPU_ADDR 0x68
#define BUZZER_PIN 25
#define RESET_PIN 27

// ================= LM35 TEMPERATURE SENSOR =================
#define LM35_PIN 34  // Analog pin for LM35 (ADC1_CH6)
#define ADC_RESOLUTION 4095.0  // 12-bit ADC
#define ADC_VREF 3.3  // ESP32 ADC reference voltage
#define LM35_MV_PER_C 10.0  // LM35 outputs 10mV per °C

// ---- THRESHOLDS ----
#define ACC_IMPACT_G     1.8
#define GYRO_IMPACT     40.0
#define CONFIRM_WINDOW  200     // ms
#define BUZZ_TIME       5000    // ms

// ================= WIFI =================
const char* WIFI_SSID = "A";
const char* WIFI_PASS = "0808@123";

// ================= CLOUD =================
const char* SERVER_URL = "http://20.47.72.43:8000/api/accident";
const char* DEVICE_KEY = "smartaid-prototype";

// ================= GPS (STATIC LOCATION) =================
// North = +ve, East = +ve
float currentLatitude  = 11.0542;
float currentLongitude = 78.0485;

// ================= STATE =================
bool impactDetected = false;
bool accidentConfirmed = false;
bool systemLocked = false;
bool wifiSent = false;

unsigned long impactTime = 0;
unsigned long buzzerStartTime = 0;

// ================= DEVICE ID =================
String getDeviceId() {
  uint64_t chipId = ESP.getEfuseMac();
  char id[25];
  sprintf(id, "ESP32-%04X%08X",
          (uint16_t)(chipId >> 32),
          (uint32_t)chipId);
  return String(id);
}

// ================= MPU HELPERS =================
void writeMPU(byte reg, byte data) {
  Wire.beginTransmission(MPU_ADDR);
  Wire.write(reg);
  Wire.write(data);
  Wire.endTransmission();
}

int16_t readMPU16(byte reg) {
  Wire.beginTransmission(MPU_ADDR);
  Wire.write(reg);
  Wire.endTransmission(false);
  Wire.requestFrom(MPU_ADDR, 2);
  return (Wire.read() << 8) | Wire.read();
}

// ================= LM35 TEMPERATURE READING =================
float readTemperature() {
  int adcValue = analogRead(LM35_PIN);
  // Convert ADC value to voltage (mV)
  float voltage_mV = (adcValue / ADC_RESOLUTION) * ADC_VREF * 1000.0;
  // LM35: 10mV per degree Celsius
  float temperature = voltage_mV / LM35_MV_PER_C;
  return temperature;
}

// ================= SEND TO CLOUD =================
void sendAccidentToCloud(float impactForce) {

  if (wifiSent) return;

  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("❌ WiFi not connected");
    return;
  }

  HTTPClient http;
  http.begin(SERVER_URL);
  http.addHeader("Content-Type", "application/json");
  http.addHeader("X-DEVICE-KEY", DEVICE_KEY);

  // Read temperature from LM35 sensor
  float temperature = readTemperature();

  String payload = "{";
  payload += "\"device_id\":\"" + getDeviceId() + "\",";
  payload += "\"event\":\"ACCIDENT\",";
  payload += "\"impact_force\":" + String(impactForce, 2) + ",";
  payload += "\"temperature\":" + String(temperature, 1) + ",";
  payload += "\"latitude\":" + String(currentLatitude, 6) + ",";
  payload += "\"longitude\":" + String(currentLongitude, 6) + ",";
  payload += "\"timestamp\":\"" + String(millis()) + "\"";
  payload += "}";

  Serial.println("📤 Sending JSON:");
  Serial.println(payload);
  Serial.print("🌡️ Temperature: ");
  Serial.print(temperature, 1);
  Serial.println(" °C");

  int httpCode = http.POST(payload);

  Serial.print("☁️ HTTP response: ");
  Serial.println(httpCode);

  if (httpCode == 200 || httpCode == 201) {
    wifiSent = true;
    Serial.println("✅ Accident data sent successfully");
  }

  http.end();
}

// ================= SETUP =================
void setup() {
  Serial.begin(115200);
  delay(2000);

  // MPU INIT
  Wire.begin(21, 22);
  writeMPU(0x6B, 0x00);      // Wake MPU
  writeMPU(0x1C, 0x08);     // Accel ±4g
  writeMPU(0x1B, 0x08);     // Gyro ±500 dps

  // LM35 Temperature Sensor INIT
  pinMode(LM35_PIN, INPUT);
  analogReadResolution(12);  // Set 12-bit resolution for ADC
  Serial.println("🌡️ LM35 Temperature sensor initialized");

  pinMode(BUZZER_PIN, OUTPUT);
  digitalWrite(BUZZER_PIN, LOW);

  pinMode(RESET_PIN, INPUT_PULLUP);

  // WiFi
  WiFi.begin(WIFI_SSID, WIFI_PASS);
  Serial.print("Connecting WiFi");
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
  Serial.println("\n✅ WiFi connected");

  Serial.println("🚗 SMART-AID SYSTEM RUNNING");
}

// ================= LOOP =================
void loop() {

  // ===== LOCK MODE =====
  if (systemLocked) {

    if (!wifiSent) {
      sendAccidentToCloud(ACC_IMPACT_G);
    }

    if (digitalRead(RESET_PIN) == LOW) {
      systemLocked = false;
      accidentConfirmed = false;
      impactDetected = false;
      wifiSent = false;

      Serial.println("🔓 SYSTEM RESET");
      delay(1000);
    }
    return;
  }

  // ===== READ MPU =====
  float ax = readMPU16(0x3B) / 16384.0;
  float ay = readMPU16(0x3D) / 16384.0;
  float az = readMPU16(0x3F) / 16384.0;
  float accelMag = sqrt(ax * ax + ay * ay + az * az);

  float gx = readMPU16(0x43) / 131.0;
  float gy = readMPU16(0x45) / 131.0;
  float gz = readMPU16(0x47) / 131.0;
  float gyroMag = sqrt(gx * gx + gy * gy + gz * gz);

  Serial.print("Accel: ");
  Serial.print(accelMag, 2);
  Serial.print(" | Gyro: ");
  Serial.println(gyroMag, 2);

  unsigned long now = millis();

  // ===== IMPACT DETECTION =====
  if (!impactDetected && accelMag > ACC_IMPACT_G) {
    impactDetected = true;
    impactTime = now;
    Serial.println("⚠️ Impact detected");
  }

  // ===== CONFIRM ACCIDENT =====
  if (impactDetected && !accidentConfirmed) {
    if ((now - impactTime) <= CONFIRM_WINDOW) {
      if (gyroMag > GYRO_IMPACT) {
        accidentConfirmed = true;
        buzzerStartTime = now;
        digitalWrite(BUZZER_PIN, HIGH);
        Serial.println("🚨 ACCIDENT CONFIRMED 🚨");
      }
    } else {
      impactDetected = false;
    }
  }

  // ===== BUZZ + LOCK =====
  if (accidentConfirmed && (now - buzzerStartTime >= BUZZ_TIME)) {
    digitalWrite(BUZZER_PIN, LOW);
    systemLocked = true;
    Serial.println("🔒 SYSTEM LOCKED & DATA SENT");
  }

  delay(50);
}