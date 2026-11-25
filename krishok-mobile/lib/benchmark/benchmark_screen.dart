// ⚠️ TEMPORARY — BENCHMARK ONLY
// Remove this file and the entire lib/benchmark/ folder after publication.
//
// BenchmarkScreen: A standalone screen for measuring LeafCareNet latency.
// Navigate to it via: Navigator.push(context, MaterialPageRoute(builder: (_) => const BenchmarkScreen()))

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../services/ml_service.dart';
import '../theme/app_theme.dart';
import 'benchmark_result.dart';
import 'benchmark_service.dart';

// ════════════════════════════════════════════════════════════════════════════
// ⚠️ TEMPORARY — BenchmarkScreen
// ════════════════════════════════════════════════════════════════════════════

class BenchmarkScreen extends StatefulWidget {
  const BenchmarkScreen({super.key});

  @override
  State<BenchmarkScreen> createState() => _BenchmarkScreenState();
}

enum _BenchmarkPhase { idle, loadingModel, preprocessing, warmup, measuring, done, error }

class _BenchmarkScreenState extends State<BenchmarkScreen> {
  final MLService      _mlService      = MLService();
  final BenchmarkService _benchmarkService = BenchmarkService();
  final ImagePicker    _picker         = ImagePicker();

  File?             _selectedImage;
  _BenchmarkPhase   _phase            = _BenchmarkPhase.idle;
  String            _progressLabel    = '';
  double            _progressValue    = 0.0;
  BenchmarkResult?  _result;
  String?           _errorMessage;

  @override
  void dispose() {
    _mlService.dispose();
    super.dispose();
  }

  // ── Image Selection ──────────────────────────────────────────────────────

  Future<void> _pickImage() async {
    try {
      final xFile = await _picker.pickImage(source: ImageSource.gallery);
      if (xFile == null) return;
      setState(() {
        _selectedImage = File(xFile.path);
        _result        = null;
        _errorMessage  = null;
        _phase         = _BenchmarkPhase.idle;
      });
    } catch (e) {
      _setError('Could not open image: $e');
    }
  }

  // ── Benchmark Execution ──────────────────────────────────────────────────

  Future<void> _runBenchmark() async {
    if (_selectedImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a leaf image first.')),
      );
      return;
    }

    setState(() {
      _phase         = _BenchmarkPhase.loadingModel;
      _progressLabel = 'Loading LeafCareNet model…';
      _progressValue = 0.0;
      _errorMessage  = null;
      _result        = null;
    });

    try {
      // Load model if not already loaded.
      await _mlService.loadModel();

      setState(() {
        _phase         = _BenchmarkPhase.preprocessing;
        _progressLabel = 'Preprocessing image…';
        _progressValue = 0.02;
      });

      final service = BenchmarkService(
        onProgress: (phase, current, total) {
          if (!mounted) return;
          setState(() {
            if (phase == 'warmup') {
              _phase         = _BenchmarkPhase.warmup;
              _progressLabel = 'Warm-up run $current / $total…';
              _progressValue = 0.05 + (current / total) * 0.10;
            } else {
              _phase         = _BenchmarkPhase.measuring;
              _progressLabel = 'Measuring run $current / $total…';
              _progressValue = 0.15 + (current / total) * 0.85;
            }
          });
        },
      );

      final result = await service.run(_selectedImage!, _mlService);

      if (mounted) {
        setState(() {
          _result        = result;
          _phase         = _BenchmarkPhase.done;
          _progressValue = 1.0;
          _progressLabel = 'Benchmark complete!';
        });
      }
    } on MLServiceException catch (e) {
      _setError('ML error: ${e.message}');
    } catch (e) {
      _setError('Unexpected error: $e');
    }
  }

  void _setError(String msg) {
    if (!mounted) return;
    setState(() {
      _phase        = _BenchmarkPhase.error;
      _errorMessage = msg;
    });
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KrishokColors.background,
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.science_rounded, color: Color(0xFF7C5CBF), size: 22),
            SizedBox(width: 8),
            Text('LeafCareNet Benchmark'),
          ],
        ),
        backgroundColor: KrishokColors.cardWhite,
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _TemporaryBanner(),
            const SizedBox(height: 16),
            _ImageSection(
              image: _selectedImage,
              onPick: _pickImage,
              enabled: _phase == _BenchmarkPhase.idle || _phase == _BenchmarkPhase.done || _phase == _BenchmarkPhase.error,
            ),
            const SizedBox(height: 16),
            _RunButton(
              onRun: _runBenchmark,
              enabled: _selectedImage != null &&
                  _phase != _BenchmarkPhase.loadingModel &&
                  _phase != _BenchmarkPhase.preprocessing &&
                  _phase != _BenchmarkPhase.warmup &&
                  _phase != _BenchmarkPhase.measuring,
            ),
            if (_phase != _BenchmarkPhase.idle) ...[
              const SizedBox(height: 20),
              _ProgressCard(label: _progressLabel, value: _progressValue, phase: _phase),
            ],
            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              _ErrorCard(message: _errorMessage!),
            ],
            if (_result != null) ...[
              const SizedBox(height: 20),
              _ModelInfoCard(result: _result!),
              const SizedBox(height: 12),
              _DeviceInfoCard(result: _result!),
              const SizedBox(height: 12),
              _LatencyCard(
                title: '⚡ TFLite Inference Latency',
                subtitle: 'interpreter.run() only — pure model execution time',
                color: const Color(0xFF2E7D32),
                stats: _result!.tfliteStats,
              ),
              const SizedBox(height: 12),
              _LatencyCard(
                title: '🔄 End-to-End Latency',
                subtitle: 'Tensor generation + inference + post-processing',
                color: const Color(0xFF1565C0),
                stats: _result!.e2eStats,
              ),
              const SizedBox(height: 12),
              _FileSaveCard(result: _result!),
              const SizedBox(height: 12),
              _RawValuesCard(result: _result!),
            ],
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Sub-widgets
// ════════════════════════════════════════════════════════════════════════════

