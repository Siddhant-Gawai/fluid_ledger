import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../../core/database/local_db.dart';
import '../../../core/database/version_sync.dart';
import '../../../core/sms/sms_parser.dart';
import '../../../core/supabase/supabase_config.dart';
import 'transaction_projection_service.dart';

class TransactionData {
  final String? id;
  final double amount;
  final String category;
  final String date;
  final String? notes;
  final String? userId;
  final String? brand; // matched merchant brand name (e.g. 'Swiggy', 'Amazon')

  TransactionData({
    this.id,
    required this.amount,
    required this.category,
    required this.date,
    this.notes,
    this.userId,
    this.brand,
  });

  Map<String, dynamic> toInsertMap(String userId) {
    return {
      'amount': amount,
      'category': category,
      'date': date,
      'notes': notes,
      'user_id': userId,
      'brand': brand,
    };
  }

  factory TransactionData.fromMap(Map<String, dynamic> map) {
    return TransactionData(
      id: map['id']?.toString(),
      amount: (map['amount'] as num).toDouble(),
      category: map['category'] as String,
      date: map['date'] as String,
      notes: map['notes'] as String?,
      userId: map['user_id'] as String?,
      brand: map['brand'] as String?,
    );
  }
}

class TransactionRepository {
  final SupabaseClient _client;
  final _localDb = LocalDB.instance;
  final _projection = TransactionProjectionService();

  TransactionRepository(this._client);

  String get _userId => _client.auth.currentUser!.id;

  /// Tight enough to catch bank+UPI double-SMS (usually within minutes), loose enough for clock skew.
  static const _dedupeWindow = Duration(hours: 12);
  static const _amountEpsilon = 0.02;

  /// Same spend heuristic for Smart Sync filter and [isDuplicate] (aligned time + amount checks).
  static bool likelySameSpend(TransactionData a, TransactionData b) {
    final da = DateTime.tryParse(a.date);
    final db = DateTime.tryParse(b.date);
    if (da == null || db == null) return false;
    if (da.difference(db).inMilliseconds.abs() > _dedupeWindow.inMilliseconds) {
      return false;
    }
    return (a.amount - b.amount).abs() < _amountEpsilon;
  }

  /// Whether [transaction] matches any row from [existing] (amount + date only maps).
  static bool matchesExistingSpendRows(
    TransactionData transaction,
    List<Map<String, dynamic>> existing,
  ) {
    for (final r in existing) {
      final other = TransactionData(
        amount: (r['amount'] as num).toDouble(),
        category: transaction.category,
        date: (r['date'] ?? '').toString(),
        notes: transaction.notes,
        userId: transaction.userId,
        brand: transaction.brand,
      );
      if (likelySameSpend(transaction, other)) return true;
    }
    return false;
  }

  /// Drop SMS that already map to a ledger row (stops “same transactions” every Smart Sync).
  ///
  /// Uses the same [matchesExistingSpendRows] / [likelySameSpend] rules as [isDuplicate] so the
  /// inbox list cannot disagree with confirm (previously a date-string SQLite window + cloud
  /// `.limit(5000)` could miss rows the confirm step still treated as duplicates).
  Future<List<ParsedSmsTransaction>> filterSmsNotYetInLedger(
    List<ParsedSmsTransaction> incoming,
  ) async {
    if (incoming.isEmpty) return [];

    var rows = await _localDb.getSpendDigestsForUser(_userId);
    if (rows.isEmpty) {
      try {
        final data = await _client
            .from('transactions')
            .select('date, amount')
            .eq('user_id', _userId)
            .order('date', ascending: false)
            .limit(32000);
        rows = List<Map<String, dynamic>>.from(data as List);
      } catch (e) {
        debugPrint('filterSmsNotYetInLedger cloud fallback: $e');
      }
    }

    return incoming.where((sms) {
      final tx = TransactionData(
        amount: sms.amount,
        category: sms.category,
        date: sms.date.toIso8601String(),
        notes: sms.merchant,
        userId: _userId,
        brand: null,
      );
      return !matchesExistingSpendRows(tx, rows);
    }).toList();
  }

