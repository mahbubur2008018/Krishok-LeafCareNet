class SensorData {
  final NPKData npk;
  final SHT20Data sht20;
  final SoilMoistureData soilMoisture;

  SensorData({
    required this.npk,
    required this.sht20,
    required this.soilMoisture,
  });

  factory SensorData.fromJson(Map<String, dynamic> json) {
    return SensorData(
      npk: NPKData.fromJson(json['npk'] ?? {}),
      sht20: SHT20Data.fromJson(json['sht20'] ?? {}),
      soilMoisture: SoilMoistureData.fromJson(json['soil_mosture'] ?? {}),
    );
  }

  Map<String, dynamic> toJson() => {
    'npk': {'n': npk.n, 'p': npk.p, 'k': npk.k},
    'sht20': {'temp': sht20.temp, 'hum': sht20.hum},
    'soil_mosture': {'mosture': soilMoisture.moisture},
  };
}

class NPKData {
  final int n;
  final int p;
  final int k;

  NPKData({this.n = 0, this.p = 0, this.k = 0});

  factory NPKData.fromJson(Map<String, dynamic> json) {
    return NPKData(
      n: json['n'] ?? 0,
      p: json['p'] ?? 0,
      k: json['k'] ?? 0,
    );
  }
}

class SHT20Data {
  final double temp;
  final double hum;

  SHT20Data({this.temp = 0.0, this.hum = 0.0});

  factory SHT20Data.fromJson(Map<String, dynamic> json) {
    return SHT20Data(
      temp: (json['temp'] ?? 0.0).toDouble(),
      hum: (json['hum'] ?? 0.0).toDouble(),
    );
  }
}

class SoilMoistureData {
  final double moisture;

  SoilMoistureData({this.moisture = 0.0});

  factory SoilMoistureData.fromJson(Map<String, dynamic> json) {
    return SoilMoistureData(
      moisture: (json['mosture'] ?? 0.0).toDouble(),
    );
  }
}
