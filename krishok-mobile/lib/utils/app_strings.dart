import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';

class S {
  final String lang;
  const S(this.lang);

  bool get isBn => lang == 'bn';

  // ── Navigation ───────────────────────────────────────────────────────────────
  String get navFields    => isBn ? 'মাঠ'      : 'FIELDS';
  String get navScan      => isBn ? 'স্ক্যান'   : 'AI SCAN';
  String get navHistory   => isBn ? 'ইতিহাস'   : 'HISTORY';
  String get navChat      => isBn ? 'চ্যাট'     : 'CHAT';
  String get navSettings  => isBn ? 'সেটিংস'   : 'SETTINGS';

  // ── Common ───────────────────────────────────────────────────────────────────
  String get online       => isBn ? 'অনলাইন'   : 'ONLINE';
  String get offline      => isBn ? 'অফলাইন'   : 'OFFLINE';
  String get confidence   => isBn ? 'নিশ্চিততা' : 'confidence';
  String get cancel       => isBn ? 'বাতিল'     : 'Cancel';
  String get clear        => isBn ? 'মুছুন'     : 'Clear';
  String get healthy      => isBn ? 'সুস্থ'     : 'Healthy';
  String get disease      => isBn ? 'রোগাক্রান্ত' : 'Disease';
  String get aiInsightTitle => isBn ? 'AI বিশ্লেষণ' : 'AI Insight';

  // ── Dashboard ────────────────────────────────────────────────────────────────
  String get climateConditions  => isBn ? 'আবহাওয়া'         : 'CLIMATE';
  String get liveTelemetry      => isBn ? 'লাইভ ডেটা'        : 'LIVE TELEMETRY';
  String get temperature        => isBn ? 'তাপমাত্রা'         : 'Temperature';
  String get humidity           => isBn ? 'আর্দ্রতা'          : 'Humidity';
  String get soilMoisture       => isBn ? 'মাটির আর্দ্রতা'    : 'Soil Moisture';
  String get npkValues          => isBn ? 'সার মাত্রা (NPK)'  : 'NPK Values';
  String get getAiSuggestion    => isBn ? 'AI পরামর্শ নিন'    : 'Get AI Suggestion';
  String get aiSuggestionTitle  => isBn ? 'মাঠের পরামর্শ'     : 'Field Suggestion';
  String get loadingSuggestion  => isBn ? 'পরামর্শ তৈরি হচ্ছে…' : 'Generating suggestion…';
  String get staleDataNote      => isBn ? 'সেন্সর অফলাইন — শেষ পরিচিত ডেটা দেখানো হচ্ছে' : 'Sensor offline — showing last known data';
  String get sensorSearchTitle  => isBn ? 'সেন্সর খোঁজা হচ্ছে…' : 'Searching for sensor…';
  String get sensorStep1        => isBn ? '১. ESP32 ডিভাইস চালু করুন' : '1. Power on your ESP32 device';
  String get sensorStep2        => isBn ? '২. WiFi: KrishokAP নেটওয়ার্কে সংযুক্ত হন' : '2. Connect to WiFi: KrishokAP';
  String get sensorStep3        => isBn ? '৩. ডেটা স্বয়ংক্রিয়ভাবে লোড হবে' : '3. Data will load automatically';

  // ── AI Scan ──────────────────────────────────────────────────────────────────
  String get noImageSelected    => isBn ? 'কোনো ছবি নেই'               : 'No Image Selected';
  String get tapToSelectLeaf    => isBn ? 'পাতার ছবি বেছে নিতে ট্যাপ করুন' : 'Tap to select a leaf image from gallery';
  String get camera             => isBn ? 'ক্যামেরা'                    : 'Camera';
  String get gallery            => isBn ? 'গ্যালারি'                    : 'Gallery';
  String get modelSelection     => isBn ? 'মডেল নির্বাচন'               : 'MODEL SELECTION';
  String get analyseLeaf        => isBn ? 'পাতা বিশ্লেষণ করুন'          : 'Analyse Leaf';
  String get analysing          => isBn ? 'বিশ্লেষণ হচ্ছে…'             : 'Analysing…';
  String get loadingModel       => isBn ? 'মডেল লোড হচ্ছে…'             : 'Loading Model…';
  String get analysingLeaf      => isBn ? 'পাতা বিশ্লেষণ হচ্ছে…'        : 'Analysing leaf…';
  String get runningModel       => isBn ? 'মডেল চালু হচ্ছে, একটু অপেক্ষা করুন।' : 'Running model inference, please wait.';
  String get otherCandidates    => isBn ? 'অন্যান্য সম্ভাবনা:'           : 'Other candidates:';
  String get getAiInsight       => isBn ? 'AI পরামর্শ নিন'               : 'Get AI Insight';
  String get cropHealthyMsg     => isBn ? 'আপনার ফসল সুস্থ দেখাচ্ছে! রোগের প্রাথমিক লক্ষণের জন্য পর্যবেক্ষণ চালিয়ে যান।' : 'Your crop looks healthy! Keep monitoring for early signs of disease.';
  String get loadingInsight     => isBn ? 'AI বিশ্লেষণ তৈরি করছে…' : 'AI is generating insight…';
  String get noInsightYet       => isBn ? 'এখনো কোনো AI বিশ্লেষণ নেই।\n"AI পরামর্শ নিন" বাটনে ক্লিক করুন।' : 'No AI insight yet.\nTap "Get AI Insight" to generate one.';
  String get selectImageFirst   => isBn ? 'প্রথমে একটি পাতার ছবি বেছে নিন।' : 'Please select a leaf image first.';
  String get couldNotOpenImage  => isBn ? 'ছবি খোলা যায়নি: ' : 'Could not open image: ';

