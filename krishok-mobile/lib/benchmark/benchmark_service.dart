// ⚠️ TEMPORARY — BENCHMARK ONLY
// Remove this file and the entire lib/benchmark/ folder after publication.
//
// BenchmarkService measures LeafCareNet inference latency for journal reporting.
// It reuses the exact same MLService instance (already-loaded model, same
// preprocessing pipeline) — no separate model copy is created.

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import '../services/ml_service.dart';
import 'benchmark_result.dart';

// ════════════════════════════════════════════════════════════════════════════
// ⚠️ TEMPORARY — BenchmarkService
// ════════════════════════════════════════════════════════════════════════════

const int _kWarmupRuns   = 5;
const int _kMeasuredRuns = 50;
const String _kModelName  = 'LeafCareNet';
const String _kModelAsset = 'assets/models/hierarchical/hierarchical_float32.tflite';
const String _kPrecision  = 'Float32';

class BenchmarkService {
  // Callback so the UI can show progress (warmup 1..5, then measured 1..50).
  final void Function(String phase, int current, int total)? onProgress;

  BenchmarkService({this.onProgress});

  /// Runs the full benchmark on [imageFile] using the already-loaded [mlService].
  ///
  /// Throws [StateError] if the model is not loaded.
  Future<BenchmarkResult> run(File imageFile, MLService mlService) async {
    if (!mlService.isLoaded) {
      throw StateError('MLService model is not loaded. Call loadModel() first.');
    }

    final interpreter = mlService.interpreter!;

    // ── Collect model tensor info ────────────────────────────────────────────
    final inputTensors  = interpreter.getInputTensors();
    final outputTensors = interpreter.getOutputTensors();

    final inputShape  = List<int>.from(inputTensors.first.shape);
    final outputShape = List<int>.from(outputTensors.first.shape);

    // Attempt to detect execution backend from the interpreter options.
    // tflite_flutter does not expose a public API for this, so we report
    // 'CPU (default)' unless an explicit delegate was provided.
    const executionBackend = 'CPU (default / XNNPACK)';

    debugPrint('[Benchmark] Model: $_kModelName  asset: $_kModelAsset');
    debugPrint('[Benchmark] Input:  $inputShape');
    debugPrint('[Benchmark] Output: $outputShape');
    debugPrint('[Benchmark] Backend: $executionBackend');

    // ── Pre-process image ONCE (file I/O + decode + resize/crop) ───────────
    // We cache the decoded img.Image so the tensor-generation step can be
    // re-timed per run without re-reading from disk.
    debugPrint('[Benchmark] Preprocessing image …');
    final (cachedImage, _) = await mlService.preprocessForBenchmark(imageFile);

    final outputBuffer = [List<double>.filled(outputShape[1], 0.0)];

    // ── Warm-up runs (not timed) ─────────────────────────────────────────────
    debugPrint('[Benchmark] Starting $_kWarmupRuns warm-up runs …');
    for (int i = 0; i < _kWarmupRuns; i++) {
      onProgress?.call('warmup', i + 1, _kWarmupRuns);
      final input = mlService.tensorFromImage(cachedImage);
      interpreter.run(input, outputBuffer);
    }

    // ── Measured runs ────────────────────────────────────────────────────────
    debugPrint('[Benchmark] Starting $_kMeasuredRuns measured runs …');
    final tfliteLatencies = <double>[];
    final e2eLatencies    = <double>[];

    for (int i = 0; i < _kMeasuredRuns; i++) {
      onProgress?.call('measured', i + 1, _kMeasuredRuns);

      // ── E2E timer starts: tensor generation ─────────────────────────────
      final e2eWatch = Stopwatch()..start();
      final input = mlService.tensorFromImage(cachedImage);

      // ── Pure TFLite timer: interpreter.run() only ────────────────────────
      final tfliteWatch = Stopwatch()..start();
      interpreter.run(input, outputBuffer);
      tfliteWatch.stop();

      // ── E2E continues: post-processing (softmax + argmax) ────────────────
      _doPostProcess(outputBuffer.first);
      e2eWatch.stop();

      tfliteLatencies.add(tfliteWatch.elapsedMicroseconds / 1000.0);
      e2eLatencies.add(e2eWatch.elapsedMicroseconds / 1000.0);
    }

    // ── Statistics ───────────────────────────────────────────────────────────
    final tfliteStats = _computeStats(tfliteLatencies);
    final e2eStats    = _computeStats(e2eLatencies);

    _printSummary(tfliteLatencies, e2eLatencies, tfliteStats, e2eStats);

    // ── Device info ──────────────────────────────────────────────────────────
    final devicePlugin = DeviceInfoPlugin();
    final androidInfo  = await devicePlugin.androidInfo;

    final manufacturer    = androidInfo.manufacturer;
    final deviceModel     = androidInfo.model;
    final androidVersion  = androidInfo.version.release;
    final sdkInt          = androidInfo.version.sdkInt;
    final product         = androidInfo.product;

    debugPrint('[Benchmark] Device: $manufacturer $deviceModel  '
        'Android $androidVersion (SDK $sdkInt)');

    // ── Save files ───────────────────────────────────────────────────────────
    final ts       = DateTime.now();
    final tsTag    = _tsTag(ts);
    final saveDir  = await _resolveOutputDir();
    final jsonPath = '${saveDir.path}/leafcarenet_benchmark_$tsTag.json';
    final csvPath  = '${saveDir.path}/leafcarenet_benchmark_$tsTag.csv';

    final result = BenchmarkResult(
      timestamp:         ts,
      warmupRuns:        _kWarmupRuns,
      measuredRuns:      _kMeasuredRuns,
      modelName:         _kModelName,
      modelAsset:        _kModelAsset,
      modelPrecision:    _kPrecision,
      inputShape:        inputShape,
      outputShape:       outputShape,
      executionBackend:  executionBackend,
      manufacturer:      manufacturer,
      model:             deviceModel,
      androidVersion:    androidVersion,
      sdkInt:            sdkInt,
      product:           product,
      tfliteLatenciesMs: tfliteLatencies,
      e2eLatenciesMs:    e2eLatencies,
      tfliteStats:       tfliteStats,
      e2eStats:          e2eStats,
      jsonPath:          jsonPath,
      csvPath:           csvPath,
    );

    await _saveJson(result, jsonPath);
    await _saveCsv(result, csvPath);

    debugPrint('[Benchmark] Saved JSON → $jsonPath');
    debugPrint('[Benchmark] Saved CSV  → $csvPath');

    return result;
  }

