import 'package:fluid_ledger/core/sms/sms_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses debit SMS into a transaction with amount and merchant', () {
    final parsed = SmsParser.parse(
      'Rs. 245 debited for purchase at Swiggy using HDFC Bank Card on 12-04.',
      'HDFCBK',
      DateTime(2025, 4, 12, 20, 15),
    );

    expect(parsed, isNotNull);
    expect(parsed!.type, 'debit');
    expect(parsed.amount, 245);
    expect(parsed.merchant, contains('Swiggy'));
    expect(parsed.category, isNotEmpty);
  });

  test('skips OTP-like messages', () {
    final parsed = SmsParser.parse(
      'Your OTP is 438921. Do not share it with anyone. Valid for 10 min.',
      'HDFCBK',
      DateTime(2025, 4, 12, 20, 15),
    );

    expect(parsed, isNull);
  });

  test('extracts merchant from VPA handle', () {
    final parsed = SmsParser.parse(
      'Rs. 480 paid via UPI to swiggy@okaxis UPI Ref no 123456789012',
      'ICICIB',
      DateTime(2025, 4, 12, 20, 15),
    );

    expect(parsed, isNotNull);
    expect(parsed!.merchant, contains('Swiggy'));
    expect(parsed.type, 'debit');
  });

  test('detects debit wording variant "deducted"', () {
    final parsed = SmsParser.parse(
      'INR 1200 deducted from a/c for transaction on Amazon',
      'SBIBNK',
      DateTime(2025, 4, 12, 20, 15),
    );

    expect(parsed, isNotNull);
    expect(parsed!.type, 'debit');
    expect(parsed.amount, 1200);
  });

  test('canonicalizes merchant names from noisy sms text', () {
    final parsed = SmsParser.parse(
      'Rs. 635 debited at Tata Starbucks For Inr 635.00 ref 12345',
      'AXISBK',
      DateTime(2026, 4, 25, 19, 15),
    );

    expect(parsed, isNotNull);
    expect(parsed!.merchant, 'Starbucks');
    expect(parsed.category, 'Food');
  });
}
