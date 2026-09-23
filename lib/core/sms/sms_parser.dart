import 'dart:math' as math;

import 'merchant_categorizer.dart';

/// Parsed transaction from an SMS message
class ParsedSmsTransaction {
  final double amount;
  final String type; // 'debit' or 'credit'
  final String merchant;
  final DateTime date;
  final String rawSms;
  final String sender;

  ParsedSmsTransaction({
    required this.amount,
    required this.type,
    required this.merchant,
    required this.date,
    required this.rawSms,
    required this.sender,
  });

  /// Auto-categorize — tries merchant name first, then full SMS body
  String get category {
    return MerchantCategorizer.categorize(merchant: merchant, rawText: rawSms);
  }
}

/// Simple, effective parser for Indian bank SMS
class SmsParser {
  /// Bump when skip rules / heuristics change materially — triggers a one-time wide re-scan.
  static const int parserVersion = 4;

  /// Amount regex — matches ₹, INR, Rs, Rs. followed by amount
  static final _amountRegex = RegExp(
    r'(₹|inr|rs\.?)\s?([\d,]+\.?\d*)',
    caseSensitive: false,
  );

  /// UTR / ref patterns (Indian bank + UPI)
  static final _utrPatterns = <RegExp>[
    RegExp(
      r'(?:utr|utr no|utr:?)\s*[:\s]*([0-9]{12,22})',
      caseSensitive: false,
    ),
    RegExp(
      r'(?:ref|rrn|txn id|transaction id|trxn id|trn id|no\.?|id)[\s:.]*([0-9]{10,22})',
      caseSensitive: false,
    ),
    RegExp(
      r'(?:upi|imps|neft|rtgs)[^\d]{0,24}([0-9]{12,22})',
      caseSensitive: false,
    ),
  ];

  static final _creditPattern = RegExp(
    r'(?:credited|credit|deposited|added|received|refund|repayment|cashback)\b',
    caseSensitive: false,
  );

  static final _debitPattern = RegExp(
    r'(?:debited|debit|deducted|withdrawn|spent|paid|payment|charged|used\s+at|'
    r'transaction\s+on|tran\b|booked|purchased|purchase\s+of|sent\s+to)\b',
    caseSensitive: false,
  );

  static const List<String> _upiKeywords = <String>[
    'upi ref no',
    'upi ref',
    'ref no',
    'utr',
    'txn id',
    'transaction id',
    'rrn',
  ];

  // Borrowed and adapted from transaction-sms-parser-main for better VPA detection.
  static const List<String> _upiHandleSuffixes = <String>[
    '@upi',
    '@okhdfcbank',
    '@okaxis',
    '@oksbi',
    '@okicici',
    '@paytm',
    '@ybl',
    '@ibl',
    '@axl',
    '@sbi',
    '@icici',
    '@kotak',
    '@hdfcbank',
    '@yesbank',
    '@yesg',
    '@axisbank',
    '@federal',
    '@unionbank',
    '@uboi',
    '@airtel',
    '@apl',
  ];

  /// Fingerprint for deduping duplicate bank + UPI SMS for the same spend.
  static String fingerprint(ParsedSmsTransaction t) {
    final minute = t.date.millisecondsSinceEpoch ~/ 60000;
    final amt = t.amount.toStringAsFixed(2);
    final utr = extractUtr(t.rawSms);
    if (utr != null && utr.isNotEmpty) return '$minute|$amt|$utr';
    final m = t.merchant.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    final norm = m.length > 24 ? m.substring(0, 24) : m;
    return '$minute|$amt|$norm';
  }

  /// Best-effort UTR / bank ref extraction from raw SMS.
  static String? extractUtr(String raw) {
    final s = raw.toLowerCase();
    for (final p in _utrPatterns) {
      final m = p.firstMatch(s);
      if (m != null) {
        final g = m.group(1);
        if (g != null && g.length >= 10) return g;
      }
    }
    return null;
  }

  /// When two SMS map to the same [fingerprint], keep the richer candidate (better merchant / UTR in body).
  static ParsedSmsTransaction pickRicher(
    ParsedSmsTransaction a,
    ParsedSmsTransaction b,
  ) {
    int score(ParsedSmsTransaction t) {
      var s = t.rawSms.length;
      if (t.merchant != 'Unknown') s += 500;
      if (extractUtr(t.rawSms) != null) s += 200;
      return s;
    }

    return score(b) > score(a) ? b : a;
  }

