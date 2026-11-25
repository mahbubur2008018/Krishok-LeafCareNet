import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

// ════════════════════════════════════════════════════════════════════════════════
// FINAL LEAFCARENET — single shared MobileNetV2 backbone, one 19-logit output.
//
// Input:
//   [1, 224, 224, 3], float32, RGB values in 0..255
//
// IMPORTANT:
//   ImageNet /255 + mean/std normalization is EMBEDDED inside the TFLite model.
//   Do not normalize again in Dart.
//
// Output layout:
//   0:3    crop logits [potato, rice, tomato]
//   3:6    potato disease logits (3)
//   6:11   rice disease logits (5)
//   11:19  tomato disease logits (8)
//
// Crop argmax selects the corresponding disease slice.
// ════════════════════════════════════════════════════════════════════════════════

const String _kLeafCareNetPath =
    'assets/models/hierarchical/hierarchical_float32.tflite';
const String _kClassNamesPath =
    'assets/models/hierarchical/class_names.json';

const List<String> _kCrops = ['potato', 'rice', 'tomato'];

const int _kExpectedInputH = 224;
const int _kExpectedInputW = 224;
const int _kExpectedOutputLength = 19;

// timm evaluation transform uses crop_pct=0.875, therefore
// resize shorter side to 224 / 0.875 = 256, then center-crop 224.
const int _kResizeShortSide = 256;

/// Display-side crop metadata. The active crop is detected by LeafCareNet.
enum KrishokModel {
  potato(
    displayName: 'Potato',
    crop: 'potato',
    labelPrefix: 'Potato',
    emoji: '🥔',
  ),
  rice(
    displayName: 'Rice',
    crop: 'rice',
    labelPrefix: 'Rice',
    emoji: '🌾',
  ),
  tomato(
    displayName: 'Tomato',
    crop: 'tomato',
    labelPrefix: 'Tomato',
    emoji: '🍅',
  );

  const KrishokModel({
    required this.displayName,
    required this.crop,
    required this.labelPrefix,
    required this.emoji,
  });

  final String displayName;
  final String crop;
  final String labelPrefix;
  final String emoji;

  static KrishokModel fromCrop(String crop) =>
      KrishokModel.values.firstWhere((m) => m.crop == crop);
}

class PredictionResult {
  final String label;
  final double confidence;
  final bool isTopResult;

  const PredictionResult({
    required this.label,
    required this.confidence,
    required this.isTopResult,
  });

  /// `Potato___Early_blight` -> `Early Blight`
  String get prettyLabel {
    final parts = label.split('___');
    final disease = parts.length > 1 ? parts.last : parts.first;
    return disease.replaceAll('_', ' ').trim();
  }

  bool get isHealthy => label.toLowerCase().contains('healthy');

  String get confidencePercent =>
      '${(confidence * 100).toStringAsFixed(1)}%';
}

class InferenceResult {
  final KrishokModel crop;
  final double cropConfidence;
  final Map<String, double> cropProbs;
  final List<PredictionResult> diseases;

  const InferenceResult({
    required this.crop,
    required this.cropConfidence,
    required this.cropProbs,
    required this.diseases,
  });

  PredictionResult get topDisease => diseases.first;
}

class MLServiceException implements Exception {
  final String message;
  final String code;

  const MLServiceException(this.message, this.code);

  @override
  String toString() => 'MLServiceException[$code]: $message';
}

class MLService {
  Interpreter? _interpreter;

  int _inputH = _kExpectedInputH;
  int _inputW = _kExpectedInputW;

  Map<String, List<String>> _diseasesPerCrop = {};

  bool get isLoaded => _interpreter != null;

  // ⚠️ TEMPORARY — BENCHMARK ONLY ─────────────────────────────────────────
  // Exposes the raw TFLite interpreter so the benchmark can call
  // interpreter.run() in isolation for pure-inference timing.
  Interpreter? get interpreter => _interpreter;

