// =================================================================
// Krishok ESP32 - Industrial RS-485 Modbus RTU NPK Sensor Reader
// Hardware: ESP32-WROOM-32 + MAX485 TTL-to-RS485 + 7-in-1 Soil Sensor
// =================================================================

#define SerialPort Serial2  

// Standard Modbus RTU query frame for 7-in-1 NPK sensor
// Function code 0x03, reading 3 holding registers starting at 0x001E
const uint8_t npkQuery[] = {0x01, 0x03, 0x00, 0x1E, 0x00, 0x03, 0x65, 0xCD};

void setup() {
  Serial.begin(9600);
  // Initialize Hardware Serial2 on GPIO 16 (RX) and GPIO 17 (TX)
  SerialPort.begin(9600, SERIAL_8N1, 16, 17);
  Serial.println("ESP32 RS-485 Modbus Reader Initialized.");
}

void loop() {
  // Transmit inquiry frame to sensor
  SerialPort.write(npkQuery, sizeof(npkQuery));
  delay(100);

  // Await 11-byte Modbus response
  if (SerialPort.available() >= 11) {
    uint8_t response[11];
    SerialPort.readBytes(response, sizeof(response));

    // Decode Nitrogen, Phosphorus, and Potassium from big-endian bytes
    uint16_t nitrogen   = (response[3] << 8) | response[4]; // mg/kg
    uint16_t phosphorus = (response[5] << 8) | response[6]; // mg/kg
    uint16_t potassium  = (response[7] << 8) | response[8]; // mg/kg

    Serial.println("--- Soil Telemetry Reading ---");
    Serial.printf("Nitrogen (N)   : %u mg/kg\n", nitrogen);
    Serial.printf("Phosphorus (P) : %u mg/kg\n", phosphorus);
    Serial.printf("Potassium (K)  : %u mg/kg\n", potassium);
  }
  delay(1000);
}