  /// Messages to skip
  static bool _shouldSkip(String msg) {
    if (_looksLikeOtpOrAuthCode(msg)) return true;

    // OTP messages — strict check first
    if (RegExp(r'\botp\b', caseSensitive: false).hasMatch(msg)) return true;
    if (msg.contains('one time password')) return true;
    if (msg.contains('do not share')) return true;
    if (msg.contains('valid for') && msg.contains('min')) return true;
    if (msg.contains('ref:') && msg.contains('txn')) {
      return true; // OTP reference SMS
    }

    return msg.contains('cvv') ||
        msg.contains('generate pin') ||
        msg.contains('set your pin') ||
        // Loan / credit offers
        msg.contains('apply now') ||
        msg.contains('pre-approved') ||
        msg.contains('pre approved') ||
        msg.contains('eligible for loan') ||
        msg.contains('disbursal') ||
        msg.contains('disbursement') ||
        msg.contains('loan offer') ||
        msg.contains('credit limit') ||
        msg.contains('limit increased') ||
        msg.contains('limit enhancement') ||
        msg.contains('confirm your tenure') ||
        msg.contains('acquisition loan') ||
        msg.contains('emi conversion') ||
        msg.contains('convert to emi') ||
        msg.contains('flexi pay') ||
        msg.contains('smartemi') ||
        msg.contains('insta emi') ||
        msg.contains('click to avail') ||
        msg.contains('avail now') ||
        msg.contains('access to funds') ||
        // Promo / marketing
        msg.contains('cashback earn') ||
        msg.contains('reward points') ||
        msg.contains('upgrade your') ||
        msg.contains('congratulations') ||
        msg.contains('exclusive offer') ||
        msg.contains('limited period') ||
        msg.contains('special offer') ||
        // Account alerts (not transactions)
        msg.contains('minimum amount due') ||
        msg.contains('payment due date') ||
        msg.contains('bill generated') ||
        msg.contains('statement ready') ||
        msg.contains('autopay') ||
        msg.contains('auto-pay') ||
        msg.contains('mandate') ||
        msg.contains('nach') ||
        msg.contains('verification code') ||
        msg.contains('login code') ||
        msg.contains('sign-in code') ||
        msg.contains('security code') ||
        msg.contains('never share') ||
        msg.contains('do not disclose') ||
        msg.contains('sms banking password') ||
        // Balance check / enquiry (parentheses: avoid mixing && with || incorrectly)
        (msg.contains('available balance') &&
            !msg.contains('debited') &&
            !msg.contains('credited')) ||
        (msg.contains('bal ') && msg.length < 80 && !msg.contains('debited'));
  }

  /// Short, digit-heavy “code” SMS that are not spends.
  static bool _looksLikeOtpOrAuthCode(String msg) {
    final t = msg.trim();
    if (t.length > 140) return false;
    final digitCount = RegExp(r'\d').allMatches(t).length;
    if (digitCount < 4) return false;
    final ratio = digitCount / math.max(t.length, 1);
    if (ratio < 0.25) return false;
    return RegExp(
      r'otp|password|passcode|pin\b|verification|authenticate|login|sign[\s-]?in|'
      r'2fa|two[\s-]?factor|secure\s*code|auth\s*code|is\s+your|use\s+\d',
      caseSensitive: false,
    ).hasMatch(t);
  }

  /// Parse SMS body into a transaction, or null if not a transaction
  static ParsedSmsTransaction? parse(
    String message,
    String sender,
    DateTime date,
  ) {
    final msg = message.toLowerCase();

    // Skip non-transaction messages
    if (_shouldSkip(msg)) return null;

    // Detect transaction type using regex patterns to cover bank wording variants.
    String type;
    if (_debitPattern.hasMatch(msg) || msg.contains('dr ')) {
      type = 'debit';
    } else if (_creditPattern.hasMatch(msg) || msg.contains('cr ')) {
      type = 'credit';
    } else {
      return null;
    }

    // Credit card spends — SMS says "credit card" but it's a debit
    if ((msg.contains('credit card') || msg.contains('cr card')) &&
        (msg.contains('spent') ||
            msg.contains('txn') ||
            msg.contains('used') ||
            msg.contains('charged') ||
            msg.contains('purchase') ||
            msg.contains('debited') ||
            msg.contains('payment'))) {
      type = 'debit';
    }

    // Extract amount
    final amountMatch = _amountRegex.firstMatch(msg);
    if (amountMatch == null) return null;

    final amountStr = (amountMatch.group(2) ?? '').replaceAll(',', '');
    final amount = double.tryParse(amountStr) ?? 0;
    if (amount <= 0) return null;

    // Extract merchant
    String merchant = _extractMerchant(msg);

    return ParsedSmsTransaction(
      amount: amount,
      type: type,
      merchant: merchant,
      date: date,
      rawSms: message,
      sender: sender,
    );
  }

