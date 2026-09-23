import '../constants/categories.dart';

class MerchantCategorizer {
  MerchantCategorizer._();

  static const Set<String> _noiseWords = {
    'pvt',
    'private',
    'ltd',
    'limited',
    'llp',
    'inc',
    'india',
    'services',
    'service',
    'payment',
    'payments',
    'txn',
    'txns',
    'trxn',
    'transaction',
    'merchant',
    'online',
    'store',
    'retail',
    'solutions',
    'solution',
    'technologies',
    'technology',
    'digital',
    'enterprises',
    'enterprise',
    'super',
    'svcs',
    'misc',
    'for',
    'inr',
    'rs',
    'li',
    'priv',
    'intl',
    'international',
  };

  static const Map<String, String> _merchantCategoryMap = {
    // Food / quick commerce
    'zomato': 'Food',
    'swiggy': 'Food',
    'swiggy instamart': 'Groceries',
    'instamart': 'Groceries',
    'eatclub': 'Food',
    'eat fit': 'Food',
    'bundl': 'Food',
    'bundle': 'Food',
    'faasos': 'Food',
    'behrouz': 'Food',
    'box8': 'Food',
    'chaayos': 'Food',
    'starbucks': 'Food',
    'mcdonald': 'Food',
    'dominos': 'Food',
    'domino': 'Food',
    'kfc': 'Food',
    'subway': 'Food',
    'pizza hut': 'Food',

    // Groceries
    'blinkit': 'Groceries',
    'blink commerce': 'Groceries',
    'zepto': 'Groceries',
    'bigbasket': 'Groceries',
    'big basket': 'Groceries',
    'jiomart': 'Groceries',
    'dmart': 'Groceries',
    'reliance fresh': 'Groceries',
    'nature basket': 'Groceries',
    'dunzo': 'Groceries',
    'more supermarket': 'Groceries',
    'spencers': 'Groceries',
    'smart bazaar': 'Groceries',
    'easyday': 'Groceries',
    'fresh to home': 'Groceries',

    // Shopping
    'amazon': 'Shopping',
    'amazon pay': 'Shopping',
    'flipkart': 'Shopping',
    'snapdeal': 'Shopping',
    'tatacliq': 'Shopping',
    'nykaa': 'Shopping',
    'meesho': 'Shopping',
    'croma': 'Shopping',
    'reliance digital': 'Shopping',
    'vijay sales': 'Shopping',
    'shopsy': 'Shopping',
    'pepperfry': 'Shopping',
    'urban ladder': 'Shopping',
    'firstcry': 'Shopping',
    'hamleys': 'Shopping',
    'decathlon': 'Shopping',
    'mintra': 'Shopping',
    'itsy bitsy': 'Shopping',
    'jewellers': 'Shopping',
    'jewelers': 'Shopping',
    'mobile shop': 'Shopping',
    'trading company': 'Shopping',
    'flora': 'Gifts',

    // Clothing / fashion
    'myntra': 'Clothing',
    'ajio': 'Clothing',
    'zara': 'Clothing',
    'h and m': 'Clothing',
    'hm': 'Clothing',
    'westside': 'Clothing',
    'pantaloons': 'Clothing',
    'max fashion': 'Clothing',
    'zudio': 'Clothing',
    'trent': 'Clothing',
    'lifestyle': 'Clothing',
    'life style': 'Clothing',
    'lifestyle intl': 'Clothing',
    'lifestyle international': 'Clothing',
    'life style internation': 'Clothing',
    'shopper stop': 'Clothing',
    'shoppers stop': 'Clothing',
    'levis': 'Clothing',
    'van heusen': 'Clothing',
    'allen solly': 'Clothing',
    'peter england': 'Clothing',
    'uniqlo': 'Clothing',
    'snitch': 'Clothing',

    // Travel
    'uber': 'Travel',
    'ola': 'Travel',
    'rapido': 'Travel',
    'irctc': 'Travel',
    'makemytrip': 'Travel',
    'goibibo': 'Travel',
    'redbus': 'Travel',
    'cleartrip': 'Travel',
    'indigo': 'Travel',
    'spicejet': 'Travel',
    'air india': 'Travel',

    // Subscriptions / digital
    'netflix': 'Subscriptions',
    'spotify': 'Subscriptions',
    'youtube premium': 'Subscriptions',
    'prime video': 'Subscriptions',
    'amazon prime': 'Subscriptions',
    'hotstar': 'Subscriptions',
    'disney hotstar': 'Subscriptions',
    'apple': 'Subscriptions',
    'jio cinema': 'Subscriptions',
    'zee5': 'Subscriptions',
    'sonyliv': 'Subscriptions',
    'apple music': 'Subscriptions',
    'google one': 'Subscriptions',

    // Entertainment
    'bookmyshow': 'Entertainment',
    'pvr': 'Entertainment',
    'inox': 'Entertainment',
    'cinepolis': 'Entertainment',
    'google play': 'Subscriptions',

    // Health
    'apollo': 'Health',
    'pharmeasy': 'Health',
    '1mg': 'Health',
    'netmeds': 'Health',

    // Bills / utilities
    'airtel': 'Bills',
    'jio': 'Bills',
    'bsnl': 'Bills',
    'vodafone': 'Bills',
    'vi': 'Bills',
    'act fibernet': 'Bills',
    'hathway': 'Bills',
    'asianet': 'Bills',
    'tataplay': 'Bills',
    'tata play': 'Bills',
    'tata power': 'Utilities',
    'adani': 'Utilities',
    'bescom': 'Utilities',
    'bses': 'Utilities',
    'torrent power': 'Utilities',
    'msedcl': 'Utilities',

    // Finance / payments
    'paytm': 'Finance',
    'phonepe': 'Finance',
    'google pay': 'Finance',
    'gpay': 'Finance',
    'cred': 'Finance',
    'mobikwik': 'Finance',
    'freecharge': 'Finance',
    'bharatpe': 'Finance',
    'simpl': 'Finance',
    'lazypay': 'Finance',
    'slice': 'Finance',
    'one card': 'Finance',
    'hdfc': 'Finance',
    'icici': 'Finance',
    'axis': 'Finance',
    'kotak': 'Finance',
    'sbi': 'Finance',
    'dreamplug': 'Finance',
    'razorpay': 'Finance',

    // Fallback broad label
    'reliance': 'Groceries',
    'keshar market': 'Groceries',
    'market': 'Groceries',
    'third wave coffee': 'Food',
    'new loksewa hotel': 'Food',
    'sapphire foods': 'Food',
    'eternal': 'Food',
    'madhu wines': 'Entertainment',
  };