  // ---------------------------------------------------------------------------
  // Local-first reads — try SQLite, fallback to Supabase
  // ---------------------------------------------------------------------------

  /// Get transactions from local cache first, fallback to cloud
  Future<List<TransactionData>> getCachedTransactions({
    int page = 0,
    int pageSize = 30,
  }) async {
    try {
      final local = await _localDb.getTransactions(
        page: page,
        pageSize: pageSize,
        userId: _userId,
      );
      if (local.isNotEmpty) {
        return local.map((m) => TransactionData.fromMap(m)).toList();
      }
    } catch (e) {
      debugPrint('Local DB read failed: $e');
    }
    // Fallback to cloud
    return getTransactions(page: page, pageSize: pageSize);
  }

  /// Get summary from local cache first
  Future<List<Map<String, dynamic>>> getCachedSummary() async {
    try {
      final local = await _localDb.getSummary();
      if (local.isNotEmpty) return local;
    } catch (e) {
      debugPrint('Local summary read failed: $e');
    }
    return getTransactionSummary();
  }

  /// Get transactions for a specific month — local first
  Future<List<TransactionData>> getCachedTransactionsForMonth(
    int year,
    int month,
  ) async {
    try {
      final local = await _localDb.getTransactionsForMonth(
        year,
        month,
        _userId,
      );
      if (local.isNotEmpty) {
        return local.map((m) => TransactionData.fromMap(m)).toList();
      }
    } catch (e) {
      debugPrint('Local month read failed: $e');
    }
    return getTransactionsForMonth(year, month);
  }

  Future<List<TransactionData>> searchCachedTransactions({
    required String query,
    int? year,
    int? month,
    int limit = 500,
  }) async {
    try {
      final rows = await _localDb.searchTransactions(
        userId: _userId,
        query: query,
        year: year,
        month: month,
        limit: limit,
      );
      return rows.map((m) => TransactionData.fromMap(m)).toList();
    } catch (e) {
      debugPrint('searchCachedTransactions failed: $e');
      return [];
    }
  }

  Future<MonthlySpendSnapshot?> getCachedMonthlySnapshot(
    int year,
    int month,
  ) async {
    try {
      final cached = await _projection.getMonthlySnapshot(
        userId: _userId,
        year: year,
        month: month,
      );
      if (cached != null) return cached;
      await _projection.recomputeMonth(
        userId: _userId,
        year: year,
        month: month,
      );
      return _projection.getMonthlySnapshot(
        userId: _userId,
        year: year,
        month: month,
      );
    } catch (e) {
      debugPrint('Monthly snapshot read failed: $e');
      return null;
    }
  }

  /// Recent activity feed — keeps the dashboard fast without truncating month analytics.
  Future<List<TransactionData>> getCachedRecentTransactions({
    int limit = 20,
  }) async {
    return getCachedTransactions(pageSize: limit);
  }

  // ---------------------------------------------------------------------------
  // Cloud writes (write to Supabase + update local cache)
  // ---------------------------------------------------------------------------

  Future<void> insertTransaction(TransactionData transaction) async {
    final id = transaction.id ?? const Uuid().v4();
    final now = DateTime.now().toIso8601String();
    final row = {
      'id': id,
      ...transaction.toInsertMap(_userId),
      'created_at': now,
      'updated_at': now,
      'dirty': 1,
      'is_deleted': 0,
      'last_synced_at': null,
      'sync_action': 'upsert',
    };
    await _localDb.upsertTransaction(row);
    await _recomputeTouchedMonths([
      DateTime.tryParse(transaction.date) ?? DateTime.now(),
    ]);
    unawaited(_flushDirtyTransactions());
  }

