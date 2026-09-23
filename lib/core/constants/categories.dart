import 'package:flutter/material.dart';

class ExpenseCategory {
  final String name;
  final String emoji;
  final IconData icon;
  final Color color;

  const ExpenseCategory({
    required this.name,
    required this.emoji,
    required this.icon,
    required this.color,
  });
}

const defaultCategories = [
  ExpenseCategory(
    name: 'Food',
    emoji: '🍔',
    icon: Icons.restaurant,
    color: Color(0xFFFF8A65),
  ),
  ExpenseCategory(
    name: 'Shopping',
    emoji: '🛍️',
    icon: Icons.shopping_bag,
    color: Color(0xFF7C4DFF),
  ),
  ExpenseCategory(
    name: 'Clothing',
    emoji: '👕',
    icon: Icons.checkroom,
    color: Color(0xFFFF3E6C),
  ),
  ExpenseCategory(
    name: 'Travel',
    emoji: '✈️',
    icon: Icons.flight_takeoff,
    color: Color(0xFF42A5F5),
  ),
  ExpenseCategory(
    name: 'Groceries',
    emoji: '🥦',
    icon: Icons.local_grocery_store,
    color: Color(0xFF66BB6A),
  ),
  ExpenseCategory(
    name: 'Bills',
    emoji: '📄',
    icon: Icons.receipt_long,
    color: Color(0xFF26A69A),
  ),
  ExpenseCategory(
    name: 'Rent',
    emoji: '🏠',
    icon: Icons.home,
    color: Color(0xFF8D6E63),
  ),
  ExpenseCategory(
    name: 'Health',
    emoji: '💊',
    icon: Icons.favorite,
    color: Color(0xFFEF5350),
  ),
  ExpenseCategory(
    name: 'Entertainment',
    emoji: '🎬',
    icon: Icons.movie,
    color: Color(0xFFEC407A),
  ),
  ExpenseCategory(
    name: 'Education',
    emoji: '📚',
    icon: Icons.school,
    color: Color(0xFF29B6F6),
  ),
  ExpenseCategory(
    name: 'Finance',
    emoji: '💼',
    icon: Icons.account_balance,
    color: Color(0xFF5C6BC0),
  ),
  ExpenseCategory(
    name: 'Fuel',
    emoji: '⛽',
    icon: Icons.local_gas_station,
    color: Color(0xFFFF7043),
  ),
  ExpenseCategory(
    name: 'Utilities',
    emoji: '💡',
    icon: Icons.bolt,
    color: Color(0xFFFFCA28),
  ),
  ExpenseCategory(
    name: 'Subscriptions',
    emoji: '🔄',
    icon: Icons.autorenew,
    color: Color(0xFFAB47BC),
  ),
  ExpenseCategory(
    name: 'Gifts',
    emoji: '🎁',
    icon: Icons.card_giftcard,
    color: Color(0xFFF06292),
  ),
  ExpenseCategory(
    name: 'Other',
    emoji: '📦',
    icon: Icons.category,
    color: Color(0xFF90A4AE),
  ),
];

/// Get category by name (case-insensitive, falls back to Other)
ExpenseCategory getCategoryByName(String name) {
  var key = name.trim().toLowerCase();
  // Older data / SMS used "Transport" — same bucket as Travel
  if (key == 'transport') key = 'travel';
  return defaultCategories.firstWhere(
    (c) => c.name.toLowerCase() == key,
    orElse: () => defaultCategories.last,
  );
}

/// Looks up a per-category amount for the current week. Keys are canonical names; the map may be
/// from [GoalsRepository.getWeeklySpendByCategory] (ledger only) or
/// [GoalsRepository.getWeeklyAttributedSpendByCategory] (ledger + manual “Log spend” rows).
///
/// Weekly targets may still store legacy / mixed-case labels; [getCategoryByName] aligns keys.
double lookupWeeklySpendForCategory(
  Map<String, double> spendByCategory,
  String weeklyTargetCategory,
) {
  final canon = getCategoryByName(weeklyTargetCategory).name;
  return spendByCategory[canon] ??
      spendByCategory[weeklyTargetCategory.trim()] ??
      0;
}

// ---------------------------------------------------------------------------
// Keyword → Category mapping (your dictionary + extras)
// Matched against transaction merchant/notes text
// ---------------------------------------------------------------------------

