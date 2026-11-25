import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../services/gemini_service.dart';
import '../services/weather_service.dart';
import '../theme/app_theme.dart';
import '../models/sensor_data.dart';
import '../utils/app_strings.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final appState = context.watch<AppState>();
    final data = appState.currentData;

    return Scaffold(
      backgroundColor: KrishokColors.background,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          _buildSliverAppBar(context, appState.isConnected),
          if (data == null)
            SliverFillRemaining(
              child: _SensorSearchingView(isConnected: appState.isConnected),
            )
          else
            SliverPadding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  if (appState.isShowingStaleData)
                    _StaleDataBanner(staleSince: appState.staleSinceLabel),
                  if (appState.isShowingStaleData)
                    const SizedBox(height: 12),
                  _ClimateCard(temp: data.sht20.temp, hum: data.sht20.hum),
                  const SizedBox(height: 20),
                  _SectionLabel(label: context.s.liveTelemetry),
                  const SizedBox(height: 12),
                  _MoistureCard(moisture: data.soilMoisture.moisture),
                  const SizedBox(height: 16),
                  _NPKCard(npk: data.npk),
                  const SizedBox(height: 16),
                  _SensorSuggestionCard(data: data),
                  const SizedBox(height: 24),
                ]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSliverAppBar(BuildContext context, bool isConnected) {
    return SliverAppBar(
      pinned: true,
      backgroundColor: KrishokColors.cardWhite,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      expandedHeight: 0,
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: KrishokColors.mintGreen,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.eco_rounded,
              size: 20,
              color: KrishokColors.primaryGreen,
            ),
          ),
          const SizedBox(width: 10),
          const Text(
            'Krishok',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 20,
              color: KrishokColors.textDark,
            ),
          ),
        ],
      ),
      actions: [
        _ConnectionBadge(isConnected: isConnected),
        const SizedBox(width: 16),
      ],
    );
  }
}

class _ConnectionBadge extends StatefulWidget {
  final bool isConnected;
  const _ConnectionBadge({required this.isConnected});

  @override
  State<_ConnectionBadge> createState() => _ConnectionBadgeState();
}

class _ConnectionBadgeState extends State<_ConnectionBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: widget.isConnected
            ? KrishokColors.primaryGreen.withValues(alpha: 0.12)
            : Colors.red.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FadeTransition(
            opacity: _pulse,
            child: Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: widget.isConnected
                    ? KrishokColors.successGreen
                    : Colors.red,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            widget.isConnected ? context.s.online : context.s.offline,
            style: TextStyle(
              color: widget.isConnected
                  ? KrishokColors.primaryGreen
                  : Colors.red,
              fontWeight: FontWeight.w700,
              fontSize: 10,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 16,
          decoration: BoxDecoration(
            color: KrishokColors.primaryGreen,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
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

class _ClimateCard extends StatefulWidget {
  final double temp;
  final double hum;
  const _ClimateCard({required this.temp, required this.hum});

  @override
  State<_ClimateCard> createState() => _ClimateCardState();
}

class _ClimateCardState extends State<_ClimateCard> {
  int? _rainPercent;

  @override
  void initState() {
    super.initState();
    _fetchRain();
  }

  Future<void> _fetchRain() async {
    try {
      final p = await WeatherService().fetchRainProbability();
      if (mounted) setState(() => _rainPercent = p);
    } catch (_) {
      // Network failure — leave _rainPercent null (shows "—")
    }
  }

  IconData _weatherIcon() {
    if (_rainPercent == null) return Icons.wb_sunny_rounded;
    if (_rainPercent! >= 70) return Icons.thunderstorm_rounded;
    if (_rainPercent! >= 40) return Icons.cloud_rounded;
    return Icons.wb_sunny_rounded;
  }

  Color _weatherIconColor() {
    if (_rainPercent == null) return Colors.amber;
    if (_rainPercent! >= 70) return Colors.lightBlueAccent;
    if (_rainPercent! >= 40) return Colors.white70;
    return Colors.amber;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2E7D32), Color(0xFF4CAF50)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: KrishokColors.primaryGreen.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.s.climateConditions,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: Colors.white70,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.temp.toStringAsFixed(1),
                    style: const TextStyle(
                      fontSize: 52,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      height: 1.0,
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(top: 8.0),
                    child: Text(
                      '°C',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w500,
                        color: Colors.white70,
                      ),
                    ),
                  ),
                ],
              ),
              Icon(_weatherIcon(), color: _weatherIconColor(), size: 40),
            ],
          ),
          const SizedBox(height: 12),
          // Humidity row
          _climateRow(
            icon: Icons.water_drop_outlined,
            label: context.s.humidity,
            value: '${widget.hum.toStringAsFixed(0)}%',
          ),
          const SizedBox(height: 8),
          // Rain probability row
          _climateRow(
            icon: Icons.umbrella_rounded,
            label: context.s.rainChance,
            value: _rainPercent != null ? '$_rainPercent%' : '—',
            valueStyle: _rainPercent != null && _rainPercent! >= 60
                ? const TextStyle(
                    color: Colors.lightBlueAccent,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  )
                : null,
          ),
        ],
      ),
    );
  }

  Widget _climateRow({
    required IconData icon,
    required String label,
    required String value,
    TextStyle? valueStyle,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 16),
          const SizedBox(width: 8),
          Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 13)),
          const Spacer(),
          Text(
            value,
            style: valueStyle ??
                const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
          ),
        ],
      ),
    );
  }
}