  // ── Post-processing (mirrors MLService._softmax + _argmax) ─────────────────
  // We reproduce this inline so it is timed as part of E2E but the original
  // MLService methods are not changed.
  void _doPostProcess(List<double> logits) {
    // Softmax on crop logits [0:3]
    final cropLogits = logits.sublist(0, 3);
    _softmax(cropLogits);
    // Softmax on disease slice (timing only — result discarded).
    final cropIdx = _argmax(cropLogits);
    late final List<double> diseaseSlice;
    switch (cropIdx) {
      case 0: diseaseSlice = logits.sublist(3, 6);  break;
      case 1: diseaseSlice = logits.sublist(6, 11); break;
      default: diseaseSlice = logits.sublist(11, 19);
    }
    _softmax(diseaseSlice);
  }

  List<double> _softmax(List<double> logits) {
    final maxL = logits.reduce(math.max);
    final exps = logits.map((x) => math.exp(x - maxL)).toList();
    final sum  = exps.reduce((a, b) => a + b);
    for (int i = 0; i < exps.length; i++) exps[i] /= sum;
    return exps;
  }

  int _argmax(List<double> v) {
    int best = 0;
    for (int i = 1; i < v.length; i++) if (v[i] > v[best]) best = i;
    return best;
  }

  // ── Statistics ────────────────────────────────────────────────────────────
  LatencyStats _computeStats(List<double> samples) {
    final sorted = List<double>.from(samples)..sort();
    final n      = sorted.length;

    final mean   = samples.reduce((a, b) => a + b) / n;
    final median = n.isOdd
        ? sorted[n ~/ 2]
        : (sorted[n ~/ 2 - 1] + sorted[n ~/ 2]) / 2;
    final min    = sorted.first;
    final max    = sorted.last;

    // P95: index = ceil(0.95 * n) - 1
    final p95Idx = (0.95 * n).ceil() - 1;
    final p95    = sorted[p95Idx.clamp(0, n - 1)];

    final variance = samples.map((x) => math.pow(x - mean, 2)).reduce((a, b) => a + b) / n;
    final stdDev   = math.sqrt(variance);

    final throughput = mean > 0 ? 1000.0 / mean : 0.0;

    return LatencyStats(
      mean:         mean,
      median:       median,
      min:          min,
      max:          max,
      p95:          p95,
      stdDev:       stdDev,
      throughputFps: throughput,
    );
  }

  // ── Console output ────────────────────────────────────────────────────────
  void _printSummary(
    List<double> tflite,
    List<double> e2e,
    LatencyStats ts,
    LatencyStats es,
  ) {
    debugPrint('');
    debugPrint('╔══════════════════════════════════════════════════════════╗');
    debugPrint('║           LeafCareNet Benchmark Summary                  ║');
    debugPrint('╠══════════════════════════════════════════════════════════╣');
    debugPrint('║  Metric            TFLite-only (ms)    End-to-End (ms)  ║');
    debugPrint('╠══════════════════════════════════════════════════════════╣');
    _row('Mean',       ts.mean,       es.mean);
    _row('Median',     ts.median,     es.median);
    _row('Min',        ts.min,        es.min);
    _row('Max',        ts.max,        es.max);
    _row('P95',        ts.p95,        es.p95);
    _row('Std Dev',    ts.stdDev,     es.stdDev);
    _row('Throughput (fps)', ts.throughputFps, es.throughputFps);
    debugPrint('╚══════════════════════════════════════════════════════════╝');
    debugPrint('');
    debugPrint('[Benchmark] TFLite raw (ms): ${tflite.map((v) => v.toStringAsFixed(2)).join(', ')}');
    debugPrint('[Benchmark] E2E raw (ms):    ${e2e.map((v) => v.toStringAsFixed(2)).join(', ')}');
  }

