// =================================================================
// Krishok ESP32 - Multi-Sensor Telemetry Station & Local SoftAP Server
// Hardware: ESP32-WROOM-32 DevKit V1
// Sensors:
//   1. 7-in-1 Soil NPK Probe (RS-485 Modbus RTU on Serial2, DE/RE=GPIO 4)
//   2. SHT20 Ambient Microclimate Sensor (I2C on SDA=GPIO 21, SCL=GPIO 22)
//   3. Capacitive Soil Moisture Sensor v1.2 (Analog ADC on GPIO 34)
//
// Network & Protocol:
//   - Local Wi-Fi SoftAP: "Krishok_Station_01" (192.168.4.1)
//   - REST Telemetry Endpoint: GET /api/data (JSON)
//   - Fully autonomous, offline-first operation (Zero internet required)
// =================================================================

#include <WiFi.h>
#include <WebServer.h>
#include <Wire.h>

// --- Configuration & Pin Definitions ---
const char* ap_ssid = "Krishok_Station_01";
const char* ap_pass = "krishok1234";

#define MAX485_DE_RE 4
#define SOIL_ADC_PIN 34
#define SHT20_I2C_ADDR 0x40

// SHT20 Measurement Commands (No Hold Master)
#define SHT20_CMD_TEMP 0xF3
#define SHT20_CMD_HUMID 0xF5

// RS-485 Modbus RTU Query Frame: Read 3 holding registers (N, P, K) starting at 0x001E
const uint8_t npkQuery[] = {0x01, 0x03, 0x00, 0x1E, 0x00, 0x03, 0x65, 0xCD};

WebServer server(80);
#define ModbusSerial Serial2

// Telemetry state cache
uint16_t current_n = 45;
uint16_t current_p = 22;
uint16_t current_k = 118;
float current_temp = 28.4;
float current_humidity = 65.2;
float current_moisture = 44.0;
unsigned long lastSensorRead = 0;

// --- SHT20 Acquisition Functions ---
float readSHT20Temperature() {
  Wire.beginTransmission(SHT20_I2C_ADDR);
  Wire.write(SHT20_CMD_TEMP);
  if (Wire.endTransmission() != 0) return current_temp;

  delay(85); // Wait for conversion (14-bit: ~85ms)

  Wire.requestFrom(SHT20_I2C_ADDR, 3);
  if (Wire.available() >= 2) {
    uint16_t raw = (Wire.read() << 8) | Wire.read();
    raw &= ~0x0003; // Clear status bits
    return -46.85 + 175.72 * ((float)raw / 65536.0);
  }
  return current_temp;
}

float readSHT20Humidity() {
  Wire.beginTransmission(SHT20_I2C_ADDR);
  Wire.write(SHT20_CMD_HUMID);
  if (Wire.endTransmission() != 0) return current_humidity;

  delay(30); // Wait for conversion (12-bit: ~29ms)

  Wire.requestFrom(SHT20_I2C_ADDR, 3);
  if (Wire.available() >= 2) {
    uint16_t raw = (Wire.read() << 8) | Wire.read();
    raw &= ~0x0003; // Clear status bits
    float hum = -6.0 + 125.0 * ((float)raw / 65536.0);
    return constrain(hum, 0.0, 100.0);
  }
  return current_humidity;
}

// --- Capacitive Soil Moisture Acquisition ---
float readSoilMoisture() {
  // Average multiple ADC samples to suppress electrical noise
  long sum = 0;
  for (int i = 0; i < 16; i++) {
    sum += analogRead(SOIL_ADC_PIN);
    delay(5);
  }
  int raw_adc = sum / 16;

  // Calibrated voltage thresholds for capacitive v1.2 sensor:
  // Air (completely dry): ~3200 raw ADC counts
  // Submerged in water (saturated): ~1400 raw ADC counts
  float pct = ((float)(3200 - raw_adc) / (float)(3200 - 1400)) * 100.0;
  return constrain(pct, 0.0, 100.0);
}

// --- RS-485 Modbus RTU NPK Acquisition ---
void readModbusNPK() {
  // Set MAX485 to transmit mode
  digitalWrite(MAX485_DE_RE, HIGH);
  delay(5);
  ModbusSerial.write(npkQuery, sizeof(npkQuery));
  ModbusSerial.flush();
  
  // Set MAX485 to receive mode
  digitalWrite(MAX485_DE_RE, LOW);
  delay(100);

  if (ModbusSerial.available() >= 11) {
    uint8_t res[11];
    ModbusSerial.readBytes(res, 11);
    
    // Validate frame header and byte count
    if (res[0] == 0x01 && res[1] == 0x03 && res[2] == 0x06) {
      current_n = (res[3] << 8) | res[4];
      current_p = (res[5] << 8) | res[6];
      current_k = (res[7] << 8) | res[8];
    }
  }
}

// --- HTTP REST API Handler ---
void handleApiData() {
  String json = "{";
  json += "\"status\":\"success\",";
  json += "\"nitrogen\":" + String(current_n) + ",";
  json += "\"phosphorus\":" + String(current_p) + ",";
  json += "\"potassium\":" + String(current_k) + ",";
  json += "\"temperature\":" + String(current_temp, 1) + ",";
  json += "\"humidity\":" + String(current_humidity, 1) + ",";
  json += "\"soilPercent\":" + String(current_moisture, 1) + ",";
  json += "\"timestamp\":" + String(millis() / 1000);
  json += "}";
  
  server.sendHeader("Access-Control-Allow-Origin", "*");
  server.send(200, "application/json", json);
}

void setup() {
  Serial.begin(115200);
  pinMode(MAX485_DE_RE, OUTPUT);
  digitalWrite(MAX485_DE_RE, LOW);

  // Initialize Hardware Serial 2 for RS-485 (RX=16, TX=17)
  ModbusSerial.begin(9600, SERIAL_8N1, 16, 17);

  // Initialize I2C for SHT20 (SDA=21, SCL=22)
  Wire.begin(21, 22);

  // Initialize ADC for soil moisture
  analogReadResolution(12);
  analogSetAttenuation(ADC_11db);

  // Spin up local isolated SoftAP
  WiFi.mode(WIFI_AP);
  WiFi.softAP(ap_ssid, ap_pass);
  Serial.println("[Krishok ESP32] SoftAP Active.");
  Serial.print("  SSID: "); Serial.println(ap_ssid);
  Serial.print("  IP Address: "); Serial.println(WiFi.softAPIP());

  server.on("/api/data", HTTP_GET, handleApiData);
  server.begin();
  Serial.println("[Krishok ESP32] HTTP REST endpoint /api/data initialized.");
}

void loop() {
  server.handleClient();

  // Non-blocking periodic telemetry polling every 2500ms
  if (millis() - lastSensorRead > 2500) {
    lastSensorRead = millis();
    readModbusNPK();
    current_temp = readSHT20Temperature();
    current_humidity = readSHT20Humidity();
    current_moisture = readSoilMoisture();
  }
}
