import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/local_db.dart';
import '../../../core/supabase/supabase_config.dart';

class MonthlySpendSnapshot {
  final int year;
  final int month;
  final double totalSpend;
  final int transactionCount;
  final int categoryCount;
  final String? lastTransactionAt;
  final Map<String, double> categoryTotals;

  const MonthlySpendSnapshot({
    required this.year,
    required this.month,
    required this.totalSpend,
    required this.transactionCount,
    required this.categoryCount,
    required this.lastTransactionAt,
    required this.categoryTotals,
  });
}

class TransactionProjectionService {
  TransactionProjectionService();

  final LocalDB _localDb = LocalDB.instance;

  Future<void> recomputeMonth({
    required String userId,
    required int year,
    required int month,
    String? lastSyncedAt,
  }) async {
    final rows = await _localDb.getTransactionsForMonth(year, month, userId);
    final now = DateTime.now().toIso8601String();
    final categoryTotals = <String, double>{};
    var totalSpend = 0.0;
    String? lastTransactionAt;

    for (final row in rows) {
      final amount = (row['amount'] as num?)?.toDouble() ?? 0;
      final category = (row['category'] as String?) ?? 'Other';
      final date = row['date'] as String?;
      totalSpend += amount;
      categoryTotals[category] = (categoryTotals[category] ?? 0) + amount;
      if (date != null &&
          (lastTransactionAt == null ||
              date.compareTo(lastTransactionAt) > 0)) {
        lastTransactionAt = date;
      }
    }

    await _localDb.replaceMonthlyAggregate(
      userId: userId,
      year: year,
      month: month,
      totalSpend: totalSpend,
      transactionCount: rows.length,
      categoryCount: categoryTotals.length,
      lastTransactionAt: lastTransactionAt,
      updatedAt: now,
      lastSyncedAt: lastSyncedAt,
    );

    await _localDb.replaceMonthlyCategoryTotals(
      userId: userId,
      year: year,
      month: month,
      rows: categoryTotals.entries
          .map(
            (entry) => {
              'user_id': userId,
              'year': year,
              'month': month,
              'category': entry.key,
              'total_spend': entry.value,
              'transaction_count': rows
                  .where((row) => row['category'] == entry.key)
                  .length,
              'updated_at': now,
              'last_synced_at': lastSyncedAt,
            },
          )
          .toList(),
    );

    await _localDb.rebuildSummaryFromTransactions(userId);
  }

  Future<MonthlySpendSnapshot?> getMonthlySnapshot({
    required String userId,
    required int year,
    required int month,
  }) async {
    final aggregate = await _localDb.getMonthlyAggregate(
      userId: userId,
      year: year,
      month: month,
    );
    if (aggregate == null) return null;
    final categories = await _localDb.getMonthlyCategoryTotals(
      userId: userId,
      year: year,
      month: month,
    );
    return MonthlySpendSnapshot(
      year: year,
      month: month,
      totalSpend: (aggregate['total_spend'] as num?)?.toDouble() ?? 0,
      transactionCount: (aggregate['transaction_count'] as num?)?.toInt() ?? 0,
      categoryCount: (aggregate['category_count'] as num?)?.toInt() ?? 0,
      lastTransactionAt: aggregate['last_transaction_at'] as String?,
      categoryTotals: {
        for (final row in categories)
          (row['category'] as String? ?? 'Other'):
              (row['total_spend'] as num?)?.toDouble() ?? 0,
      },
    );
  }
}

final transactionProjectionServiceProvider =
    Provider<TransactionProjectionService>((ref) {
      ref.watch(supabaseClientProvider);
      return TransactionProjectionService();
    });
