# ESP32 IoT Station: Hardware Wiring and Pinout Guide

## Required Components
1. **ESP32-WROOM-32 Dev Module**
2. **Industrial 7-in-1 Soil NPK Sensor (Modbus RTU over RS-485)**
3. **MAX485 TTL-to-RS485 Transceiver Module**
4. **SHT20 / AHT10 I2C Ambient Temperature & Humidity Sensor**
5. **Capacitive Soil Moisture Sensor v1.2**
6. **12V DC External Power Supply** (for sensor) + LM2596 buck converter (to 5V for ESP32)

## Wiring Connections

### 1. MAX485 to ESP32
- **RO (Receiver Out)  -> GPIO 16 (RX2)**
- **DI (Driver In)     -> GPIO 17 (TX2)**
- **DE & RE (Tied)     -> GPIO 4 (Direction Control)**
- **VCC                -> 5V (VIN)**
- **GND                -> GND**

### 2. MAX485 to 7-in-1 Sensor
- **A+ -> Sensor RS-485 A (Yellow Wire)**
- **B- -> Sensor RS-485 B (Blue Wire)**
- **Sensor VCC -> External 12V DC (Brown Wire)**
- **Sensor GND -> External Common Ground (Black Wire)**

### 3. SHT20 Ambient Sensor (I2C)
- **SDA -> GPIO 21**
- **SCL -> GPIO 22**
- **VCC -> 3.3V**
- **GND -> GND**