  /// Bulk insert multiple transactions in a single Supabase call
  Future<void> insertMany(List<TransactionData> transactions) async {
    if (transactions.isEmpty) return;
    final now = DateTime.now().toIso8601String();
    final rows = transactions
        .map(
          (t) => {
            'id': t.id ?? const Uuid().v4(),
            ...t.toInsertMap(_userId),
            'created_at': now,
            'updated_at': now,
            'dirty': 1,
            'is_deleted': 0,
            'last_synced_at': null,
            'sync_action': 'upsert',
          },
        )
        .toList();
    await _localDb.upsertTransactions(rows);
    await _recomputeTouchedMonths(
      transactions
          .map((t) => DateTime.tryParse(t.date) ?? DateTime.now())
          .toList(),
    );
    unawaited(_flushDirtyTransactions());
  }

  Future<void> _upsertInsertedRowsToCache(dynamic inserted) async {
    try {
      final list = inserted as List;
      if (list.isEmpty) return;
      final maps = list
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      await _localDb.upsertTransactions(maps);
      await _recomputeTouchedMonths(
        maps
            .map((row) => DateTime.tryParse((row['date'] ?? '').toString()))
            .whereType<DateTime>()
            .toList(),
      );
    } catch (e) {
      debugPrint('Cache upsert after insert failed: $e');
    }
  }

  Future<void> _recomputeTouchedMonths(List<DateTime> dates) async {
    final touched = <String, DateTime>{};
    for (final date in dates) {
      touched['${date.year}-${date.month}'] = DateTime(date.year, date.month);
    }
    for (final date in touched.values) {
      await _projection.recomputeMonth(
        userId: _userId,
        year: date.year,
        month: date.month,
      );
    }
  }

  Future<void> syncPendingWrites() => _flushDirtyTransactions();

  Future<void> _flushDirtyTransactions() async {
    if (_client.auth.currentUser == null) return;
    final dirtyRows = await _localDb.getDirtyTransactions(_userId);
    if (dirtyRows.isEmpty) return;
    for (final row in dirtyRows) {
      final id = (row['id'] ?? '').toString();
      final action = (row['sync_action'] ?? 'upsert').toString();
      try {
        if (action == 'delete') {
          await _client
              .from('transactions')
              .delete()
              .eq('id', id)
              .eq('user_id', _userId);
          await _localDb.deleteCachedTransaction(id);
        } else {
          final payload = {
            'id': id,
            'amount': (row['amount'] as num?)?.toDouble() ?? 0,
            'category': row['category'],
            'date': row['date'],
            'notes': row['notes'],
            'user_id': _userId,
            'brand': row['brand'],
          };
          final inserted = await _client
              .from('transactions')
              .upsert(payload)
              .select();
          await _upsertInsertedRowsToCache(inserted);
          await _localDb.markTransactionSynced(
            id: id,
            syncedAt: DateTime.now().toIso8601String(),
          );
        }
      } catch (e) {
        debugPrint('Transaction sync failed for $id: $e');
      }
    }
    await _localDb.setSyncMeta(
      'last_transactions_sync',
      DateTime.now().toIso8601String(),
    );
    await VersionSync.instance.bumpVersion(SyncTable.transactions);
  }

  /// Whether a very similar row already exists (local cache and/or Supabase).
  ///
  /// Local is checked first so Smart Sync sees rows just inserted before the next sync.
  /// Uses the same [likelySameSpend] logic as [filterSmsNotYetInLedger] (Dart-parsed dates, not
  /// SQLite string bounds on ISO timestamps).
  Future<bool> isDuplicate(TransactionData transaction) async {
    final dt = DateTime.tryParse(transaction.date);
    if (dt == null) return false;

    final start = dt.subtract(_dedupeWindow).toIso8601String();
    final end = dt.add(_dedupeWindow).toIso8601String();
    final amt = transaction.amount;

    try {
      final nearLocal = await _localDb.getSpendDigestsNearAmount(
        userId: _userId,
        amount: amt,
        epsilon: _amountEpsilon,
      );
      if (matchesExistingSpendRows(transaction, nearLocal)) return true;
    } catch (e) {
      debugPrint('isDuplicate local check: $e');
    }

    final data = await _client
        .from('transactions')
        .select('date, amount')
        .eq('user_id', _userId)
        .gte('amount', amt - _amountEpsilon)
        .lte('amount', amt + _amountEpsilon)
        .gte('date', start)
        .lte('date', end)
        .limit(80);

    final cloudRows = List<Map<String, dynamic>>.from(data as List);
    return matchesExistingSpendRows(transaction, cloudRows);
  }

