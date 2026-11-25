import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../benchmark/benchmark_screen.dart'; // ⚠️ TEMPORARY — BENCHMARK ONLY
import '../providers/app_state.dart';
import '../services/connectivity_service.dart';
import '../services/gemini_service.dart';
import '../services/ml_service.dart';
import '../services/scan_history_service.dart';
import '../services/weather_service.dart';
import '../theme/app_theme.dart';
import '../utils/app_strings.dart';
import '../utils/disease_labels.dart';

// ════════════════════════════════════════════════════════════════════════════════
// SCREEN
// ════════════════════════════════════════════════════════════════════════════════

class AiScanScreen extends StatefulWidget {
  const AiScanScreen({super.key});

  @override
  State<AiScanScreen> createState() => _AiScanScreenState();
}

class _AiScanScreenState extends State<AiScanScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  // ── State ──────────────────────────────────────────────────────────────────

  File? _pickedImage;
  bool _isLoading = false;
  bool _isAnalyzing = false;
  InferenceResult? _result;
  String? _errorMessage;
  String? _lastScanId; // tracks the most recently saved scan

  final MLService _mlService = MLService();
  final GeminiService _geminiService = GeminiService();
  final ImagePicker _picker = ImagePicker();

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _mlService.dispose();
    super.dispose();
  }

  // ── Model Loading ─────────────────────────────────────────────────────────

  Future<void> _ensureModelLoaded() async {
    if (_mlService.isLoaded) return;

    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      await _mlService.loadModel();
    } on MLServiceException catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Model not available: ${e.message}';
        });
      }
      debugPrint(e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Image Picking ─────────────────────────────────────────────────────────

  Future<void> _pickImage(ImageSource source) async {
    try {
      final xFile = await _picker.pickImage(
        source: source,
        imageQuality: 90,
        maxWidth: 1024,
        maxHeight: 1024,
      );
      if (xFile == null) return;
      setState(() {
        _pickedImage = File(xFile.path);
        _result = null;
        _errorMessage = null;
      });
    } catch (e) {
      if (mounted) setState(() => _errorMessage = '${context.s.couldNotOpenImage}$e');
    }
  }

  // ── Inference ─────────────────────────────────────────────────────────────

  /// Entry point for the Analyse button.
  ///
  /// Final deployment flow:
  /// 1. Run the validated on-device LeafCareNet first (online or offline).
  /// 2. Use Gemini Vision only as a cloud fallback if the local model
  ///    could not be loaded.
  ///
  /// This ensures normal disease classification is performed by the
  /// proposed LeafCareNet rather than by Gemini whenever the TFLite
  /// model is available.
  Future<void> _runInference() async {
    if (_pickedImage == null) {
      _showSnack(context.s.selectImageFirst);
      return;
    }

    setState(() {
      _isAnalyzing = true;
      _result = null;
      _errorMessage = null;
    });

    try {
      InferenceResult? result;

      // ── Primary path: final on-device LeafCareNet ───────────────────────
      await _ensureModelLoaded();

      if (_mlService.isLoaded) {
        result = await _mlService.runInference(_pickedImage!);
      }

      // ── Optional cloud fallback only if local model unavailable ─────────
      if (result == null && await ConnectivityService.isOnline()) {
        debugPrint(
          '[AiScan] LeafCareNet unavailable; trying Gemini Vision fallback',
        );
        result = await _geminiService.classifyDiseaseFromImage(_pickedImage!);
      }

      if (result == null) {
        throw const MLServiceException(
          'Disease classification could not be completed.',
          'CLASSIFICATION_FAILED',
        );
      }

      if (mounted) {
        setState(() => _result = result);
        _saveToHistory(result);
      }
    } on MLServiceException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } catch (e) {
      if (mounted) setState(() => _errorMessage = 'Unexpected error: $e');
    } finally {
      if (mounted) setState(() => _isAnalyzing = false);
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        backgroundColor: KrishokColors.primaryGreen,
      ),
    );
  }

  void _saveToHistory(InferenceResult result) {
    final top = result.topDisease;
    final id = ScanHistoryService.newId();
    _lastScanId = id;
    final record = ScanRecord(
      id: id,
      cropModel: result.crop.displayName,
      cropEmoji: result.crop.emoji,
      diseaseName: top.prettyLabel,
      diseaseLabel: top.label,
      confidence: top.confidence,
      imagePath: _pickedImage?.path,
      timestamp: DateTime.now(),
      isHealthy: top.isHealthy,
    );
    Provider.of<AppState>(context, listen: false).addScan(record);
  }

  void _showAiInsightSheet() {
    if (_result == null) return;
    final appState = Provider.of<AppState>(context, listen: false);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AiInsightSheet(
        model: _result!.crop,
        topResult: _result!.topDisease,
        sensorData: appState.currentData,
        isSensorOnline: appState.isConnected,
        language: appState.language,
        onInsightLoaded: (insight) {
          if (_lastScanId != null) {
            appState.updateScanInsight(_lastScanId!, insight);
          }
        },
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: KrishokColors.background,
      appBar: _buildAppBar(),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ImageDropZone(
              image: _pickedImage,
              onTapCamera: () => _pickImage(ImageSource.camera),
              onTapGallery: () => _pickImage(ImageSource.gallery),
            ),
            const SizedBox(height: 16),
            _ActionRow(
              isDisabled: _isAnalyzing || _isLoading,
              onCamera: () => _pickImage(ImageSource.camera),
              onGallery: () => _pickImage(ImageSource.gallery),
            ),
            const SizedBox(height: 20),

            // Analyse button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: (_isAnalyzing || _isLoading) ? null : _runInference,
                icon: _isLoading
                    ? const SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(LucideIcons.microscope, size: 18),
                label: Text(
                  _isLoading
                      ? context.s.loadingModel
                      : _isAnalyzing
                          ? context.s.analysing
                          : context.s.analyseLeaf,
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: KrishokColors.primaryGreen,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: KrishokColors.primaryGreen.withValues(alpha: 0.5),
                  disabledForegroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  textStyle: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 15),
                ),
              ),
            ),

            if (_isAnalyzing) ...[
              const SizedBox(height: 24),
              const _AnalyzingCard(),
            ],

            if (_errorMessage != null) ...[
              const SizedBox(height: 24),
              _ErrorCard(message: _errorMessage!),
            ],

            if (_result != null && !_isAnalyzing) ...[
              const SizedBox(height: 24),
              _ResultCard(
                result: _result!,
                onGetAiInsight: _showAiInsightSheet,
              ),
            ],

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: KrishokColors.mintGreen,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.eco_rounded,
                size: 20, color: KrishokColors.primaryGreen),
          ),
          const SizedBox(width: 10),
          const Text('Krishok'),
        ],
      ),
      backgroundColor: KrishokColors.cardWhite,
      // ⚠️ TEMPORARY — BENCHMARK ONLY: remove actions block below after publication
      actions: [
        Tooltip(
          message: 'Benchmark LeafCareNet',
          child: IconButton(
            icon: const Icon(Icons.science_rounded, color: Color(0xFF7C5CBF)),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const BenchmarkScreen()),
            ),
          ),
        ),
      ],
      // ⚠️ END TEMPORARY
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════════
// IMAGE DROP ZONE
// ════════════════════════════════════════════════════════════════════════════════