class _TemporaryBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFB300), width: 1),
      ),
      child: const Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: Color(0xFFE65100), size: 18),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'TEMPORARY — For journal evaluation only.\nRemove lib/benchmark/ after publication.',
              style: TextStyle(fontSize: 12, color: Color(0xFF5D4037), height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _ImageSection extends StatelessWidget {
  final File? image;
  final VoidCallback onPick;
  final bool enabled;

  const _ImageSection({required this.image, required this.onPick, required this.enabled});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onPick : null,
      child: Container(
        height: 180,
        width: double.infinity,
        decoration: BoxDecoration(
          color: KrishokColors.cardWhite,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFD8D0EA), width: 1.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: image != null
            ? Stack(
                fit: StackFit.expand,
                children: [
                  Image.file(image!, fit: BoxFit.cover),
                  Positioned(
                    bottom: 8, right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(children: [
                        Icon(Icons.swap_horiz, color: Colors.white, size: 14),
                        SizedBox(width: 4),
                        Text('Change', style: TextStyle(color: Colors.white, fontSize: 12)),
                      ]),
                    ),
                  ),
                ],
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEDE7F6),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Icon(Icons.add_photo_alternate_rounded,
                        size: 38, color: Color(0xFF7C5CBF)),
                  ),
                  const SizedBox(height: 12),
                  const Text('Tap to select a leaf image',
                      style: TextStyle(fontWeight: FontWeight.w600, color: KrishokColors.textDark)),
                  const SizedBox(height: 4),
                  const Text('Use a real leaf image for valid results',
                      style: TextStyle(fontSize: 12, color: KrishokColors.textLight)),
                ],
              ),
      ),
    );
  }
}

class _RunButton extends StatelessWidget {
  final VoidCallback onRun;
  final bool enabled;

  const _RunButton({required this.onRun, required this.enabled});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: enabled ? onRun : null,
        icon: const Icon(Icons.play_circle_fill_rounded, size: 20),
        label: const Text('Run Benchmark  (5 warm-up + 50 measured)',
            style: TextStyle(fontWeight: FontWeight.w700)),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF7C5CBF),
          foregroundColor: Colors.white,
          disabledBackgroundColor: const Color(0xFFD1C4E9),
          disabledForegroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
    );
  }
}

class _ProgressCard extends StatelessWidget {
  final String label;
  final double value;
  final _BenchmarkPhase phase;

  const _ProgressCard({required this.label, required this.value, required this.phase});

  @override
  Widget build(BuildContext context) {
    final isDone  = phase == _BenchmarkPhase.done;
    final isError = phase == _BenchmarkPhase.error;
    final color   = isError ? Colors.red : isDone ? KrishokColors.successGreen : const Color(0xFF7C5CBF);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: KrishokColors.cardWhite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            if (isDone)
              const Icon(Icons.check_circle_rounded, color: KrishokColors.successGreen, size: 18)
            else if (isError)
              const Icon(Icons.error_rounded, color: Colors.red, size: 18)
            else
              SizedBox(
                width: 16, height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: color),
              ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(label, style: TextStyle(fontWeight: FontWeight.w600, color: color)),
            ),
          ]),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: value,
              minHeight: 8,
              backgroundColor: color.withValues(alpha: 0.1),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          const SizedBox(height: 4),
          Text('${(value * 100).toStringAsFixed(0)}%',
              style: TextStyle(fontSize: 11, color: color.withValues(alpha: 0.7))),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;
  const _ErrorCard({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFEBEE),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(children: [
        const Icon(Icons.error_outline_rounded, color: Colors.red, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(message, style: const TextStyle(color: Colors.red, fontSize: 13))),
      ]),
    );
  }
}

