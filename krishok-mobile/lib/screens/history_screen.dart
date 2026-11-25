import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../services/scan_history_service.dart';
import '../services/sensor_history_service.dart';
import '../theme/app_theme.dart';
import '../utils/app_strings.dart';
import '../utils/disease_labels.dart';

// ════════════════════════════════════════════════════════════════════════════════
// HISTORY SCREEN
// ════════════════════════════════════════════════════════════════════════════════

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  Future<void> _deleteScan(String id) async {
    await context.read<AppState>().deleteScan(id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.s.scanDeleted),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
          backgroundColor: KrishokColors.primaryGreen,
        ),
      );
    }
  }

  Future<void> _clearAll() async {
    final appState = context.read<AppState>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(context.s.clearAllHistory),
        content: Text(context.s.clearAllConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.s.cancel,
                style: const TextStyle(color: KrishokColors.textMedium)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.s.clear,
                style: const TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await appState.clearScanHistory();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final appState = context.watch<AppState>();
    final scans = appState.scanHistory;
    final stats = appState.weeklyStats;

    return Scaffold(
      backgroundColor: KrishokColors.background,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          _buildAppBar(),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _RiskSummaryCard(stats: stats),
                const SizedBox(height: 24),
                _DailyChart(dailyCounts: stats.dailyCounts),
                const SizedBox(height: 24),
                _SensorTrendCard(history: appState.sensorHistory),
                const SizedBox(height: 24),
                _ScanListSection(
                  scans: scans,
                  onDelete: _deleteScan,
                ),
                const SizedBox(height: 24),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  SliverAppBar _buildAppBar() {
    return SliverAppBar(
      pinned: true,
      backgroundColor: KrishokColors.cardWhite,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: KrishokColors.mintGreen,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(LucideIcons.history,
                size: 20, color: KrishokColors.primaryGreen),
          ),
          const SizedBox(width: 10),
          Text(
            context.s.scanHistory,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 20,
              color: KrishokColors.textDark,
            ),
          ),
        ],
      ),
      actions: [
        PopupMenuButton<String>(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: KrishokColors.primaryGreen.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(LucideIcons.moreHorizontal,
                size: 18, color: KrishokColors.primaryGreen),
          ),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          onSelected: (value) {
            if (value == 'clear') _clearAll();
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'clear',
              child: Row(
                children: [
                  const Icon(LucideIcons.trash2, size: 16, color: Colors.redAccent),
                  const SizedBox(width: 10),
                  Text(context.s.clearAll, style: const TextStyle(color: Colors.redAccent)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(width: 12),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════════
// RISK SUMMARY CARD
// ════════════════════════════════════════════════════════════════════════════════

class _RiskSummaryCard extends StatelessWidget {
  final WeeklyStats stats;
  const _RiskSummaryCard({required this.stats});

  Color get _riskColor {
    switch (stats.riskLevel) {
      case 'Low':
        return KrishokColors.primaryGreen;
      case 'Moderate':
        return KrishokColors.amber;
      case 'High':
        return KrishokColors.orangeWarning;
      case 'Critical':
        return Colors.redAccent;
      default:
        return KrishokColors.primaryGreen;
    }
  }

  IconData get _riskIcon {
    switch (stats.riskLevel) {
      case 'Low':
        return Icons.check_circle_rounded;
      case 'Moderate':
        return Icons.info_rounded;
      case 'High':
        return Icons.warning_amber_rounded;
      case 'Critical':
        return Icons.dangerous_rounded;
      default:
        return Icons.check_circle_rounded;
    }
  }

  String _riskMessage(BuildContext context) =>
      context.s.riskMessage(stats.riskLevel);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: KrishokColors.cardWhite,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: _riskColor.withValues(alpha: 0.2),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Text(
            context.s.diseaseRisk7Days,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
              color: KrishokColors.textMedium,
            ),
          ),

          const SizedBox(height: 20),

          // Risk percentage + circular indicator
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Percentage and label
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${stats.riskPercent.toInt()}%',
                          style: TextStyle(
                            fontSize: 48,
                            fontWeight: FontWeight.w800,
                            color: _riskColor,
                            height: 1.0,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            '→ ${stats.riskLevel}',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: _riskColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Circular progress
              SizedBox(
                width: 64,
                height: 64,
                child: Stack(
                  children: [
                    SizedBox.expand(
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: stats.riskPercent / 100),
                        duration: const Duration(milliseconds: 900),
                        curve: Curves.easeOut,
                        builder: (context, value, _) =>
                            CircularProgressIndicator(
                          value: value,
                          strokeWidth: 6,
                          backgroundColor:
                              _riskColor.withValues(alpha: 0.15),
                          color: _riskColor,
                          strokeCap: StrokeCap.round,
                        ),
                      ),
                    ),
                    Center(
                      child: Icon(
                        _riskIcon,
                        color: _riskColor,
                        size: 26,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          // Warning message
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: _riskColor.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _riskColor.withValues(alpha: 0.15),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(_riskIcon, size: 16, color: _riskColor),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _riskMessage(context),
                    style: TextStyle(
                      fontSize: 12,
                      color: _riskColor.withValues(alpha: 0.9),
                      height: 1.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Stats row
          Row(
            children: [
              _StatChip(
                value: '${stats.totalScans}',
                label: context.s.totalScans,
              ),
              const SizedBox(width: 12),
              _StatChip(
                value: '${stats.diseasesFound}',
                label: context.s.diseasesFound,
                valueColor: stats.diseasesFound > 0
                    ? KrishokColors.orangeWarning
                    : null,
              ),
              const SizedBox(width: 12),
              _StatChip(
                value: '${stats.healthyCount}',
                label: context.s.healthy,
                valueColor: stats.healthyCount > 0
                    ? KrishokColors.primaryGreen
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String value;
  final String label;
  final Color? valueColor;

  const _StatChip({
    required this.value,
    required this.label,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: KrishokColors.surfaceGray,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: valueColor ?? KrishokColors.textDark,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: KrishokColors.textLight,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════════
// DAILY CHART
// ════════════════════════════════════════════════════════════════════════════════

class _DailyChart extends StatelessWidget {
  final List<int> dailyCounts;
  const _DailyChart({required this.dailyCounts});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: KrishokColors.cardWhite,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
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
                width: 3,
                height: 16,
                decoration: BoxDecoration(
                  color: KrishokColors.primaryGreen,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                context.s.dailyActivity,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: KrishokColors.textMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 140,
            child: CustomPaint(
              size: Size.infinite,
              painter: _BarChartPainter(dailyCounts: dailyCounts),
            ),
          ),
          const SizedBox(height: 12),
          _ChartLegend(dailyCounts: dailyCounts),
        ],
      ),
    );
  }
}

class _ChartLegend extends StatelessWidget {
  final List<int> dailyCounts;
  const _ChartLegend({required this.dailyCounts});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: List.generate(7, (i) {
        final date = now.subtract(Duration(days: 6 - i));
        return Text(
          days[date.weekday - 1],
          style: TextStyle(
            fontSize: 10,
            fontWeight: i == 6 ? FontWeight.w700 : FontWeight.w500,
            color: i == 6
                ? KrishokColors.primaryGreen
                : KrishokColors.textLight,
          ),
        );
      }),
    );
  }
}

class _BarChartPainter extends CustomPainter {
  final List<int> dailyCounts;
  _BarChartPainter({required this.dailyCounts});

  @override
  void paint(Canvas canvas, Size size) {
    final maxCount = dailyCounts.reduce(math.max).clamp(1, 100);
    final barWidth = size.width / 7 * 0.45;
    final spacing = size.width / 7;

    // Grid lines
    final gridPaint = Paint()
      ..color = KrishokColors.surfaceGray
      ..strokeWidth = 1;

    for (int i = 0; i <= 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    for (int i = 0; i < 7 && i < dailyCounts.length; i++) {
      final count = dailyCounts[i];
      final barHeight =
          count > 0 ? (count / maxCount * size.height * 0.85).clamp(8.0, size.height) : 0.0;
      final x = spacing * i + (spacing - barWidth) / 2;
      final y = size.height - barHeight;

      if (count == 0) continue;

      final barRect =
          RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, barWidth, barHeight),
        const Radius.circular(6),
      );

      final isToday = i == 6;
      final paint = Paint()
        ..color = isToday
            ? KrishokColors.primaryGreen
            : Colors.redAccent.withValues(alpha: 0.8);

      canvas.drawRRect(barRect, paint);

      // Value label
      final textPainter = TextPainter(
        text: TextSpan(
          text: '$count',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: isToday
                ? KrishokColors.primaryGreen
                : KrishokColors.textMedium,
          ),
        ),
        textDirection: ui.TextDirection.ltr,
      )..layout();

      textPainter.paint(
        canvas,
        Offset(x + barWidth / 2 - textPainter.width / 2, y - 16),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BarChartPainter oldDelegate) =>
      oldDelegate.dailyCounts != dailyCounts;
}

// ════════════════════════════════════════════════════════════════════════════════
// SCAN LIST
// ════════════════════════════════════════════════════════════════════════════════

class _ScanListSection extends StatelessWidget {
  final List<ScanRecord> scans;
  final ValueChanged<String> onDelete;

  const _ScanListSection({
    required this.scans,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
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
              'All Scans (${scans.length})',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: KrishokColors.textMedium,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (scans.isEmpty)
          _EmptyScanState()
        else
          ...scans.map((scan) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _ScanCard(
                  scan: scan,
                  onDelete: () => onDelete(scan.id),
                  onTap: () => _showScanDetail(context, scan),
                ),
              )),
      ],
    );
  }
}

class _EmptyScanState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      decoration: BoxDecoration(
        color: KrishokColors.cardWhite,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: KrishokColors.mintGreen,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(LucideIcons.scanLine,
                size: 36, color: KrishokColors.primaryGreen),
          ),
          const SizedBox(height: 20),
          const Text(
            'No Scans Yet',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: KrishokColors.textDark,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Start scanning your crops with the AI Scan tab\nto see your history here.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: KrishokColors.textLight,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}

void _showScanDetail(BuildContext context, ScanRecord scan) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ScanDetailSheet(scan: scan),
  );
}

class _ScanCard extends StatelessWidget {
  final ScanRecord scan;
  final VoidCallback onDelete;
  final VoidCallback onTap;

  const _ScanCard({
    required this.scan,
    required this.onDelete,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final timeStr = DateFormat('d MMM yyyy, h:mm a').format(scan.timestamp);
    final accentColor =
        scan.isHealthy ? KrishokColors.primaryGreen : Colors.orange[700]!;

    return GestureDetector(
      onTap: onTap,
      child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: KrishokColors.cardWhite,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          // Thumbnail
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: accentColor.withValues(alpha: 0.08),
            ),
            child: scan.imagePath != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.file(
                      File(scan.imagePath!),
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Center(
                        child: Text(scan.cropEmoji,
                            style: const TextStyle(fontSize: 24)),
                      ),
                    ),
                  )
                : Center(
                    child: Text(scan.cropEmoji,
                        style: const TextStyle(fontSize: 24)),
                  ),
          ),
          const SizedBox(width: 14),

          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  DiseaseLabels.get(scan.diseaseLabel.isNotEmpty ? scan.diseaseLabel : scan.diseaseName, context.read<AppState>().language),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: KrishokColors.textDark,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  '${scan.cropModel}  ·  ${(scan.confidence * 100).toStringAsFixed(1)}%',
                  style: const TextStyle(
                    fontSize: 12,
                    color: KrishokColors.textMedium,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  timeStr,
                  style: const TextStyle(
                    fontSize: 11,
                    color: KrishokColors.textLight,
                  ),
                ),
              ],
            ),
          ),

          // Delete button
          IconButton(
            onPressed: onDelete,
            icon: const Icon(LucideIcons.trash2,
                size: 16, color: Colors.redAccent),
            style: IconButton.styleFrom(
              backgroundColor: Colors.red.withValues(alpha: 0.06),
              padding: const EdgeInsets.all(8),
              minimumSize: const Size(36, 36),
            ),
          ),
        ],
      ),
    ), // Container
    ); // GestureDetector
  }
}

