import '../database/local_db.dart';
import 'merchant_categorizer.dart';

/// Persists merchant-category overrides locally and hydrates categorizer cache.
class MerchantOverrideService {
  MerchantOverrideService._();
  static final MerchantOverrideService instance = MerchantOverrideService._();

  Future<void> hydrateFromLocal() async {
    final rows = await LocalDB.instance.getMerchantOverrides();
    final overrides = <String, String>{};
    for (final row in rows) {
      final key = (row['merchant_key'] ?? '').toString().trim();
      final category = (row['category'] ?? '').toString().trim();
      if (key.isEmpty || category.isEmpty) continue;
      overrides[key] = category;
    }
    MerchantCategorizer.registerOverrides(overrides);
  }

  Future<void> setOverride({
    required String merchant,
    required String category,
  }) async {
    final key = MerchantCategorizer.normalizeMerchant(merchant);
    if (key.isEmpty || category.trim().isEmpty) return;
    await LocalDB.instance.upsertMerchantOverride(
      merchantKey: key,
      category: category.trim(),
      dirty: true,
    );
    await hydrateFromLocal();
  }

  Future<void> removeOverride(String merchant) async {
    final key = MerchantCategorizer.normalizeMerchant(merchant);
    if (key.isEmpty) return;
    await LocalDB.instance.markMerchantOverrideDeleted(merchantKey: key);
    await hydrateFromLocal();
  }

  Future<Map<String, String>> getOverrides() async {
    final rows = await LocalDB.instance.getMerchantOverrides();
    final map = <String, String>{};
    for (final row in rows) {
      final key = (row['merchant_key'] ?? '').toString().trim();
      final category = (row['category'] ?? '').toString().trim();
      if (key.isNotEmpty && category.isNotEmpty) {
        map[key] = category;
      }
    }
    return map;
  }
}