const categoryKeywordMap = <String, String>{
  // 🍔 FOOD & DINING
  'zomato': 'Food', 'swiggy': 'Food', 'uber eats': 'Food', 'dominos': 'Food',
  'domino': 'Food', 'pizza hut': 'Food', 'kfc': 'Food', 'mcdonalds': 'Food',
  'mcdonald': 'Food',
  'burger king': 'Food',
  'restaurant': 'Food',
  'cafe': 'Food',
  'chai': 'Food', 'coffee': 'Food', 'eat': 'Food', 'dining': 'Food',
  'starbucks': 'Food', 'barista': 'Food', 'subway': 'Food', 'biryani': 'Food',
  'kitchen': 'Food', 'bakery': 'Food', 'pizza': 'Food', 'burger': 'Food',
  'food': 'Food', 'dine': 'Food', 'haldiram': 'Food', 'barbeque': 'Food',
  'tokai': 'Food', 'chaayos': 'Food', 'faasos': 'Food', 'box8': 'Food',
  'eatfit': 'Food', 'behrouz': 'Food',

  // 🛍️ SHOPPING
  'amazon': 'Shopping', 'flipkart': 'Shopping', 'meesho': 'Shopping',
  'myntra': 'Shopping', 'ajio': 'Shopping', 'snapdeal': 'Shopping',
  'shopping': 'Shopping', 'nykaa': 'Shopping', 'tatacliq': 'Shopping',
  'croma': 'Shopping',
  'reliance digital': 'Shopping',
  'vijay sales': 'Shopping',

  // 👕 CLOTHING / APPAREL
  'apparel': 'Clothing', 'clothing': 'Clothing', 'fashion': 'Clothing',
  'garments': 'Clothing', 'zara': 'Clothing', 'h&m': 'Clothing',
  'westside': 'Clothing', 'lifestyle': 'Clothing', 'pantaloons': 'Clothing',
  'max fashion': 'Clothing', 'uniqlo': 'Clothing', 'levis': 'Clothing',
  'allen solly': 'Clothing',
  'van heusen': 'Clothing',
  'peter england': 'Clothing',

  // ✈️ TRAVEL (cabs, transit, flights)
  'uber': 'Travel', 'ola': 'Travel', 'rapido': 'Travel',
  'metro': 'Travel', 'train': 'Travel', 'bus': 'Travel',
  'cab': 'Travel', 'irctc': 'Travel', 'railway': 'Travel',
  'flight': 'Travel', 'makemytrip': 'Travel', 'redbus': 'Travel',
  'goibibo': 'Travel', 'cleartrip': 'Travel', 'indigo': 'Travel',
  'spicejet': 'Travel', 'vistara': 'Travel', 'air india': 'Travel',

  // 🥦 GROCERIES
  'bigbasket': 'Groceries', 'big basket': 'Groceries', 'blinkit': 'Groceries',
  'zepto': 'Groceries', 'grofers': 'Groceries', 'dmart': 'Groceries',
  'grocery': 'Groceries',
  'supermarket': 'Groceries',
  'reliance fresh': 'Groceries',
  'instamart': 'Groceries',
  'jiomart': 'Groceries',
  'more supermarket': 'Groceries',
  'nature basket': 'Groceries', 'dunzo': 'Groceries',

  // 📄 BILLS
  'electricity': 'Bills', 'water bill': 'Bills', 'gas bill': 'Bills',
  'wifi': 'Bills', 'broadband': 'Bills', 'mobile recharge': 'Bills',
  'postpaid': 'Bills', 'prepaid': 'Bills', 'recharge': 'Bills',
  'jio': 'Bills',
  'airtel': 'Bills',
  'vodafone': 'Bills',
  'vodafone idea': 'Bills',
  'bsnl': 'Bills', 'internet': 'Bills', 'dth': 'Bills', 'tata sky': 'Bills',

  // 🏠 RENT
  'rent': 'Rent', 'landlord': 'Rent', 'society': 'Rent',
  'maintenance': 'Rent', 'house rent': 'Rent', 'pg rent': 'Rent',

  // 💊 HEALTH
  'pharmacy': 'Health', 'hospital': 'Health', 'clinic': 'Health',
  'doctor': 'Health', 'medicine': 'Health', 'apollo': 'Health',
  '1mg': 'Health', 'pharmeasy': 'Health', 'netmeds': 'Health',
  'medical': 'Health', 'lab': 'Health', 'diagnostic': 'Health',
  'medplus': 'Health', 'practo': 'Health', 'dental': 'Health',

  // 🎬 ENTERTAINMENT
  'netflix': 'Entertainment', 'amazon prime': 'Entertainment',
  'hotstar': 'Entertainment', 'disney+': 'Entertainment',
  'bookmyshow': 'Entertainment', 'movie': 'Entertainment',
  'gaming': 'Entertainment', 'spotify': 'Entertainment',
  'youtube premium': 'Entertainment', 'pvr': 'Entertainment',
  'inox': 'Entertainment', 'prime video': 'Entertainment',
  'gaana': 'Entertainment', 'jiosaavn': 'Entertainment',
  'apple music': 'Entertainment', 'steam': 'Entertainment',

  // 📚 EDUCATION
  'course': 'Education', 'udemy': 'Education', 'coursera': 'Education',
  'byju': 'Education', 'unacademy': 'Education', 'fees': 'Education',
  'tuition': 'Education', 'school': 'Education', 'college': 'Education',
  'upgrad': 'Education', 'simplilearn': 'Education', 'vedantu': 'Education',
  'toppr': 'Education', 'exam': 'Education',

  // 💼 FINANCE
  'emi': 'Finance', 'loan': 'Finance', 'credit card': 'Finance',
  'interest': 'Finance', 'insurance': 'Finance', 'mutual fund': 'Finance',
  'sip': 'Finance', 'zerodha': 'Finance', 'groww': 'Finance',
  'upstox': 'Finance', 'investment': 'Finance', 'premium': 'Finance',
  'lic': 'Finance', 'policy': 'Finance',

  // ⛽ FUEL
  'petrol': 'Fuel', 'diesel': 'Fuel', 'fuel': 'Fuel',
  'ev charging': 'Fuel',
  'indian oil': 'Fuel',
  'hp petrol': 'Fuel',
  'hindustan petroleum': 'Fuel',
  'iocl': 'Fuel', 'bharat petroleum': 'Fuel', 'shell': 'Fuel',

  // 💡 UTILITIES
  'bescom': 'Utilities', 'tata power': 'Utilities', 'adani': 'Utilities',
  'bses': 'Utilities', 'torrent': 'Utilities',

  // 🎁 GIFTS / OTHER
  'gift': 'Gifts', 'donation': 'Gifts',
};