  // ── History ──────────────────────────────────────────────────────────────────
  String get scanHistory        => isBn ? 'স্ক্যান ইতিহাস'    : 'Scan History';
  String get diseaseRisk7Days   => isBn ? 'রোগের ঝুঁকি (৭ দিন)' : 'Disease Risk (7 Days)';
  String get totalScans         => isBn ? 'মোট স্ক্যান'        : 'Total Scans';
  String get diseasesFound      => isBn ? 'রোগ শনাক্ত'         : 'Diseases Found';
  String get riskLevel          => isBn ? 'ঝুঁকির মাত্রা'      : 'Risk Level';
  String get dailyActivity      => isBn ? 'দৈনিক কার্যক্রম'    : 'Daily Activity';
  String get noScansYet         => isBn ? 'এখনো কোনো স্ক্যান নেই' : 'No scans yet';
  String get noScansDesc        => isBn ? 'AI স্ক্যান ট্যাবে গিয়ে ফসলের পাতা স্ক্যান করুন।' : 'Go to AI Scan tab to analyse a leaf.';
  String get scanDeleted        => isBn ? 'স্ক্যান মুছে ফেলা হয়েছে' : 'Scan deleted';
  String get clearAll           => isBn ? 'সব মুছুন'           : 'Clear All';
  String get clearAllHistory    => isBn ? 'সব ইতিহাস মুছুন'    : 'Clear All History';
  String get clearAllConfirm    => isBn ? 'এটি সব স্ক্যান রেকর্ড স্থায়ীভাবে মুছে দেবে। চালিয়ে যাবেন?' : 'This will permanently delete all scan records. Continue?';
  String get noAiInsightYet     => isBn ? 'এই স্ক্যানের জন্য কোনো AI বিশ্লেষণ নেই।\nস্ক্যান পুনরায় করুন এবং "AI পরামর্শ নিন" ক্লিক করুন।' : 'No AI insight for this scan yet.\nRe-scan and tap "Get AI Insight".';

  String riskMessage(String level) {
    if (isBn) {
      switch (level) {
        case 'Low':      return 'ফসল সুস্থ আছে। নিয়মিত পর্যবেক্ষণ চালিয়ে যান।';
        case 'Moderate': return 'কিছু সমস্যা শনাক্ত হয়েছে। প্রতিরোধমূলক ব্যবস্থা নিন।';
        case 'High':     return 'উচ্চ রোগের ঝুঁকি! অবিলম্বে পদক্ষেপ নিন।';
        case 'Critical': return 'সংকটজনক ঝুঁকি! কৃষি কর্মকর্তার সাথে যোগাযোগ করুন।';
        default:         return 'স্ক্যান চালিয়ে যান এবং ফসলের স্বাস্থ্য পর্যবেক্ষণ করুন।';
      }
    } else {
      switch (level) {
        case 'Low':      return 'Your crops look healthy. Keep monitoring regularly.';
        case 'Moderate': return 'Some issues detected. Consider preventive measures.';
        case 'High':     return 'High disease risk! Take immediate preventive action.';
        case 'Critical': return 'Critical risk! Contact an agricultural officer immediately.';
        default:         return 'Keep scanning to track crop health.';
      }
    }
  }