  /// Extract merchant name using multiple heuristics
  static String _extractMerchant(String msg) {
    // 1) Explicit VPA marker: "... vpa abc@okaxis ..."
    final vpaKeywordMatch = RegExp(
      r'\bvpa\b[:\s()-]*([a-z0-9._-]+@[a-z0-9._-]+)',
      caseSensitive: false,
    ).firstMatch(msg);
    if (vpaKeywordMatch != null) {
      final merchant = _merchantFromVpa(vpaKeywordMatch.group(1) ?? '');
      if (merchant.isNotEmpty) return merchant;
    }

    // 2) Any UPI handle in text, adapted from transaction-sms-parser-main.
    final handlePattern = _upiHandleSuffixes.map(RegExp.escape).join('|');
    final handleMatch = RegExp(
      r'([a-z0-9._-]+(?:' + handlePattern + r'))\b',
      caseSensitive: false,
    ).firstMatch(msg);
    if (handleMatch != null) {
      final merchant = _merchantFromVpa(handleMatch.group(1) ?? '');
      if (merchant.isNotEmpty) return merchant;
    }

    // Try patterns in order of specificity
    for (final prefix in ['at ', 'to ', 'from ', 'via ', 'towards ', 'on ']) {
      if (msg.contains(prefix)) {
        final parts = msg.split(prefix);
        if (parts.length > 1) {
          final afterPrefix = parts[1];
          // Take words until we hit a stop pattern
          final merchant = afterPrefix
              .split(
                RegExp(
                  r'(\s+on\s+|\s+for\s+|\s+ref|\s+upi|\s+\d{2}[/-]|\.\s|avl\s|bal\s|a/c|acct|ifsc)',
                ),
              )
              .first;
          final cleaned = _cleanMerchant(merchant);
          if (cleaned.isNotEmpty) return cleaned;
        }
      }
    }

    // 3) Parse words after UPI/ref keywords when present.
    for (final keyword in _upiKeywords) {
      final candidate = _extractWordsAfterKeyword(msg, keyword);
      if (candidate.isNotEmpty) {
        final cleaned = _cleanMerchant(candidate);
        if (cleaned.isNotEmpty) return cleaned;
      }
    }

    // Try "Info:" pattern
    final infoMatch = RegExp(
      r'info[:\s]+([a-zA-Z][\w\s&\-.]+?)(?:\s+ref|\s*$)',
      caseSensitive: false,
    ).firstMatch(msg);
    if (infoMatch != null) {
      final cleaned = _cleanMerchant(infoMatch.group(1) ?? '');
      if (cleaned.isNotEmpty) return cleaned;
    }

    return 'Unknown';
  }

  static String _merchantFromVpa(String vpa) {
    final localPart = vpa.split('@').first;
    final cleaned = localPart.replaceAll(RegExp(r'[^a-zA-Z]'), ' ').trim();
    final merchant = _cleanMerchant(cleaned);
    return merchant;
  }

  static String _extractWordsAfterKeyword(String msg, String keyword) {
    final idx = msg.indexOf(keyword);
    if (idx < 0 || idx + keyword.length >= msg.length) return '';
    final tail = msg.substring(idx + keyword.length).trim();
    if (tail.isEmpty) return '';
    final token = tail.split(RegExp(r'\s+')).first;
    if (RegExp(r'^[0-9]{6,}$').hasMatch(token)) return '';
    return tail
        .split(
          RegExp(
            r'(\s+on\s+|\s+at\s+|\s+to\s+|\s+from\s+|\s+via\s+|\s+ref\b|\s+upi\b|'
            r'\s+for\s+|\s+avl\b|\s+bal\b|\s+a/c\b|\s+acct\b|[\.,;])',
          ),
        )
        .first;
  }

  static String _cleanMerchant(String raw) {
    final canonical = MerchantCategorizer.canonicalizeDisplayName(raw);
    if (canonical.isEmpty) return '';
    var cleaned = canonical.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleaned.length > 32) cleaned = cleaned.substring(0, 32).trim();
    return cleaned;
  }
}