// ════════════════════════════════════════════════════════════════════════════════
// SCAN DETAIL BOTTOM SHEET
// ════════════════════════════════════════════════════════════════════════════════

class _ScanDetailSheet extends StatelessWidget {
  final ScanRecord scan;
  const _ScanDetailSheet({required this.scan});

  @override
  Widget build(BuildContext context) {
    final timeStr =
        DateFormat('d MMM yyyy, h:mm a').format(scan.timestamp);
    final accentColor =
        scan.isHealthy ? KrishokColors.primaryGreen : Colors.orange[700]!;
    final hasInsight =
        scan.aiInsight != null && scan.aiInsight!.isNotEmpty;

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, controller) => Container(
        decoration: const BoxDecoration(
          color: KrishokColors.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            // Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Image + basic info card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: KrishokColors.cardWhite,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: accentColor.withValues(alpha: 0.3)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Thumbnail
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      color: accentColor.withValues(alpha: 0.08),
                    ),
                    child: scan.imagePath != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Image.file(
                              File(scan.imagePath!),
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stack) => Center(
                                child: Text(scan.cropEmoji,
                                    style: const TextStyle(fontSize: 30)),
                              ),
                            ),
                          )
                        : Center(
                            child: Text(scan.cropEmoji,
                                style: const TextStyle(fontSize: 30)),
                          ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          DiseaseLabels.get(scan.diseaseLabel.isNotEmpty ? scan.diseaseLabel : scan.diseaseName, context.read<AppState>().language),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: KrishokColors.textDark,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${scan.cropModel}  ·  ${(scan.confidence * 100).toStringAsFixed(1)}% confidence',
                          style: const TextStyle(
                              fontSize: 12,
                              color: KrishokColors.textMedium),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          timeStr,
                          style: const TextStyle(
                              fontSize: 11,
                              color: KrishokColors.textLight),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: accentColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            scan.isHealthy ? 'Healthy' : 'Disease Detected',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: accentColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // AI Analysis section
            Row(
              children: [
                Container(
                  width: 3,
                  height: 16,
                  decoration: BoxDecoration(
                    color: KrishokColors.amber,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  context.s.aiInsightTitle.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                    color: KrishokColors.textMedium,
                  ),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: KrishokColors.amber.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'AI',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: KrishokColors.amber,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            if (hasInsight)
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: KrishokColors.cardWhite,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Text(
                  scan.aiInsight!,
                  style: const TextStyle(
                    fontSize: 13,
                    color: KrishokColors.textMedium,
                    height: 1.75,
                  ),
                ),
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(
                    vertical: 32, horizontal: 20),
                decoration: BoxDecoration(
                  color: KrishokColors.cardWhite,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.auto_awesome_outlined,
                        size: 32, color: KrishokColors.textLight),
                    const SizedBox(height: 12),
                    Text(
                      context.s.noAiInsightYet.split('\n').first,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: KrishokColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      context.s.noAiInsightYet.split('\n').last,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 12,
                        color: KrishokColors.textLight,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════════
// SENSOR TREND CARD — 5-Day History
// ════════════════════════════════════════════════════════════════════════════════

class _SensorTrendCard extends StatelessWidget {
  final List<DailySensorSnapshot> history;
  const _SensorTrendCard({required this.history});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: KrishokColors.cardWhite,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
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
                width: 3,
                height: 16,
                decoration: BoxDecoration(
                  color: KrishokColors.primaryGreen,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                context.s.sensorTrend,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: KrishokColors.textMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          if (history.isEmpty)
            _EmptyTrendState(message: context.s.noSensorHistory)
          else ...[
            SizedBox(
              height: 118,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: history.length,
                itemBuilder: (_, i) {
                  // history[0] = most recent; display oldest→newest left→right
                  final snap = history[history.length - 1 - i];
                  return _DayCard(snapshot: snap);
                },
              ),
            ),
            if (history.length >= 2) ...[
              const SizedBox(height: 20),
              SizedBox(
                height: 90,
                child: CustomPaint(
                  size: Size.infinite,
                  painter: _NPKLinePainter(
                    history: history.reversed.toList(),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _LegendDot(
                    color: KrishokColors.nitrogenColor,
                    label: context.s.nLegend,
                  ),
                  const SizedBox(width: 16),
                  _LegendDot(
                    color: KrishokColors.phosphorusColor,
                    label: context.s.pLegend,
                  ),
                  const SizedBox(width: 16),
                  _LegendDot(
                    color: KrishokColors.potassiumLow,
                    label: context.s.kLegend,
                  ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _DayCard extends StatelessWidget {
  final DailySensorSnapshot snapshot;
  const _DayCard({required this.snapshot});

  bool get _isToday {
    final now = DateTime.now();
    return snapshot.date.year == now.year &&
        snapshot.date.month == now.month &&
        snapshot.date.day == now.day;
  }

  Color get _moistureColor {
    if (snapshot.moisture < 30) return Colors.orange;
    if (snapshot.moisture < 65) return KrishokColors.primaryGreen;
    return Colors.blue;
  }

  @override
  Widget build(BuildContext context) {
    final dayName = DateFormat('EEE').format(snapshot.date);
    final dateLabel = DateFormat('d MMM').format(snapshot.date);
    final isToday = _isToday;
    final bg = isToday ? KrishokColors.primaryGreen : KrishokColors.surfaceGray;
    final textPrimary = isToday ? Colors.white : KrishokColors.textDark;
    final textSecondary =
        isToday ? Colors.white70 : KrishokColors.textMedium;
    final barBg = isToday
        ? Colors.white.withValues(alpha: 0.25)
        : KrishokColors.background;

    return Container(
      width: 88,
      margin: const EdgeInsets.only(right: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(18),
        boxShadow: isToday
            ? [
                BoxShadow(
                  color:
                      KrishokColors.primaryGreen.withValues(alpha: 0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                )
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            dayName,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: textPrimary,
            ),
          ),
          Text(
            dateLabel,
            style: TextStyle(fontSize: 10, color: textSecondary),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.thermostat_rounded,
                  size: 12,
                  color: isToday
                      ? Colors.white70
                      : KrishokColors.textLight),
              const SizedBox(width: 2),
              Text(
                '${snapshot.temp.toStringAsFixed(0)}°',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (snapshot.moisture / 100).clamp(0.0, 1.0),
              backgroundColor: barBg,
              color: isToday ? Colors.white : _moistureColor,
              minHeight: 5,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            '${snapshot.moisture.toStringAsFixed(0)}%',
            style: TextStyle(fontSize: 10, color: textSecondary),
          ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            color: KrishokColors.textLight,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _EmptyTrendState extends StatelessWidget {
  final String message;
  const _EmptyTrendState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Column(
        children: [
          Icon(Icons.show_chart_rounded,
              size: 32,
              color: KrishokColors.textLight.withValues(alpha: 0.5)),
          const SizedBox(height: 10),
          Text(
            message,
            style: const TextStyle(
              fontSize: 13,
              color: KrishokColors.textLight,
            ),
          ),
        ],
      ),
    );
  }
}

class _NPKLinePainter extends CustomPainter {
  final List<DailySensorSnapshot> history; // oldest → newest

  _NPKLinePainter({required this.history});

  @override
  void paint(Canvas canvas, Size size) {
    if (history.length < 2) return;

    final gridPaint = Paint()
      ..color = KrishokColors.surfaceGray
      ..strokeWidth = 1;
    for (int i = 0; i <= 3; i++) {
      final y = size.height * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    _drawLine(canvas, size,
        history.map((d) => d.n.toDouble()).toList(), KrishokColors.nitrogenColor);
    _drawLine(canvas, size,
        history.map((d) => d.p.toDouble()).toList(), KrishokColors.phosphorusColor);
    _drawLine(canvas, size,
        history.map((d) => d.k.toDouble()).toList(), KrishokColors.potassiumLow);
  }

  void _drawLine(Canvas canvas, Size size, List<double> values, Color color) {
    const maxVal = 100.0;
    final step = size.width / (values.length - 1);

    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    for (int i = 0; i < values.length; i++) {
      final x = step * i;
      final y =
          size.height - (values[i] / maxVal * size.height * 0.88).clamp(0.0, size.height);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        final prevX = step * (i - 1);
        final prevY = size.height -
            (values[i - 1] / maxVal * size.height * 0.88)
                .clamp(0.0, size.height);
        final cx = (prevX + x) / 2;
        path.cubicTo(cx, prevY, cx, y, x, y);
      }
    }
    canvas.drawPath(path, linePaint);

    final dotPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final dotBorder = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    for (int i = 0; i < values.length; i++) {
      final x = step * i;
      final y =
          size.height - (values[i] / maxVal * size.height * 0.88).clamp(0.0, size.height);
      canvas.drawCircle(Offset(x, y), 3.5, dotPaint);
      canvas.drawCircle(Offset(x, y), 3.5, dotBorder);
    }
  }

  @override
  bool shouldRepaint(covariant _NPKLinePainter old) =>
      old.history != history;
}