  static const Map<String, String> _canonicalDisplayNames = {
    'tata starbuck': 'Starbucks',
    'tata starbucks': 'Starbucks',
    'starbuck': 'Starbucks',
    'starbucks': 'Starbucks',
    'life style internation': 'Lifestyle',
    'life style international': 'Lifestyle',
    'life style': 'Lifestyle',
    'lifestyle': 'Lifestyle',
    'lifestyle intl': 'Lifestyle',
    'shoppers stop': 'Shoppers Stop',
    'shopper stop': 'Shoppers Stop',
    'bundl': 'Swiggy',
    'blink commerce': 'Blinkit',
    'google play': 'Google Play',
    'cinepolis': 'Cinepolis',
    'dreamplug technologi': 'Razorpay',
    'dreamplug technologies': 'Razorpay',
    'eternal': 'Zomato',
  };

  static final List<MapEntry<String, String>> _sortedRules =
      _merchantCategoryMap.entries.toList()
        ..sort((a, b) => b.key.length.compareTo(a.key.length));

  static const Map<String, String> _keywordFallbackMap = {
    'fuel': 'Fuel',
    'petrol': 'Fuel',
    'diesel': 'Fuel',
    'recharge': 'Bills',
    'mobile recharge': 'Bills',
    'atm': 'Finance',
    'cash withdrawal': 'Finance',
    'rent': 'Rent',
    'house rent': 'Rent',
    'maintenance': 'Rent',
    'electricity': 'Utilities',
    'water bill': 'Utilities',
    'gas bill': 'Utilities',
    'broadband': 'Bills',
    'wifi': 'Bills',
    'movie': 'Entertainment',
    'pharmacy': 'Health',
    'hospital': 'Health',
    'school': 'Education',
    'fees': 'Education',
  };

  static final List<MapEntry<String, String>> _sortedFallbacks =
      _keywordFallbackMap.entries.toList()
        ..sort((a, b) => b.key.length.compareTo(a.key.length));

  static final Map<String, String> _runtimeOverrides = {};

  static void registerOverrides(Map<String, String> overrides) {
    _runtimeOverrides
      ..clear()
      ..addEntries(
        overrides.entries.map(
          (entry) => MapEntry(normalizeMerchant(entry.key), entry.value),
        ),
      );
  }

  static String normalizeMerchant(String raw) {
    var normalized = raw.toLowerCase();
    normalized = normalized.replaceAll(RegExp(r'[@#_/\\|]+'), ' ');
    normalized = normalized.replaceAll(RegExp(r'[^a-z0-9& ]+'), ' ');
    normalized = normalized.replaceAll('&', ' and ');
    final parts = normalized
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .where((part) => !_noiseWords.contains(part))
        .where((part) => part.length > 1 || RegExp(r'\d').hasMatch(part))
        .toList();
    return parts.join(' ').trim();
  }

  static String categorize({
    required String merchant,
    required String rawText,
  }) {
    final normalizedMerchant = normalizeMerchant(merchant);
    final normalizedRaw = normalizeMerchant(rawText);

    final override = _runtimeOverrides[normalizedMerchant];
    if (override != null && override.isNotEmpty) {
      return getCategoryByName(override).name;
    }

    final exact = _merchantCategoryMap[normalizedMerchant];
    if (exact != null) {
      return exact;
    }

    for (final entry in _sortedRules) {
      final key = entry.key;
      if (normalizedMerchant.contains(key) ||
          key.contains(normalizedMerchant)) {
        return entry.value;
      }
    }

    final keywordCategory = categorizeByKeywords(normalizedMerchant);
    if (keywordCategory != null) {
      return keywordCategory;
    }

    for (final entry in _sortedFallbacks) {
      if (normalizedMerchant.contains(entry.key) ||
          normalizedRaw.contains(entry.key)) {
        return entry.value;
      }
    }

    final rawCategory = categorizeByKeywords(rawText);
    if (rawCategory != null) {
      return rawCategory;
    }

    return 'Other';
  }

  static String canonicalizeDisplayName(String rawMerchant) {
    final normalized = normalizeMerchant(rawMerchant);
    if (normalized.isEmpty) return '';
    final exact = _canonicalDisplayNames[normalized];
    if (exact != null) return exact;
    for (final entry in _canonicalDisplayNames.entries) {
      if (normalized.contains(entry.key) || entry.key.contains(normalized)) {
        return entry.value;
      }
    }
    return _titleCase(normalized);
  }

  static String _titleCase(String value) {
    return value
        .split(' ')
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }
}