  // ── Chat ─────────────────────────────────────────────────────────────────────
  String get chatScreenTitle    => isBn ? 'AI সহকারী'                : 'AI Assistant';
  String get poweredByAi        => isBn ? 'AI দ্বারা চালিত'          : 'Powered by AI';
  String get typeMessage        => isBn ? 'বার্তা লিখুন...'          : 'Type a message...';
  String get welcomeTitle       => isBn ? 'কৃষক AI সহকারী'           : 'Krishok AI Assistant';
  String get welcomeSubtitle    => isBn ? 'ফসলের রোগ, মাটির স্বাস্থ্য\nও চাষাবাদের পরামর্শ পান।' : 'Ask me anything about crop health, diseases,\nsoil management, and farming tips.';
  String get suggestedQuestions => isBn ? 'প্রস্তাবিত প্রশ্নসমূহ'    : 'Suggested Questions';

  List<String> get chatSuggestions => isBn
      ? [
          'আমার ফসলে রোগের লক্ষণ দেখা যাচ্ছে, কী করা উচিত?',
          'মাটির পুষ্টিগুণ কীভাবে উন্নত করব?',
          'এই মৌসুমের জন্য সেরা সার সময়সূচি কী?',
          'আমার মাটির জন্য কোন ফসল সবচেয়ে ভালো?',
        ]
      : [
          'My crop has disease symptoms, what should I do?',
          'How can I improve soil nutrition?',
          'Best fertilizer schedule for this season?',
          'What crops are best for my soil type?',
        ];

  // ── Settings ─────────────────────────────────────────────────────────────────
  String get settingsTitle        => isBn ? 'সেটিংস'                          : 'Settings';
  String get esp32Device          => isBn ? 'ESP32 ডিভাইস'                     : 'ESP32 Device';
  String get serverUrlLabel       => isBn ? 'সার্ভার URL'                       : 'Server URL';
  String get saveReconnect        => isBn ? 'সংরক্ষণ ও পুনঃসংযোগ'              : 'Save & Reconnect';
  String get appLanguageTitle     => isBn ? 'ভাষা / Language'                   : 'Language / ভাষা';
  String get appLanguageLabel     => isBn ? 'অ্যাপের ভাষা'                     : 'App Language';
  String get aboutKrishok         => isBn ? 'কৃষক সম্পর্কে'                    : 'About Krishok';
  String get deviceConnected      => isBn ? 'ডিভাইস সংযুক্ত'                  : 'Device Connected';
  String get deviceNotConnected   => isBn ? 'ডিভাইস সংযুক্ত নেই'              : 'Device Not Connected';
  String get esp32Online          => isBn ? 'ESP32 অনলাইন এবং ডেটা পাঠাচ্ছে।' : 'ESP32 is online and streaming data.';
  String get checkWifi            => isBn ? 'WiFi নেটওয়ার্ক এবং ডিভাইস চেক করুন।' : 'Check your WiFi network and device power.';
  String get enterValidUrl        => isBn ? 'একটি সঠিক URL দিন'                : 'Please enter a valid URL';
  String get savedReconnecting    => isBn ? 'সংরক্ষিত। ডিভাইসের সাথে পুনঃসংযোগ হচ্ছে...' : 'Saved. Reconnecting to device...';
  String get madeForFarmers       => isBn ? 'কৃষকদের জন্য, কৃষকদের দ্বারা 🌾'  : 'Made for farmers, by farmers 🌾';

  // ── Climate / Rain ───────────────────────────────────────────────────────────
  String get rainChance          => isBn ? 'বৃষ্টির সম্ভাবনা'   : 'Rain Chance';
  String get rainLow             => isBn ? 'কম সম্ভাবনা'        : 'Low chance';
  String get rainModerate        => isBn ? 'মাঝারি সম্ভাবনা'    : 'Moderate';
  String get rainHigh            => isBn ? 'বৃষ্টি হতে পারে'    : 'Likely rain';

  // ── Sensor Trend ────────────────────────────────────────────────────────────
  String get sensorTrend         => isBn ? '৫ দিনের সেন্সর ট্রেন্ড' : '5-Day Sensor Trend';
  String get noSensorHistory     => isBn ? 'সেন্সর ডেটা সংগ্রহ হচ্ছে…' : 'Collecting sensor data…';
  String get nLegend             => isBn ? 'নাইট্রোজেন'          : 'Nitrogen';
  String get pLegend             => isBn ? 'ফসফরাস'             : 'Phosphorus';
  String get kLegend             => isBn ? 'পটাসিয়াম'            : 'Potassium';
}

extension StringsContext on BuildContext {
  S get s => S(read<AppState>().language);
}