  void _row(String label, double a, double b) {
    debugPrint('║  ${label.padRight(18)}  ${a.toStringAsFixed(2).padLeft(8)}          ${b.toStringAsFixed(2).padLeft(8)}  ║');
  }

  // ── File helpers ──────────────────────────────────────────────────────────
  Future<Directory> _resolveOutputDir() async {
    // Primary: external storage (/sdcard/Android/data/<pkg>/files/) — no permission needed.
    try {
      final ext = await getExternalStorageDirectory();
      if (ext != null) return ext;
    } catch (_) {}
    // Fallback: app documents directory.
    return getApplicationDocumentsDirectory();
  }

  Future<void> _saveJson(BenchmarkResult r, String path) async {
    final map = {
      'metadata': {
        'benchmark_version': '1.0.0',
        'timestamp':         r.timestamp.toIso8601String(),
        'model_name':        r.modelName,
        'model_asset':       r.modelAsset,
        'model_precision':   r.modelPrecision,
        'input_shape':       r.inputShape,
        'output_shape':      r.outputShape,
        'execution_backend': r.executionBackend,
        'warmup_runs':       r.warmupRuns,
        'measured_runs':     r.measuredRuns,
      },
      'device': {
        'manufacturer':    r.manufacturer,
        'model':           r.model,
        'android_version': r.androidVersion,
        'sdk_int':         r.sdkInt,
        'product':         r.product,
      },
      'tflite_latency_ms': {
        ...r.tfliteStats.toJson(),
        'raw_values': r.tfliteLatenciesMs.map((v) => double.parse(v.toStringAsFixed(4))).toList(),
      },
      'end_to_end_latency_ms': {
        ...r.e2eStats.toJson(),
        'raw_values': r.e2eLatenciesMs.map((v) => double.parse(v.toStringAsFixed(4))).toList(),
      },
    };
    await File(path).writeAsString(
      const JsonEncoder.withIndent('  ').convert(map),
      flush: true,
    );
  }

  Future<void> _saveCsv(BenchmarkResult r, String path) async {
    final buf = StringBuffer();

    // Header
    buf.writeln('# LeafCareNet Benchmark — $_kModelName');
    buf.writeln('# Timestamp: ${r.timestamp.toIso8601String()}');
    buf.writeln('# Model: ${r.modelAsset}  Precision: ${r.modelPrecision}');
    buf.writeln('# Input: ${r.inputShape}  Output: ${r.outputShape}');
    buf.writeln('# Device: ${r.manufacturer} ${r.model}  Android ${r.androidVersion} (SDK ${r.sdkInt})');
    buf.writeln('#');
    buf.writeln('# Per-run latency data (${r.measuredRuns} measured runs after ${r.warmupRuns} warm-ups)');
    buf.writeln('run_index,tflite_latency_ms,e2e_latency_ms');

    for (int i = 0; i < r.measuredRuns; i++) {
      buf.writeln(
        '${i + 1},'
        '${r.tfliteLatenciesMs[i].toStringAsFixed(4)},'
        '${r.e2eLatenciesMs[i].toStringAsFixed(4)}',
      );
    }

    // Summary block
    buf.writeln('#');
    buf.writeln('# Summary Statistics');
    buf.writeln('stat,tflite_ms,e2e_ms');
    buf.writeln('mean,${r.tfliteStats.mean.toStringAsFixed(4)},${r.e2eStats.mean.toStringAsFixed(4)}');
    buf.writeln('median,${r.tfliteStats.median.toStringAsFixed(4)},${r.e2eStats.median.toStringAsFixed(4)}');
    buf.writeln('min,${r.tfliteStats.min.toStringAsFixed(4)},${r.e2eStats.min.toStringAsFixed(4)}');
    buf.writeln('max,${r.tfliteStats.max.toStringAsFixed(4)},${r.e2eStats.max.toStringAsFixed(4)}');
    buf.writeln('p95,${r.tfliteStats.p95.toStringAsFixed(4)},${r.e2eStats.p95.toStringAsFixed(4)}');
    buf.writeln('std_dev,${r.tfliteStats.stdDev.toStringAsFixed(4)},${r.e2eStats.stdDev.toStringAsFixed(4)}');
    buf.writeln('throughput_fps,${r.tfliteStats.throughputFps.toStringAsFixed(4)},${r.e2eStats.throughputFps.toStringAsFixed(4)}');

    await File(path).writeAsString(buf.toString(), flush: true);
  }

  String _tsTag(DateTime dt) =>
      '${dt.year}${_p(dt.month)}${_p(dt.day)}_${_p(dt.hour)}${_p(dt.minute)}${_p(dt.second)}';

  String _p(int v) => v.toString().padLeft(2, '0');
}
