// ⚠️ TEMPORARY — BENCHMARK ONLY
// This file exists solely for journal deployment evaluation of LeafCareNet.
// Remove this file and the entire lib/benchmark/ folder after publication.

/// Holds one complete benchmark run for LeafCareNet.
class BenchmarkResult {
  // ── Run metadata ──────────────────────────────────────────────────────────
  final DateTime timestamp;
  final int warmupRuns;
  final int measuredRuns;

  // ── Model info ────────────────────────────────────────────────────────────
  final String modelName;
  final String modelAsset;
  final String modelPrecision;
  final List<int> inputShape;
  final List<int> outputShape;
  final String executionBackend;

  // ── Device info ───────────────────────────────────────────────────────────
  final String manufacturer;
  final String model;
  final String androidVersion;
  final int sdkInt;
  final String product;

  // ── Raw latency samples (ms, double precision) ────────────────────────────
  /// Pure TFLite interpreter.run() latency — 50 values.
  final List<double> tfliteLatenciesMs;

  /// End-to-end latency (tensor + inference + post-processing) — 50 values.
  final List<double> e2eLatenciesMs;

  // ── Computed statistics ───────────────────────────────────────────────────
  final LatencyStats tfliteStats;
  final LatencyStats e2eStats;

  // ── File paths ────────────────────────────────────────────────────────────
  final String jsonPath;
  final String csvPath;

  const BenchmarkResult({
    required this.timestamp,
    required this.warmupRuns,
    required this.measuredRuns,
    required this.modelName,
    required this.modelAsset,
    required this.modelPrecision,
    required this.inputShape,
    required this.outputShape,
    required this.executionBackend,
    required this.manufacturer,
    required this.model,
    required this.androidVersion,
    required this.sdkInt,
    required this.product,
    required this.tfliteLatenciesMs,
    required this.e2eLatenciesMs,
    required this.tfliteStats,
    required this.e2eStats,
    required this.jsonPath,
    required this.csvPath,
  });
}

/// Summary statistics for one latency set.
class LatencyStats {
  final double mean;
  final double median;
  final double min;
  final double max;
  final double p95;
  final double stdDev;
  final double throughputFps;

  const LatencyStats({
    required this.mean,
    required this.median,
    required this.min,
    required this.max,
    required this.p95,
    required this.stdDev,
    required this.throughputFps,
  });

  Map<String, dynamic> toJson() => {
        'mean_ms': _r(mean),
        'median_ms': _r(median),
        'min_ms': _r(min),
        'max_ms': _r(max),
        'p95_ms': _r(p95),
        'std_dev_ms': _r(stdDev),
        'throughput_fps': _r(throughputFps),
      };

  static double _r(double v) => double.parse(v.toStringAsFixed(4));
}