/// Categorize text using the keyword map — returns category name or null
String? categorizeByKeywords(String text) {
  final lower = text.toLowerCase();
  // Try longer keywords first for better matching (e.g. "amazon prime" before "amazon")
  final sorted = categoryKeywordMap.entries.toList()
    ..sort((a, b) => b.key.length.compareTo(a.key.length));
  for (final entry in sorted) {
    final keyword = entry.key.toLowerCase();
    final pattern = RegExp(
      '(?<![a-z0-9])${RegExp.escape(keyword)}(?![a-z0-9])',
      caseSensitive: false,
    );
    if (pattern.hasMatch(lower)) {
      return entry.value;
    }
  }
  return null;
}

// ---------------------------------------------------------------------------
// Merchant brands with SVG logos
// ---------------------------------------------------------------------------

class MerchantBrand {
  final String name;
  final String emoji;
  final Color color;
  final List<String> keywords;

  const MerchantBrand({
    required this.name,
    required this.emoji,
    required this.color,
    required this.keywords,
  });
}

const merchantBrands = [
  // Food delivery
  MerchantBrand(
    name: 'Swiggy',
    emoji: '🟠',
    color: Color(0xFFFC8019),
    keywords: ['swiggy', 'instamart'],
  ),
  MerchantBrand(
    name: 'Zomato',
    emoji: '🔴',
    color: Color(0xFFE23744),
    keywords: ['zomato'],
  ),
  MerchantBrand(
    name: 'Blinkit',
    emoji: '🟡',
    color: Color(0xFFF7D729),
    keywords: ['blinkit', 'grofers'],
  ),
  MerchantBrand(
    name: 'Zepto',
    emoji: '🟣',
    color: Color(0xFF7B2D8E),
    keywords: ['zepto'],
  ),
  MerchantBrand(
    name: 'BigBasket',
    emoji: '🟢',
    color: Color(0xFF84C225),
    keywords: ['bigbasket', 'big basket'],
  ),
  MerchantBrand(
    name: 'Dunzo',
    emoji: '🏃',
    color: Color(0xFF00D290),
    keywords: ['dunzo'],
  ),

  // Shopping
  MerchantBrand(
    name: 'Amazon',
    emoji: '📦',
    color: Color(0xFFFF9900),
    keywords: ['amazon'],
  ),
  MerchantBrand(
    name: 'Flipkart',
    emoji: '🛒',
    color: Color(0xFF2874F0),
    keywords: ['flipkart'],
  ),
  MerchantBrand(
    name: 'Myntra',
    emoji: '👗',
    color: Color(0xFFFF3E6C),
    keywords: ['myntra'],
  ),
  MerchantBrand(
    name: 'Ajio',
    emoji: '🏷️',
    color: Color(0xFF3E3E3E),
    keywords: ['ajio'],
  ),
  MerchantBrand(
    name: 'Nykaa',
    emoji: '💄',
    color: Color(0xFFFC2779),
    keywords: ['nykaa'],
  ),
  MerchantBrand(
    name: 'Meesho',
    emoji: '🛍️',
    color: Color(0xFF570741),
    keywords: ['meesho'],
  ),

  // Travel
  MerchantBrand(
    name: 'Uber',
    emoji: '🚗',
    color: Color(0xFF000000),
    keywords: ['uber'],
  ),
  MerchantBrand(
    name: 'Ola',
    emoji: '🚕',
    color: Color(0xFF39B54A),
    keywords: ['ola'],
  ),
  MerchantBrand(
    name: 'Rapido',
    emoji: '🏍️',
    color: Color(0xFFFFD300),
    keywords: ['rapido'],
  ),
  MerchantBrand(
    name: 'IRCTC',
    emoji: '🚂',
    color: Color(0xFF1C3A6B),
    keywords: ['irctc', 'railway'],
  ),

  // Entertainment
  MerchantBrand(
    name: 'Netflix',
    emoji: '🎬',
    color: Color(0xFFE50914),
    keywords: ['netflix'],
  ),
  MerchantBrand(
    name: 'Hotstar',
    emoji: '⭐',
    color: Color(0xFF0C2E56),
    keywords: ['hotstar', 'disney+'],
  ),
  MerchantBrand(
    name: 'Spotify',
    emoji: '🎵',
    color: Color(0xFF1DB954),
    keywords: ['spotify'],
  ),
  MerchantBrand(
    name: 'YouTube',
    emoji: '▶️',
    color: Color(0xFFFF0000),
    keywords: ['youtube'],
  ),
  MerchantBrand(
    name: 'Prime Video',
    emoji: '📺',
    color: Color(0xFF00A8E1),
    keywords: ['prime video', 'primevideo'],
  ),

  // Payments
  MerchantBrand(
    name: 'PhonePe',
    emoji: '💜',
    color: Color(0xFF5F259F),
    keywords: ['phonepe'],
  ),
  MerchantBrand(
    name: 'Google Pay',
    emoji: '💳',
    color: Color(0xFF4285F4),
    keywords: ['google pay', 'gpay', 'googlepay'],
  ),
  MerchantBrand(
    name: 'Paytm',
    emoji: '💙',
    color: Color(0xFF00BAF2),
    keywords: ['paytm'],
  ),
  MerchantBrand(
    name: 'CRED',
    emoji: '⬛',
    color: Color(0xFF1A1A2E),
    keywords: ['cred'],
  ),

  // Food chains
  MerchantBrand(
    name: 'Starbucks',
    emoji: '☕',
    color: Color(0xFF00704A),
    keywords: ['starbucks'],
  ),
  MerchantBrand(
    name: "McDonald's",
    emoji: '🍟',
    color: Color(0xFFFFC72C),
    keywords: ['mcdonald'],
  ),
  MerchantBrand(
    name: 'Dominos',
    emoji: '🍕',
    color: Color(0xFF006491),
    keywords: ['domino'],
  ),
  MerchantBrand(
    name: 'KFC',
    emoji: '🍗',
    color: Color(0xFFE4002B),
    keywords: ['kfc'],
  ),
];