class _ModelInfoCard extends StatelessWidget {
  final BenchmarkResult result;
  const _ModelInfoCard({required this.result});

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: '🤖 Model Information',
      color: const Color(0xFF2E7D32),
      children: [
        _InfoRow('Name',     result.modelName),
        _InfoRow('Asset',    result.modelAsset.split('/').last),
        _InfoRow('Precision', result.modelPrecision),
        _InfoRow('Input Shape',  result.inputShape.toString()),
        _InfoRow('Output Shape', result.outputShape.toString()),
        _InfoRow('Backend',  result.executionBackend),
        _InfoRow('Warm-ups',  '${result.warmupRuns}'),
        _InfoRow('Measured',  '${result.measuredRuns} runs'),
      ],
    );
  }
}

class _DeviceInfoCard extends StatelessWidget {
  final BenchmarkResult result;
  const _DeviceInfoCard({required this.result});

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: '📱 Device Information',
      color: const Color(0xFF1565C0),
      children: [
        _InfoRow('Manufacturer', result.manufacturer),
        _InfoRow('Model',        result.model),
        _InfoRow('Android',      result.androidVersion),
        _InfoRow('SDK Level',    result.sdkInt.toString()),
        _InfoRow('Product',      result.product),
      ],
    );
  }
}

class _LatencyCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Color color;
  final LatencyStats stats;

  const _LatencyCard({
    required this.title,
    required this.subtitle,
    required this.color,
    required this.stats,
  });

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: title,
      subtitle: subtitle,
      color: color,
      children: [
        _StatRow('Runs',       '50'),
        _StatRow('Mean',       '${stats.mean.toStringAsFixed(2)} ms'),
        _StatRow('Median',     '${stats.median.toStringAsFixed(2)} ms'),
        _StatRow('Min',        '${stats.min.toStringAsFixed(2)} ms'),
        _StatRow('Max',        '${stats.max.toStringAsFixed(2)} ms'),
        _StatRow('P95',        '${stats.p95.toStringAsFixed(2)} ms'),
        _StatRow('Std Dev',    '${stats.stdDev.toStringAsFixed(2)} ms'),
        _StatRow('Throughput', '${stats.throughputFps.toStringAsFixed(1)} FPS'),
      ],
    );
  }
}

class _FileSaveCard extends StatelessWidget {
  final BenchmarkResult result;
  const _FileSaveCard({required this.result});

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: '💾 Saved Files',
      color: const Color(0xFFE65100),
      children: [
        _PathRow('JSON', result.jsonPath),
        const SizedBox(height: 6),
        _PathRow('CSV',  result.csvPath),
      ],
    );
  }
}

class _PathRow extends StatelessWidget {
  final String type;
  final String path;
  const _PathRow(this.type, this.path);

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xFFE65100),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(type, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(path, style: const TextStyle(fontSize: 11, color: KrishokColors.textMedium, height: 1.4)),
        ),
        IconButton(
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          icon: const Icon(Icons.copy_rounded, size: 16, color: KrishokColors.textLight),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: path));
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('$type path copied'),
                duration: const Duration(seconds: 2),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                margin: const EdgeInsets.all(16),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _RawValuesCard extends StatelessWidget {
  final BenchmarkResult result;
  const _RawValuesCard({required this.result});

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: '📊 Raw Latency Values (all 50 runs)',
      color: KrishokColors.textMedium,
      children: [
        const Text('TFLite (ms):', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        _RawList(values: result.tfliteLatenciesMs),
        const SizedBox(height: 12),
        const Text('End-to-End (ms):', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        _RawList(values: result.e2eLatenciesMs),
      ],
    );
  }
}

class _RawList extends StatelessWidget {
  final List<double> values;
  const _RawList({required this.values});

  @override
  Widget build(BuildContext context) {
    final text = values.asMap().entries
        .map((e) => '${e.key + 1}: ${e.value.toStringAsFixed(2)}')
        .join('  ');
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: KrishokColors.surfaceGray,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text, style: const TextStyle(fontSize: 10.5, color: KrishokColors.textMedium, height: 1.6, fontFamily: 'monospace')),
    );
  }
}

// ── Shared layout helpers ─────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Color color;
  final List<Widget> children;

  const _SectionCard({
    required this.title,
    this.subtitle,
    required this.color,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: KrishokColors.cardWhite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: color)),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(subtitle!, style: const TextStyle(fontSize: 11, color: KrishokColors.textLight)),
          ],
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label,
                style: const TextStyle(fontSize: 12, color: KrishokColors.textLight, fontWeight: FontWeight.w500)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(fontSize: 12, color: KrishokColors.textDark, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  final String label;
  final String value;
  const _StatRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13, color: KrishokColors.textMedium))),
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: KrishokColors.textDark)),
        ],
      ),
    );
  }
}