class _ImageDropZone extends StatelessWidget {
  final File? image;
  final VoidCallback onTapCamera;
  final VoidCallback onTapGallery;

  const _ImageDropZone({
    required this.image,
    required this.onTapCamera,
    required this.onTapGallery,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTapGallery,
      child: Container(
        height: 260,
        width: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xFFF3F0FA),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: const Color(0xFFD8D0EA),
            width: 1.5,
          ),
        ),
        child: image != null
            ? _SelectedImagePreview(image: image!)
            : const _EmptyDropZoneContent(),
      ),
    );
  }
}

class _EmptyDropZoneContent extends StatelessWidget {
  const _EmptyDropZoneContent();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFFE8E0F5),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Icon(LucideIcons.imagePlus,
              size: 36, color: Color(0xFF7C5CBF)),
        ),
        const SizedBox(height: 16),
        Text(
          context.s.noImageSelected,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: KrishokColors.textDark,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          context.s.tapToSelectLeaf,
          style: const TextStyle(fontSize: 13, color: KrishokColors.textLight),
        ),
      ],
    );
  }
}

class _SelectedImagePreview extends StatelessWidget {
  final File image;
  const _SelectedImagePreview({required this.image});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Image.file(
        image,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════════
// ACTION ROW
// ════════════════════════════════════════════════════════════════════════════════

class _ActionRow extends StatelessWidget {
  final bool isDisabled;
  final VoidCallback onCamera;
  final VoidCallback onGallery;

  const _ActionRow({
    required this.isDisabled,
    required this.onCamera,
    required this.onGallery,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: isDisabled ? null : onCamera,
            icon: const Icon(LucideIcons.camera, size: 18),
            label: Text(context.s.camera),
            style: OutlinedButton.styleFrom(
              foregroundColor: KrishokColors.primaryGreen,
              side: const BorderSide(color: KrishokColors.primaryGreen),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              textStyle: const TextStyle(
                  fontWeight: FontWeight.w600, fontSize: 14),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: isDisabled ? null : onGallery,
            icon: const Icon(LucideIcons.image, size: 18),
            label: Text(context.s.gallery),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF7C5CBF),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              textStyle: const TextStyle(
                  fontWeight: FontWeight.w600, fontSize: 14),
            ),
          ),
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════════
// ANALYSING CARD
// ════════════════════════════════════════════════════════════════════════════════

class _AnalyzingCard extends StatelessWidget {
  const _AnalyzingCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: KrishokColors.cardWhite,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 32, height: 32,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: KrishokColors.primaryGreen,
              backgroundColor: KrishokColors.mintGreen,
            ),
          ),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.s.analysingLeaf,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: KrishokColors.textDark)),
                const SizedBox(height: 4),
                Text(context.s.runningModel,
                    style: const TextStyle(
                        fontSize: 13, color: KrishokColors.textLight)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════════
// ERROR CARD
// ════════════════════════════════════════════════════════════════════════════════

class _ErrorCard extends StatelessWidget {
  final String message;
  const _ErrorCard({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded,
              color: Colors.redAccent, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                  fontSize: 13,
                  color: KrishokColors.textMedium,
                  height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════════
// RESULT CARD
// ════════════════════════════════════════════════════════════════════════════════

class _ResultCard extends StatelessWidget {
  final InferenceResult result;
  final VoidCallback onGetAiInsight;

  const _ResultCard({
    required this.result,
    required this.onGetAiInsight,
  });

  @override
  Widget build(BuildContext context) {
    final results = result.diseases;
    final top = result.topDisease;
    final model = result.crop;
    final isHealthy = top.isHealthy;
    final cropConfPct = (result.cropConfidence * 100).toStringAsFixed(1);

    final accentColor =
        isHealthy ? KrishokColors.primaryGreen : Colors.orange[700]!;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: KrishokColors.cardWhite,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accentColor.withValues(alpha: 0.4)),
        boxShadow: [
          BoxShadow(
              color: accentColor.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Detected crop banner (Stage-1 router output) ──────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: KrishokColors.mintGreen,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.eco_rounded,
                    size: 16, color: KrishokColors.primaryGreen),
                const SizedBox(width: 8),
                Text(
                  'Detected: ${model.emoji} ${model.displayName}  ·  $cropConfPct%',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: KrishokColors.primaryGreen,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // ── Top prediction ─────────────────────────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isHealthy
                      ? Icons.eco_rounded
                      : Icons.bug_report_rounded,
                  color: accentColor,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      DiseaseLabels.get(top.label, context.read<AppState>().language),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 17,
                        color: KrishokColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${model.emoji} ${model.displayName}  ·  ${top.confidencePercent} confidence',
                      style: const TextStyle(
                          fontSize: 13, color: KrishokColors.textMedium),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // ── Confidence bar ─────────────────────────────────────────────────
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: top.confidence),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOut,
              builder: (context, v, child) => LinearProgressIndicator(
                value: v,
                backgroundColor: KrishokColors.surfaceGray,
                color: accentColor,
                minHeight: 7,
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ── Alternates ─────────────────────────────────────────────────────
          if (results.length > 1) ...[
            Text(context.s.otherCandidates,
                style: const TextStyle(
                    fontSize: 12,
                    color: KrishokColors.textLight,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            for (final r in results.skip(1))
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    const Icon(Icons.chevron_right,
                        size: 16, color: KrishokColors.textLight),
                    Text(DiseaseLabels.get(r.label, context.read<AppState>().language),
                        style: const TextStyle(
                            fontSize: 13, color: KrishokColors.textMedium)),
                    const Spacer(),
                    Text(r.confidencePercent,
                        style: const TextStyle(
                            fontSize: 12,
                            color: KrishokColors.textLight,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            const SizedBox(height: 12),
          ],

          // ── AI Insight button ─────────────────────────────────────────────
          if (!isHealthy)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onGetAiInsight,
                icon: const Icon(Icons.auto_awesome, size: 18),
                label: Text(context.s.getAiInsight),
                style: OutlinedButton.styleFrom(
                  foregroundColor: KrishokColors.amber,
                  side: BorderSide(
                    color: KrishokColors.amber.withValues(alpha: 0.5),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  textStyle: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 14),
                ),
              ),
            ),

          if (isHealthy)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: KrishokColors.mintGreen,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_rounded,
                      color: KrishokColors.primaryGreen, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      context.s.cropHealthyMsg,
                      style: const TextStyle(
                          fontSize: 13,
                          color: KrishokColors.textMedium,
                          height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════════
// AI INSIGHT BOTTOM SHEET
// ════════════════════════════════════════════════════════════════════════════════

class _AiInsightSheet extends StatefulWidget {
  final KrishokModel model;
  final PredictionResult topResult;
  final dynamic sensorData;
  final bool isSensorOnline;
  final String language;
  final void Function(String insight)? onInsightLoaded;

  const _AiInsightSheet({
    required this.model,
    required this.topResult,
    required this.sensorData,
    required this.isSensorOnline,
    required this.language,
    this.onInsightLoaded,
  });

  @override
  State<_AiInsightSheet> createState() => _AiInsightSheetState();
}

class _AiInsightSheetState extends State<_AiInsightSheet> {
  bool _isLoading = true;
  String _insightText = '';
  String? _errorText;
  bool _isOffline = false;
  final GeminiService _gemini = GeminiService();

  @override
  void initState() {
    super.initState();
    _loadInsight();
  }

  Future<void> _loadInsight() async {
    setState(() { _isLoading = true; _errorText = null; _isOffline = false; });
    try {
      final sd = widget.sensorData;

      // Query weather service for rain probability
      String weatherSummary = '';
      try {
        final rainProb = await WeatherService().fetchRainProbability();
        if (rainProb != null) {
          weatherSummary = 'Precipitation probability: $rainProb%';
        }
      } catch (_) {}

      final text = await _gemini.getRecommendation(
        diseaseLabel: widget.topResult.label,
        confidence: widget.topResult.confidence,
        npkN: sd?.npk.n ?? 0,
        npkP: sd?.npk.p ?? 0,
        npkK: sd?.npk.k ?? 0,
        soilMoisture: sd?.soilMoisture.moisture ?? 0,
        airTemp: sd?.sht20.temp ?? 0,
        airHumidity: sd?.sht20.hum ?? 0,
        weatherSummary: weatherSummary,
        language: widget.language,
      );
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _insightText = text;
        // Detect if response came from offline KB (starts with 📴)
        // Detect if response came from offline KB
        _isOffline = text.contains('Offline Mode') || text.contains('অফলাইন মোড');
      });
      widget.onInsightLoaded?.call(text);
    } catch (e) {
      if (!mounted) return;
      setState(() { _isLoading = false; _errorText = e.toString(); });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, controller) => Container(
        decoration: const BoxDecoration(
          color: KrishokColors.cardWhite,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
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

            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: KrishokColors.amber.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.auto_awesome,
                      color: KrishokColors.amber, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(context.s.aiInsightTitle,
                          style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: KrishokColors.textDark)),
                      Text(
                        '${DiseaseLabels.get(widget.topResult.label, widget.language)}  ·  ${widget.model.emoji} ${widget.model.displayName}',
                        style: const TextStyle(
                            fontSize: 13, color: KrishokColors.textMedium),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Sensor data context
            _SensorContextCard(
              sensorData: widget.sensorData,
              isSensorOnline: widget.isSensorOnline,
            ),
            const SizedBox(height: 20),

            // Insight content
            if (_isLoading)
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: KrishokColors.surfaceGray,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    const SizedBox(
                      width: 32,
                      height: 32,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: KrishokColors.amber,
                        backgroundColor: Color(0xFFFFECB3),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      context.s.loadingInsight,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: KrishokColors.textMedium,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      context.s.isBn ? 'রোগ ও সেন্সর ডেটা বিশ্লেষণ হচ্ছে' : 'Analysing disease and sensor data',
                      style: const TextStyle(
                        fontSize: 12,
                        color: KrishokColors.textLight,
                      ),
                    ),
                  ],
                ),
              )
            else if (_errorText != null)
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.error_outline_rounded,
                            color: Colors.redAccent, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _errorText!,
                            style: const TextStyle(
                                fontSize: 13, color: KrishokColors.textMedium),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _loadInsight,
                        icon: const Icon(Icons.refresh_rounded, size: 16),
                        label: const Text('Try Again'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: KrishokColors.amber,
                          side: BorderSide(
                              color: KrishokColors.amber.withValues(alpha: 0.5)),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              Column(
                children: [
                  // Offline indicator inside insight card
                  if (_isOffline)
                    Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF3CD),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          const Icon(LucideIcons.wifiOff,
                              size: 13, color: Color(0xFF856404)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              widget.language == 'bn'
                                  ? 'অফলাইন মোড — স্থানীয় জ্ঞানভান্ডার থেকে'
                                  : 'Offline mode — from local knowledge base',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF856404),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: KrishokColors.surfaceGray,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      _insightText,
                      style: const TextStyle(
                        fontSize: 13,
                        color: KrishokColors.textMedium,
                        height: 1.7,
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _SensorContextCard extends StatelessWidget {
  final dynamic sensorData;
  final bool isSensorOnline;

  const _SensorContextCard({
    required this.sensorData,
    required this.isSensorOnline,
  });

  @override
  Widget build(BuildContext context) {
    if (sensorData == null) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: KrishokColors.surfaceGray,
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Row(
          children: [
            Icon(Icons.sensors_off_rounded,
                size: 16, color: KrishokColors.textLight),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Sensor data unavailable — insight based on disease info only.',
                style: TextStyle(
                  fontSize: 12,
                  color: KrishokColors.textLight,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: KrishokColors.primaryGreen.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: KrishokColors.primaryGreen.withValues(alpha: 0.15),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isSensorOnline
                    ? Icons.sensors_rounded
                    : Icons.wifi_off_rounded,
                size: 14,
                color: isSensorOnline
                    ? KrishokColors.primaryGreen
                    : KrishokColors.orangeWarning,
              ),
              const SizedBox(width: 6),
              Text(
                isSensorOnline ? 'Live Sensor Data' : 'Cached Sensor Data',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: isSensorOnline
                      ? KrishokColors.primaryGreen
                      : KrishokColors.orangeWarning,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              _SensorTag(
                  label: 'Temp',
                  value: '${sensorData.sht20.temp.toStringAsFixed(1)}°C'),
              _SensorTag(
                  label: 'Humidity',
                  value: '${sensorData.sht20.hum.toStringAsFixed(0)}%'),
              _SensorTag(
                  label: 'Moisture',
                  value:
                      '${sensorData.soilMoisture.moisture.toStringAsFixed(0)}%'),
              _SensorTag(
                  label: 'N', value: '${sensorData.npk.n}'),
              _SensorTag(
                  label: 'P', value: '${sensorData.npk.p}'),
              _SensorTag(
                  label: 'K', value: '${sensorData.npk.k}'),
            ],
          ),
        ],
      ),
    );
  }
}

class _SensorTag extends StatelessWidget {
  final String label;
  final String value;

  const _SensorTag({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: KrishokColors.cardWhite,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: const TextStyle(
              fontSize: 11,
              color: KrishokColors.textLight,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: KrishokColors.textDark,
            ),
          ),
        ],
      ),
    );
  }
}