/// Match a transaction's notes/merchant to a known brand
MerchantBrand? matchMerchant(String? notes) {
  if (notes == null || notes.isEmpty) return null;
  final lower = notes.toLowerCase();
  for (final brand in merchantBrands) {
    if (brand.keywords.any((k) => lower.contains(k))) {
      return brand;
    }
  }
  return null;
}

// ---------------------------------------------------------------------------
// Bank brands — matched against SMS sender ID
// ---------------------------------------------------------------------------

class BankBrand {
  final String name;
  final String shortName;
  final Color color;
  final List<String> senderKeywords;

  const BankBrand({
    required this.name,
    required this.shortName,
    required this.color,
    required this.senderKeywords,
  });
}

const bankBrands = [
  BankBrand(
    name: 'State Bank of India',
    shortName: 'SBI',
    color: Color(0xFF22409A),
    senderKeywords: ['SBI', 'SBIINB', 'SBICAR', 'SBICRD'],
  ),
  BankBrand(
    name: 'HDFC Bank',
    shortName: 'HDFC',
    color: Color(0xFF004C8F),
    senderKeywords: ['HDFC', 'HDFCBK', 'HDFCCC'],
  ),
  BankBrand(
    name: 'ICICI Bank',
    shortName: 'ICICI',
    color: Color(0xFFB02A30),
    senderKeywords: ['ICICI', 'ICICIB', 'ICICIC'],
  ),
  BankBrand(
    name: 'Axis Bank',
    shortName: 'Axis',
    color: Color(0xFF97144D),
    senderKeywords: ['AXIS', 'AXISBK'],
  ),
  BankBrand(
    name: 'Kotak Mahindra Bank',
    shortName: 'Kotak',
    color: Color(0xFFED1C24),
    senderKeywords: ['KOTAK', 'KOTAKC'],
  ),
  BankBrand(
    name: 'Punjab National Bank',
    shortName: 'PNB',
    color: Color(0xFF1B3A6B),
    senderKeywords: ['PNB', 'PNBSMS'],
  ),
  BankBrand(
    name: 'Union Bank of India',
    shortName: 'Union',
    color: Color(0xFFE8442E),
    senderKeywords: ['UNION', 'UNIBNK'],
  ),
  BankBrand(
    name: 'Bank of Baroda',
    shortName: 'BOB',
    color: Color(0xFFF37A20),
    senderKeywords: ['BOB', 'BOBTXN'],
  ),
  BankBrand(
    name: 'Canara Bank',
    shortName: 'Canara',
    color: Color(0xFF005BAA),
    senderKeywords: ['CANARA', 'CANBNK'],
  ),
  BankBrand(
    name: 'IDFC First',
    shortName: 'IDFC',
    color: Color(0xFF9C1D26),
    senderKeywords: ['IDFC', 'IDFCFB'],
  ),
  BankBrand(
    name: 'Yes Bank',
    shortName: 'Yes',
    color: Color(0xFF0066B3),
    senderKeywords: ['YES', 'YESBK'],
  ),
  BankBrand(
    name: 'IndusInd Bank',
    shortName: 'IndusInd',
    color: Color(0xFF4B0082),
    senderKeywords: ['INDUS'],
  ),
  BankBrand(
    name: 'Federal Bank',
    shortName: 'Federal',
    color: Color(0xFF003399),
    senderKeywords: ['FEDER'],
  ),
  BankBrand(
    name: 'RBL Bank',
    shortName: 'RBL',
    color: Color(0xFF003B71),
    senderKeywords: ['RBL'],
  ),
  BankBrand(
    name: 'Citi Bank',
    shortName: 'Citi',
    color: Color(0xFF003DA5),
    senderKeywords: ['CITI'],
  ),
  BankBrand(
    name: 'HSBC',
    shortName: 'HSBC',
    color: Color(0xFFDB0011),
    senderKeywords: ['HSBC'],
  ),
  BankBrand(
    name: 'Standard Chartered',
    shortName: 'StanC',
    color: Color(0xFF0072AA),
    senderKeywords: ['STAND', 'SCBANK'],
  ),
  BankBrand(
    name: 'AMEX',
    shortName: 'AMEX',
    color: Color(0xFF006FCF),
    senderKeywords: ['AMEX'],
  ),
];

/// Match SMS sender to a bank brand
BankBrand? matchBank(String sender) {
  final upper = sender.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  for (final bank in bankBrands) {
    if (bank.senderKeywords.any((k) => upper.contains(k))) {
      return bank;
    }
  }
  return null;
}