  /// Pre-processes [imageFile] into the input tensor without running inference.
  /// Returns the decoded [img.Image] (for repeated tensor generation) and
  /// the ready-to-feed tensor.
  ///
  /// Used by the benchmark to cache the decoded image and measure
  /// _imageToTensor latency separately from file I/O.
  Future<(img.Image, List<List<List<List<double>>>>)> preprocessForBenchmark(
    File imageFile,
  ) async {
    final image = await _loadImage(imageFile);
    final tensor = _imageToTensor(image);
    return (image, tensor);
  }

  /// Converts a pre-decoded [img.Image] into the input tensor.
  /// Called repeatedly by the benchmark's E2E timing loop.
  List<List<List<List<double>>>> tensorFromImage(img.Image image) =>
      _imageToTensor(image);
  // ⚠️ END TEMPORARY ────────────────────────────────────────────────────────

  Future<void> loadModel({bool force = false}) async {
    if (!force && isLoaded) {
      debugPrint('[MLService] final LeafCareNet already loaded');
      return;
    }

    _close();

    debugPrint('[MLService] loading $_kLeafCareNetPath');

    try {
      _interpreter = await Interpreter.fromAsset(_kLeafCareNetPath);
    } catch (e) {
      throw MLServiceException(
        'Failed to load model asset "$_kLeafCareNetPath": $e',
        'ASSET_NOT_FOUND',
      );
    }

    _validateTensorContract();
    await _loadClassNames();
  }

  void _validateTensorContract() {
    final inputs = _interpreter!.getInputTensors();
    final outputs = _interpreter!.getOutputTensors();

    if (inputs.length != 1) {
      throw MLServiceException(
        'LeafCareNet must have exactly 1 input tensor; found ${inputs.length}.',
        'INPUT_TENSOR_MISMATCH',
      );
    }

    if (outputs.length != 1) {
      throw MLServiceException(
        'LeafCareNet must have exactly 1 output tensor; found ${outputs.length}. '
        'The old 4-output hierarchical model is not compatible.',
        'OUTPUT_TENSOR_MISMATCH',
      );
    }

    final inShape = inputs.first.shape;
    final outShape = outputs.first.shape;

    debugPrint(
      '[MLService] input name="${inputs.first.name}" '
      'shape=$inShape type=${inputs.first.type}',
    );
    debugPrint(
      '[MLService] output name="${outputs.first.name}" '
      'shape=$outShape type=${outputs.first.type}',
    );

    if (inShape.length != 4 ||
        inShape[0] != 1 ||
        inShape[1] != _kExpectedInputH ||
        inShape[2] != _kExpectedInputW ||
        inShape[3] != 3) {
      throw MLServiceException(
        'Unexpected LeafCareNet input shape $inShape; '
        'expected [1, $_kExpectedInputH, $_kExpectedInputW, 3].',
        'INPUT_SHAPE_MISMATCH',
      );
    }

    if (outShape.length != 2 ||
        outShape[0] != 1 ||
        outShape[1] != _kExpectedOutputLength) {
      throw MLServiceException(
        'Unexpected LeafCareNet output shape $outShape; '
        'expected [1, $_kExpectedOutputLength].',
        'OUTPUT_SHAPE_MISMATCH',
      );
    }

    _inputH = inShape[1];
    _inputW = inShape[2];
  }

  Future<void> _loadClassNames() async {
    final raw = await rootBundle.loadString(_kClassNamesPath);
    final data = jsonDecode(raw) as Map<String, dynamic>;

    final crops = (data['crops'] as List).cast<String>();

    if (!listEquals(crops, _kCrops)) {
      throw MLServiceException(
        'class_names.json crop order $crops != expected $_kCrops',
        'CLASS_NAMES_MISMATCH',
      );
    }

    final diseases = data['diseases'] as Map<String, dynamic>;

    _diseasesPerCrop = {
      for (final crop in _kCrops)
        crop: (diseases[crop] as List).cast<String>(),
    };

    const expectedCounts = {
      'potato': 3,
      'rice': 5,
      'tomato': 8,
    };

    for (final entry in expectedCounts.entries) {
      final actual = _diseasesPerCrop[entry.key]?.length ?? -1;
      if (actual != entry.value) {
        throw MLServiceException(
          '${entry.key} class count $actual != expected ${entry.value}',
          'CLASS_NAMES_MISMATCH',
        );
      }
    }

    debugPrint('[MLService] class names: $_diseasesPerCrop');
  }