class _MoistureCard extends StatelessWidget {
  final double moisture;
  const _MoistureCard({required this.moisture});

  Color get _moistureColor {
    if (moisture < 30) return Colors.orange;
    if (moisture < 60) return KrishokColors.primaryGreen;
    return Colors.blue;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: KrishokColors.cardWhite,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                context.s.soilMoisture.toUpperCase(),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: KrishokColors.textMedium,
                  letterSpacing: 1.1,
                ),
              ),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _moistureColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.water_drop_rounded,
                    color: _moistureColor, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                moisture.toStringAsFixed(1),
                style: const TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.w700,
                  color: KrishokColors.textDark,
                  height: 1.1,
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(bottom: 7, left: 3),
                child: Text(
                  '%',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: KrishokColors.textMedium,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: moisture / 100),
              duration: const Duration(milliseconds: 800),
              curve: Curves.easeOut,
              builder: (context, value, child) => LinearProgressIndicator(
                value: value,
                backgroundColor: KrishokColors.surfaceGray,
                color: _moistureColor,
                minHeight: 10,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '0%',
                style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey[500],
                    fontWeight: FontWeight.w600),
              ),
              Text(
                'TARGET: 55%',
                style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey[500],
                    fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NPKCard extends StatelessWidget {
  final NPKData npk;
  const _NPKCard({required this.npk});

  static const _maxNPK = 100.0;

  String _statusLabel(int value, String lang) {
    final isBn = lang == 'bn';
    if (value < 25) return isBn ? 'কম' : 'Low';
    if (value < 70) return isBn ? 'স্বাভাবিক' : 'Good';
    return isBn ? 'বেশি' : 'High';
  }

  Color _statusColor(int value) {
    if (value < 25) return KrishokColors.potassiumLow;
    if (value < 70) return KrishokColors.primaryGreen;
    return KrishokColors.darkGreen;
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.read<AppState>().language;
    final isBn = lang == 'bn';
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: KrishokColors.cardWhite,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.s.npkValues.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: KrishokColors.textMedium,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 20),
          _NPKRow(
            label: 'N',
            fullLabel: isBn ? 'নাইট্রোজেন' : 'Nitrogen',
            value: npk.n,
            max: _maxNPK,
            barColor: KrishokColors.nitrogenColor,
            status: _statusLabel(npk.n, lang),
            statusColor: _statusColor(npk.n),
          ),
          const SizedBox(height: 18),
          _NPKRow(
            label: 'P',
            fullLabel: isBn ? 'ফসফরাস' : 'Phosphorus',
            value: npk.p,
            max: _maxNPK,
            barColor: KrishokColors.phosphorusColor,
            status: _statusLabel(npk.p, lang),
            statusColor: _statusColor(npk.p),
          ),
          const SizedBox(height: 18),
          _NPKRow(
            label: 'K',
            fullLabel: isBn ? 'পটাসিয়াম' : 'Potassium',
            value: npk.k,
            max: _maxNPK,
            barColor: KrishokColors.potassiumLow,
            status: _statusLabel(npk.k, lang),
            statusColor: _statusColor(npk.k),
          ),
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 10),
          Text(
            'Values in mg/kg',
            style: TextStyle(fontSize: 11, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }
}

class _NPKRow extends StatelessWidget {
  final String label;
  final String fullLabel;
  final int value;
  final double max;
  final Color barColor;
  final String status;
  final Color statusColor;

  const _NPKRow({
    required this.label,
    required this.fullLabel,
    required this.value,
    required this.max,
    required this.barColor,
    required this.status,
    required this.statusColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            // Letter badge
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: barColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    color: barColor,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                fullLabel,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: KrishokColors.textDark,
                ),
              ),
            ),
            Text(
              '$value mg/kg',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: KrishokColors.textMedium,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                status,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: statusColor,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: (value / max).clamp(0.0, 1.0)),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOut,
            builder: (context, val, child) => LinearProgressIndicator(
              value: val,
              backgroundColor: KrishokColors.surfaceGray,
              color: barColor,
              minHeight: 7,
            ),
          ),
        ),
      ],
    );
  }
}

class _SensorSuggestionCard extends StatefulWidget {
  final SensorData data;
  const _SensorSuggestionCard({required this.data});

