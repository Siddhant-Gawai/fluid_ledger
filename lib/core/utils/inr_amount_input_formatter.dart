import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

/// Formats numeric input using Indian grouping (3-2-2...), e.g.
/// 1234 -> 1,234 and 1234567 -> 12,34,567.
///
/// - Accepts digits only (you can pair with [FilteringTextInputFormatter.digitsOnly]).
/// - Preserves cursor position based on the number of digits to the left.
class InrAmountInputFormatter extends TextInputFormatter {
  InrAmountInputFormatter({NumberFormat? formatter})
      : _fmt = formatter ?? NumberFormat('#,##,##0', 'en_IN');

  final NumberFormat _fmt;

  static String _digitsOnly(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

  static int _countDigitsLeftOfSelection(String text, int selectionOffset) {
    final clamped = selectionOffset.clamp(0, text.length);
    return _digitsOnly(text.substring(0, clamped)).length;
  }

  static int _selectionOffsetForDigitIndex(String formatted, int digitIndex) {
    if (digitIndex <= 0) return 0;
    var seen = 0;
    for (var i = 0; i < formatted.length; i++) {
      final c = formatted.codeUnitAt(i);
      final isDigit = c >= 48 && c <= 57;
      if (isDigit) seen++;
      if (seen >= digitIndex) return i + 1;
    }
    return formatted.length;
  }

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    // Let empty input be empty.
    final digits = _digitsOnly(newValue.text);
    if (digits.isEmpty) {
      return const TextEditingValue(text: '', selection: TextSelection.collapsed(offset: 0));
    }

    // Avoid int overflow: keep only last 15 digits (₹ amounts won't need more).
    final safeDigits = digits.length > 15 ? digits.substring(digits.length - 15) : digits;
    final number = int.tryParse(safeDigits);
    if (number == null) return oldValue;

    final formatted = _fmt.format(number);

    // Keep caret stable: map "digits left of caret" to formatted string.
    final digitsLeft = _countDigitsLeftOfSelection(newValue.text, newValue.selection.baseOffset);
    final newOffset = _selectionOffsetForDigitIndex(formatted, digitsLeft);

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: newOffset),
    );
  }
}