  /// Get transactions with pagination
  /// [page] starts at 0, [pageSize] defaults to 50
  Future<List<TransactionData>> getTransactions({
    int page = 0,
    int pageSize = 50,
  }) async {
    final from = page * pageSize;
    final to = from + pageSize - 1;

    final data = await _client
        .from('transactions')
        .select()
        .eq('user_id', _userId)
        .order('date', ascending: false)
        .range(from, to);

    return (data as List).map((map) => TransactionData.fromMap(map)).toList();
  }

  /// Get all transactions for a specific month
  Future<List<TransactionData>> getTransactionsForMonth(
    int year,
    int month,
  ) async {
    final start = DateTime(year, month, 1).toIso8601String();
    final end = DateTime(year, month + 1, 1).toIso8601String();

    final data = await _client
        .from('transactions')
        .select()
        .eq('user_id', _userId)
        .gte('date', start)
        .lt('date', end)
        .order('date', ascending: false);

    return (data as List).map((map) => TransactionData.fromMap(map)).toList();
  }

  /// Lightweight summary — only date, amount, category (for month pills + budget)
  Future<List<Map<String, dynamic>>> getTransactionSummary() async {
    final data = await _client
        .from('transactions')
        .select('date, amount, category')
        .eq('user_id', _userId)
        .order('date', ascending: false);
    return List<Map<String, dynamic>>.from(data);
  }

  /// Get ALL transactions (for dashboard summary, categories, etc.)
  Future<List<TransactionData>> getAllTransactions() async {
    final data = await _client
        .from('transactions')
        .select()
        .eq('user_id', _userId)
        .order('date', ascending: false);

    return (data as List).map((map) => TransactionData.fromMap(map)).toList();
  }

  Future<void> deleteTransaction(String id) async {
    try {
      Map<String, dynamic>? local;
      for (final row in await _localDb.getAllTransactions(userId: _userId)) {
        if (row['id'] == id) {
          local = row;
          break;
        }
      }
      final date = (local?['date'] ?? DateTime.now().toIso8601String())
          .toString();
      await _localDb.markTransactionDeletedLocally(
        id: id,
        userId: _userId,
        date: date,
      );
      await _recomputeTouchedMonths([
        DateTime.tryParse(date) ?? DateTime.now(),
      ]);
      unawaited(_flushDirtyTransactions());
    } catch (e) {
      debugPrint('deleteTransaction local cache: $e');
    }
  }

  Future<void> deleteAllTransactions() async {
    await _client.from('transactions').delete().eq('user_id', _userId);
    VersionSync.instance.bumpVersion(SyncTable.transactions);
    try {
      await _localDb.clearTransactions();
      await _localDb.replaceSummary([]);
    } catch (e) {
      debugPrint('deleteAllTransactions local cache: $e');
    }
  }

  Future<void> updateTransaction(String id, TransactionData transaction) async {
    final now = DateTime.now().toIso8601String();
    await _localDb.upsertTransaction({
      'id': id,
      ...transaction.toInsertMap(_userId),
      'updated_at': now,
      'dirty': 1,
      'is_deleted': 0,
      'last_synced_at': null,
      'sync_action': 'upsert',
    });
    await _recomputeTouchedMonths([
      DateTime.tryParse(transaction.date) ?? DateTime.now(),
    ]);
    unawaited(_flushDirtyTransactions());
  }
}

final transactionRepositoryProvider = Provider<TransactionRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return TransactionRepository(client);
});