  Future<InferenceResult> runInference(File imageFile) async {
    if (!isLoaded) {
      throw const MLServiceException(
        'Model not loaded — call loadModel() first.',
        'MODEL_NOT_LOADED',
      );
    }

    final totalWatch = Stopwatch()..start();

    final image = await _loadImage(imageFile);
    final input = _imageToTensor(image);

    final output = [
      List<double>.filled(_kExpectedOutputLength, 0.0),
    ];

    final invokeWatch = Stopwatch()..start();

    try {
      _interpreter!.run(input, output);
    } catch (e) {
      throw MLServiceException(
        'TFLite inference error: $e',
        'INFERENCE_ERROR',
      );
    } finally {
      invokeWatch.stop();
    }

    totalWatch.stop();

    debugPrint(
      '[MLService] LeafCareNet latency: '
      'invoke=${(invokeWatch.elapsedMicroseconds / 1000.0).toStringAsFixed(2)} ms, '
      'end-to-end=${(totalWatch.elapsedMicroseconds / 1000.0).toStringAsFixed(2)} ms',
    );

    final logits = output.first;

    if (logits.length != _kExpectedOutputLength) {
      throw MLServiceException(
        'Unexpected output length ${logits.length}; '
        'expected $_kExpectedOutputLength.',
        'OUTPUT_LENGTH_MISMATCH',
      );
    }

    // 0:3 -> crop logits
    final cropLogits = logits.sublist(0, 3);
    final cropProbs = _softmax(cropLogits);
    final cropIdx = _argmax(cropProbs);
    final crop = _kCrops[cropIdx];

    // Crop-specific disease slice from the same 19-logit tensor.
    late final List<double> diseaseLogits;

    switch (cropIdx) {
      case 0:
        diseaseLogits = logits.sublist(3, 6);
        break;
      case 1:
        diseaseLogits = logits.sublist(6, 11);
        break;
      case 2:
        diseaseLogits = logits.sublist(11, 19);
        break;
      default:
        throw MLServiceException(
          'Invalid crop index $cropIdx.',
          'ROUTING_ERROR',
        );
    }

    final diseaseProbs = _softmax(diseaseLogits);
    final diseases = _buildResults(crop, diseaseProbs);

    final cropProbsMap = <String, double>{
      for (int i = 0; i < _kCrops.length; i++)
        _kCrops[i]: cropProbs[i],
    };

    return InferenceResult(
      crop: KrishokModel.fromCrop(crop),
      cropConfidence: cropProbs[cropIdx],
      cropProbs: cropProbsMap,
      diseases: diseases,
    );
  }

  Future<img.Image> _loadImage(File file) async {
    if (!await file.exists()) {
      throw const MLServiceException(
        'Image not found.',
        'FILE_NOT_FOUND',
      );
    }

    final bytes = await file.readAsBytes();
    final decoded = img.decodeImage(bytes);

    if (decoded == null) {
      throw const MLServiceException(
        'Failed to decode image.',
        'DECODE_ERROR',
      );
    }

    // Respect EXIF rotation from phone-camera images.
    return img.bakeOrientation(decoded);
  }

