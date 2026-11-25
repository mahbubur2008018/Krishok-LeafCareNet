import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../services/weather_service.dart';
import '../theme/app_theme.dart';

class WeatherScreen extends StatefulWidget {
  const WeatherScreen({super.key});

  @override
  State<WeatherScreen> createState() => _WeatherScreenState();
}

class _WeatherScreenState extends State<WeatherScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final _weatherService = WeatherService();
  bool _loading = true;
  String _error = '';
  Map<String, dynamic>? _data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final pos = await _getPosition();
      final data = await _weatherService.fetchWeather(pos.latitude, pos.longitude);
      if (mounted) setState(() { _data = data; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString().replaceFirst('Exception: ', ''); _loading = false; });
    }
  }

  Future<Position> _getPosition() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw Exception('Location services are disabled. Please enable them.');
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
      throw Exception('Location permission denied. Please allow in Settings.');
    }
    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.low),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: KrishokColors.background,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: KrishokColors.cardWhite,
            surfaceTintColor: Colors.transparent,
            title: const Text('Weather Forecast'),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh_rounded,
                    color: KrishokColors.primaryGreen),
                onPressed: _load,
              ),
              const SizedBox(width: 8),
            ],
          ),
          if (_loading)
            const SliverFillRemaining(
              child: Center(
                child: CircularProgressIndicator(
                  color: KrishokColors.primaryGreen,
                ),
              ),
            )
          else if (_error.isNotEmpty)
            SliverFillRemaining(child: _ErrorState(error: _error, onRetry: _load))
          else
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverList(
                delegate: SliverChildListDelegate(
                  _buildContent(),
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _buildContent() {
    final current = _data?['current'];
    final daily = _data?['daily'];

    final temp = (current?['temperature_2m'] ?? 0).toDouble();
    final hum = (current?['relative_humidity_2m'] ?? 0).toDouble();
    final code = (current?['weather_code'] ?? 0) as int;

    final dailyMaxList = (daily?['temperature_2m_max'] as List?)
        ?.map((e) => (e as num).toDouble())
        .toList() ?? [];
    final dailyMinList = (daily?['temperature_2m_min'] as List?)
        ?.map((e) => (e as num).toDouble())
        .toList() ?? [];
    final dailyCodeList = (daily?['weather_code'] as List?)
        ?.map((e) => e as int)
        .toList() ?? [];
    final dailyTimes = (daily?['time'] as List?)
        ?.map((e) => e.toString())
        .toList() ?? [];

    return [
      _CurrentWeatherCard(temp: temp, hum: hum, code: code),
      const SizedBox(height: 20),
      if (dailyMaxList.isNotEmpty) ...[
        const _ForecastHeader(),
        const SizedBox(height: 12),
        for (int i = 0; i < dailyMaxList.length && i < 7; i++)
          _ForecastRow(
            date: i < dailyTimes.length ? dailyTimes[i] : '',
            code: i < dailyCodeList.length ? dailyCodeList[i] : 0,
            max: dailyMaxList[i],
            min: dailyMinList[i],
            isToday: i == 0,
          ),
      ],
      const SizedBox(height: 24),
    ];
  }
}

// ── Weather Helpers ────────────────────────────────────────────────────────────

IconData _weatherIcon(int code) {
  if (code == 0) return Icons.wb_sunny_rounded;
  if (code <= 3) return Icons.cloud_rounded;
  if (code <= 67) return Icons.water_drop_rounded;
  if (code <= 77) return Icons.ac_unit_rounded;
  if (code <= 82) return Icons.thunderstorm_rounded;
  return Icons.wb_cloudy_rounded;
}

Color _weatherColor(int code) {
  if (code == 0) return Colors.amber;
  if (code <= 3) return Colors.blueGrey;
  if (code <= 67) return KrishokColors.sky;
  if (code <= 77) return Colors.lightBlue;
  return Colors.indigo;
}

String _dayName(String dateStr, bool isToday) {
  if (isToday) return 'Today';
  try {
    final date = DateTime.parse(dateStr);
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[date.weekday - 1];
  } catch (e) {
    return dateStr;
  }
}

// ── Widgets ────────────────────────────────────────────────────────────────────

class _ErrorState extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;

  const _ErrorState({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.location_off_rounded,
              size: 52,
              color: Colors.redAccent,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Location Error',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: KrishokColors.textDark,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            error,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              color: KrishokColors.textMedium,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Retry'),
            style: ElevatedButton.styleFrom(
              backgroundColor: KrishokColors.primaryGreen,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              elevation: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _CurrentWeatherCard extends StatelessWidget {
  final double temp;
  final double hum;
  final int code;

  const _CurrentWeatherCard({
    required this.temp,
    required this.hum,
    required this.code,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [const Color(0xFF1565C0), const Color(0xFF42A5F5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withValues(alpha: 0.35),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'CURRENT WEATHER',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: Colors.white70,
                  letterSpacing: 1.2,
                ),
              ),
              Icon(
                _weatherIcon(code),
                color: _weatherColor(code),
                size: 32,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                temp.toStringAsFixed(1),
                style: const TextStyle(
                  fontSize: 64,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  height: 1.0,
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  '°C',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w500,
                    color: Colors.white70,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              _WeatherStat(icon: Icons.water_drop_outlined, label: 'Humidity', value: '${hum.toStringAsFixed(0)}%'),
            ],
          ),
        ],
      ),
    );
  }
}

class _WeatherStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _WeatherStat({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 16),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(width: 8),
          Text(value,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
        ],
      ),
    );
  }
}

class _ForecastHeader extends StatelessWidget {
  const _ForecastHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 16,
          decoration: BoxDecoration(
            color: KrishokColors.sky,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        const Text(
          '7-DAY FORECAST',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
            color: KrishokColors.textMedium,
          ),
        ),
      ],
    );
  }
}

class _ForecastRow extends StatelessWidget {
  final String date;
  final int code;
  final double max;
  final double min;
  final bool isToday;

  const _ForecastRow({
    required this.date,
    required this.code,
    required this.max,
    required this.min,
    required this.isToday,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: isToday
            ? KrishokColors.sky.withValues(alpha: 0.1)
            : KrishokColors.cardWhite,
        borderRadius: BorderRadius.circular(16),
        border: isToday
            ? Border.all(color: KrishokColors.sky.withValues(alpha: 0.5))
            : null,
        boxShadow: isToday
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Row(
        children: [
          SizedBox(
            width: 52,
            child: Text(
              _dayName(date, isToday),
              style: TextStyle(
                fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
                fontSize: 14,
                color: isToday ? KrishokColors.sky : KrishokColors.textDark,
              ),
            ),
          ),
          Icon(
            _weatherIcon(code),
            color: _weatherColor(code),
            size: 22,
          ),
          const Spacer(),
          Text(
            '${min.toStringAsFixed(0)}°',
            style: const TextStyle(
              fontSize: 14,
              color: KrishokColors.textLight,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 6),
          const Text('—',
              style: TextStyle(color: KrishokColors.textLight, fontSize: 12)),
          const SizedBox(width: 6),
          Text(
            '${max.toStringAsFixed(0)}°C',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: KrishokColors.textDark,
            ),
          ),
        ],
      ),
    );
  }
}
