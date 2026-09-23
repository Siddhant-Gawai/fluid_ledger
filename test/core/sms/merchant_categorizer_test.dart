import 'package:flutter_test/flutter_test.dart';
import 'package:fluid_ledger/core/sms/merchant_categorizer.dart';
import 'package:fluid_ledger/core/sms/sms_parser.dart';

void main() {
  tearDown(() {
    MerchantCategorizer.registerOverrides(const {});
  });

  test('normalizes merchant names by removing common noise', () {
    expect(
      MerchantCategorizer.normalizeMerchant(
        'Amazon Pay India Pvt Ltd Services',
      ),
      'amazon pay',
    );
  });

  test('maps known merchants to categories', () {
    expect(
      MerchantCategorizer.categorize(
        merchant: 'Swiggy',
        rawText: 'Paid to Swiggy order',
      ),
      'Food',
    );
    expect(
      MerchantCategorizer.categorize(
        merchant: 'Flipkart Online',
        rawText: 'Txn at Flipkart',
      ),
      'Shopping',
    );
    expect(
      MerchantCategorizer.categorize(
        merchant: 'Shoppers Stop',
        rawText: 'Card txn at Shoppers Stop',
      ),
      'Clothing',
    );
    expect(
      MerchantCategorizer.categorize(
        merchant: 'Lifestyle International Pvt Ltd',
        rawText: 'Txn at Lifestyle store',
      ),
      'Clothing',
    );
    expect(
      MerchantCategorizer.categorize(
        merchant: 'Life Style Internation For Inr',
        rawText: 'Life Style Internation For Inr 1811 00',
      ),
      'Clothing',
    );
    expect(
      MerchantCategorizer.categorize(
        merchant: 'Bundl',
        rawText: 'Bundl For Inr 557 00',
      ),
      'Food',
    );
    expect(
      MerchantCategorizer.categorize(
        merchant: 'Cinepolis Nexus Ahmedabad',
        rawText: 'Cinepolis Nexus Ahmedabad',
      ),
      'Entertainment',
    );
    expect(
      MerchantCategorizer.categorize(
        merchant: 'Google Play For Inr 179',
        rawText: 'Google Play For Inr 179',
      ),
      'Subscriptions',
    );
    expect(
      MerchantCategorizer.categorize(
        merchant: 'Zudio Unit Of Trent',
        rawText: 'Zudio Unit Of Trent',
      ),
      'Clothing',
    );
    expect(
      MerchantCategorizer.categorize(
        merchant: 'Madhu Wines For Inr',
        rawText: 'Madhu Wines For Inr 14550',
      ),
      'Entertainment',
    );
    expect(
      MerchantCategorizer.categorize(
        merchant: 'MSEDCL Energy Bill',
        rawText: 'MSEDCL Energy Bill For Consumer',
      ),
      'Utilities',
    );
  });

  test('uses fuzzy merchant matching when exact match is absent', () {
    expect(
      MerchantCategorizer.categorize(
        merchant: 'Amazon Pay India',
        rawText: 'UPI txn to Amazon Pay India',
      ),
      'Shopping',
    );
  });

  test('uses keyword fallback when merchant mapping misses', () {
    expect(
      MerchantCategorizer.categorize(
        merchant: 'Unknown',
        rawText: 'Cash withdrawal at ATM',
      ),
      'Finance',
    );
    expect(
      MerchantCategorizer.categorize(
        merchant: 'Unknown',
        rawText: 'Mobile recharge successful',
      ),
      'Bills',
    );
  });

  test('sms parser category uses improved merchant categorizer', () {
    final parsed = SmsParser.parse(
      'Rs.299 spent via UPI at Netflix Services txn id 123456',
      'HDFCBK',
      DateTime(2025, 1, 10, 12, 30),
    );
    expect(parsed, isNotNull);
    expect(parsed!.category, 'Subscriptions');
  });

  test('runtime override takes precedence over default mapping', () {
    MerchantCategorizer.registerOverrides({'swiggy': 'Utilities'});
    expect(
      MerchantCategorizer.categorize(
        merchant: 'Swiggy',
        rawText: 'Paid to Swiggy',
      ),
      'Utilities',
    );
  });

  test('canonicalizes noisy merchant names for display', () {
    expect(
      MerchantCategorizer.canonicalizeDisplayName('Tata Starbucks For Inr'),
      'Starbucks',
    );
    expect(
      MerchantCategorizer.canonicalizeDisplayName(
        'Life Style Internation For Inr',
      ),
      'Lifestyle',
    );
    expect(
      MerchantCategorizer.canonicalizeDisplayName(
        'Dreamplug Technologi For Inr',
      ),
      'Razorpay',
    );
  });
}