  /// Matches the final PyTorch/timm evaluation geometry:
  /// 1) preserve aspect ratio
  /// 2) resize shorter side to 256 using cubic interpolation
  /// 3) center-crop 224x224
  /// 4) feed RGB float values in 0..255
  ///
  /// The TFLite graph performs /255 and ImageNet mean/std normalization
  /// internally, so Dart MUST NOT normalize a second time.
  List<List<List<List<double>>>> _imageToTensor(img.Image image) {
    final srcW = image.width;
    final srcH = image.height;

    if (srcW <= 0 || srcH <= 0) {
      throw const MLServiceException(
        'Invalid decoded image dimensions.',
        'INVALID_IMAGE_SIZE',
      );
    }

    late final int resizedW;
    late final int resizedH;

    if (srcW <= srcH) {
      resizedW = _kResizeShortSide;
      resizedH = (srcH * (_kResizeShortSide / srcW)).round();
    } else {
      resizedH = _kResizeShortSide;
      resizedW = (srcW * (_kResizeShortSide / srcH)).round();
    }

    final resized = img.copyResize(
      image,
      width: resizedW,
      height: resizedH,
      interpolation: img.Interpolation.cubic,
    );

    final cropX = math.max(0, ((resized.width - _inputW) / 2).floor());
    final cropY = math.max(0, ((resized.height - _inputH) / 2).floor());

    final cropped = img.copyCrop(
      resized,
      x: cropX,
      y: cropY,
      width: _inputW,
      height: _inputH,
    );

    return [
      List.generate(_inputH, (y) {
        return List.generate(_inputW, (x) {
          final p = cropped.getPixel(x, y);

          // IMPORTANT: raw RGB 0..255.
          return [
            p.r.toDouble(),
            p.g.toDouble(),
            p.b.toDouble(),
          ];
        });
      }),
    ];
  }

  int _argmax(List<double> values) {
    int best = 0;

    for (int i = 1; i < values.length; i++) {
      if (values[i] > values[best]) best = i;
    }

    return best;
  }

  List<double> _softmax(List<double> logits) {
    final maxLogit = logits.reduce(math.max);
    final exps = logits.map((x) => math.exp(x - maxLogit)).toList();
    final sum = exps.reduce((a, b) => a + b);

    return exps.map((e) => e / sum).toList();
  }

  /// Converts final dataset labels to the UI's existing canonical
  /// triple-underscore keys.
  ///
  /// Examples:
  ///   Potato_Early_blight                  -> Potato___Early_blight
  ///   Tomato_Tomato_YellowLeaf_Curl_Virus -> Tomato___YellowLeaf_Curl_Virus
  ///   Tomato_Tomato_mosaic_virus           -> Tomato___mosaic_virus
  List<PredictionResult> _buildResults(
    String crop,
    List<double> probs,
  ) {
    final names = _diseasesPerCrop[crop]!;

    final indexed = <({int idx, double p})>[
      for (int i = 0; i < probs.length; i++)
        (idx: i, p: probs[i]),
    ]..sort((a, b) => b.p.compareTo(a.p));

    final prefix = KrishokModel.fromCrop(crop).labelPrefix;

    bool first = true;

    return indexed.take(math.min(3, indexed.length)).map((entry) {
      var raw = entry.idx < names.length
          ? names[entry.idx]
          : 'Class ${entry.idx}';

      if (raw.startsWith('${prefix}_') &&
          !raw.startsWith('${prefix}___')) {
        var diseasePart = raw.substring(prefix.length + 1);

        // Final tomato dataset contains two class folder names with a
        // duplicated crop prefix: Tomato_Tomato_...
        if (diseasePart.startsWith('${prefix}_')) {
          diseasePart = diseasePart.substring(prefix.length + 1);
        }

        raw = '${prefix}___$diseasePart';
      }

      final result = PredictionResult(
        label: raw,
        confidence: entry.p,
        isTopResult: first,
      );

      first = false;
      return result;
    }).toList();
  }

  void _close() {
    _interpreter?.close();
    _interpreter = null;
    _diseasesPerCrop = {};
  }

  void dispose() => _close();
}