  @override
  State<_SensorSuggestionCard> createState() => _SensorSuggestionCardState();
}

class _SensorSuggestionCardState extends State<_SensorSuggestionCard> {
  final GeminiService _gemini = GeminiService();
  bool _isLoading = false;
  String? _suggestion;

  Future<void> _loadSuggestion() async {
    setState(() => _isLoading = true);
    final d = widget.data;
    final result = await _gemini.getSensorRecommendation(
      npkN: d.npk.n,
      npkP: d.npk.p,
      npkK: d.npk.k,
      soilMoisture: d.soilMoisture.moisture,
      airTemp: d.sht20.temp,
      airHumidity: d.sht20.hum,
      language: context.read<AppState>().language,
    );
    if (mounted) setState(() { _isLoading = false; _suggestion = result; });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: KrishokColors.cardWhite,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: KrishokColors.primaryGreen.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: KrishokColors.primaryGreen.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: KrishokColors.mintGreen,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.auto_awesome_rounded,
                    size: 18, color: KrishokColors.primaryGreen),
              ),
              const SizedBox(width: 10),
              Text(
                context.s.aiSuggestionTitle,
                style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: KrishokColors.textDark),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: KrishokColors.amber.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'AI',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: KrishokColors.amber),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          if (_isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.5, color: KrishokColors.primaryGreen),
                ),
              ),
            )
          else if (_suggestion != null) ...[
            Text(
              _suggestion!,
              style: const TextStyle(
                  fontSize: 13,
                  color: KrishokColors.textMedium,
                  height: 1.7),
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: _loadSuggestion,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.refresh_rounded,
                      size: 14, color: KrishokColors.textLight),
                  const SizedBox(width: 4),
                  Text(
                    context.s.isBn ? 'রিফ্রেশ' : 'Refresh',
                    style: const TextStyle(
                        fontSize: 12, color: KrishokColors.textLight),
                  ),
                ],
              ),
            ),
          ] else
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _loadSuggestion,
                icon: const Icon(Icons.auto_awesome_rounded, size: 16),
                label: Text(context.s.getAiSuggestion),
                style: OutlinedButton.styleFrom(
                  foregroundColor: KrishokColors.primaryGreen,
                  side: BorderSide(
                      color: KrishokColors.primaryGreen.withValues(alpha: 0.5)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  textStyle: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SensorSearchingView extends StatefulWidget {
  final bool isConnected;
  const _SensorSearchingView({required this.isConnected});

  @override
  State<_SensorSearchingView> createState() => _SensorSearchingViewState();
}

class _SensorSearchingViewState extends State<_SensorSearchingView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Pulsing sensor icon
          FadeTransition(
            opacity: _pulse,
            child: Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                color: KrishokColors.primaryGreen.withValues(alpha: 0.08),
                shape: BoxShape.circle,
                border: Border.all(
                  color: KrishokColors.primaryGreen.withValues(alpha: 0.2),
                  width: 2,
                ),
              ),
              child: const Icon(
                Icons.sensors_rounded,
                size: 40,
                color: KrishokColors.primaryGreen,
              ),
            ),
          ),
          const SizedBox(height: 28),
          Text(
            context.s.sensorSearchTitle,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: KrishokColors.textDark,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            context.s.isBn
                ? 'ESP32 WiFi নেটওয়ার্কে সংযুক্ত হন এবং লাইভ মাঠের ডেটা দেখুন।'
                : 'Connect your phone to the ESP32 WiFi network to see live field data.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              color: KrishokColors.textMedium,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 28),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: KrishokColors.surfaceGray,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                _ConnectStep(step: '1', text: context.s.sensorStep1),
                const SizedBox(height: 10),
                _ConnectStep(step: '2', text: context.s.sensorStep2),
                const SizedBox(height: 10),
                _ConnectStep(step: '3', text: context.s.sensorStep3),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectStep extends StatelessWidget {
  final String step;
  final String text;
  const _ConnectStep({required this.step, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: KrishokColors.primaryGreen,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Center(
            child: Text(
              step,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 13,
              color: KrishokColors.textMedium,
            ),
          ),
        ),
      ],
    );
  }
}

class _StaleDataBanner extends StatelessWidget {
  final String staleSince;
  const _StaleDataBanner({required this.staleSince});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: KrishokColors.amber.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: KrishokColors.amber.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.wifi_off_rounded,
              size: 18, color: KrishokColors.orangeWarning),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.s.isBn ? 'সেন্সর অফলাইন' : 'Sensor Offline',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: KrishokColors.orangeWarning,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  context.s.isBn
                      ? '$staleSince আগের ডেটা দেখানো হচ্ছে'
                      : 'Showing last data from $staleSince',
                  style: const TextStyle(
                    fontSize: 11,
                    color: KrishokColors.textMedium,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: KrishokColors.amber.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'STALE',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                color: KrishokColors.orangeWarning,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
