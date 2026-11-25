class DiseaseLabels {
  static const Map<String, Map<String, String>> _labels = {
    'Potato___Early_blight': {
      'en': 'Potato Early Blight',
      'bn': 'আলু আগাম ধ্বসা',
    },
    'Potato___Late_blight': {
      'en': 'Potato Late Blight',
      'bn': 'আলু নাবি ধ্বসা',
    },
    'Potato___healthy': {
      'en': 'Potato — Healthy',
      'bn': 'আলু — সুস্থ',
    },
    'Tomato___Bacterial_spot': {
      'en': 'Tomato Bacterial Spot',
      'bn': 'টমেটো ব্যাকটেরিয়াল স্পট',
    },
    'Tomato___Early_blight': {
      'en': 'Tomato Early Blight',
      'bn': 'টমেটো আগাম ধ্বসা',
    },
    'Tomato___Late_blight': {
      'en': 'Tomato Late Blight',
      'bn': 'টমেটো নাবি ধ্বসা',
    },
    'Tomato___Leaf_Mold': {
      'en': 'Tomato Leaf Mold',
      'bn': 'টমেটো পাতায় ছত্রাক',
    },
    'Tomato___Spider_mites_Two_spotted_spider_mite': {
      'en': 'Tomato Spider Mites',
      'bn': 'টমেটো মাকড়সা মাইট',
    },
    'Tomato___YellowLeaf_Curl_Virus': {
      'en': 'Tomato Yellow Leaf Curl Virus',
      'bn': 'টমেটো হলুদ পাতা কুঁকড়ানো ভাইরাস',
    },
    'Tomato___healthy': {
      'en': 'Tomato — Healthy',
      'bn': 'টমেটো — সুস্থ',
    },
    'Tomato___mosaic_virus': {
      'en': 'Tomato Mosaic Virus',
      'bn': 'টমেটো মোজাইক ভাইরাস',
    },
    'Rice___Bacterial_Leaf_Blight': {
      'en': 'Rice Bacterial Leaf Blight',
      'bn': 'ধানের ব্যাকটেরিয়াল পাতা ঝলসা',
    },
    'Rice___Brown_Spot': {
      'en': 'Rice Brown Spot',
      'bn': 'ধানের বাদামী দাগ',
    },
    'Rice___Healthy_Leaf': {
      'en': 'Rice — Healthy',
      'bn': 'ধান — সুস্থ',
    },
    'Rice___Leaf_Blast': {
      'en': 'Rice Leaf Blast',
      'bn': 'ধানের পাতা ব্লাস্ট',
    },
    'Rice___Sheath_Blight': {
      'en': 'Rice Sheath Blight',
      'bn': 'ধানের খোল পোড়া',
    },
  };

  static String get(String label, String language) {
    final map = _labels[label];
    if (map != null) return map[language] ?? map['en'] ?? label;
    return label.replaceAll('___', ' — ').replaceAll('_', ' ');
  }
}
