import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../supabase/supabase_config.dart';
import 'local_db.dart';
import '../../features/expense/data/transaction_projection_service.dart';
import '../../features/expense/data/transaction_repository.dart';

/// Handles cloud ↔ local SQLite synchronization
/// Auto-retries on network failure with exponential backoff
class SyncService {
  static final SyncService instance = SyncService._();
  SyncService._();

  final _localDb = LocalDB.instance;
  final _txProjection = TransactionProjectionService();
  static const _maxRetries = 3;

  SupabaseClient get _client => appSupabaseClient;
  String? get _userId => _client.auth.currentUser?.id;

  /// Serialize [fullSync] / [deltaSync] so concurrent callers (main + dashboard + history) do not
  /// skip work because `_syncing` short-circuited mid-flight.
  Future<void> _opChain = Future.value();

  Future<T> _serialized<T>(Future<T> Function() fn) {
    final completer = Completer<T>();
    _opChain = _opChain.then((_) async {
      try {
        completer.complete(await fn());
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  // ---------------------------------------------------------------------------
  // Full sync — pulls everything from Supabase into SQLite
  // ---------------------------------------------------------------------------

  Future<void> fullSync() => _serialized(_fullSyncImpl);

  Future<void> _fullSyncImpl() async {
    if (_userId == null) return;
    debugPrint('SyncService: starting full sync');

    try {
      final txData = await _client
          .from('transactions')
          .select()
          .eq('user_id', _userId!)
          .order('date', ascending: false);

      final txRows = (txData as List)
          .map(
            (m) => <String, dynamic>{
              'id': m['id'].toString(),
              'amount': (m['amount'] as num).toDouble(),
              'category': m['category'] as String,
              'date': m['date'] as String,
              'notes': m['notes'] as String?,
              'user_id': m['user_id'] as String?,
              'brand': m['brand'] as String?,
              'created_at': m['created_at'] as String?,
              'updated_at': m['updated_at'] as String?,
            },
          )
          .toList();

      await _localDb.clearTransactions();
      await _localDb.upsertTransactions(txRows);
      await _rebuildTransactionCaches(uid: _userId!);

      final profileData = await _client
          .from('profiles')
          .select()
          .eq('id', _userId!)
          .maybeSingle();

      if (profileData != null) {
        await _localDb.upsertProfile({
          'id': profileData['id'],
          'name': profileData['name'],
          'age': profileData['age'],
          'email': profileData['email'],
          'phone': profileData['phone'],
          'avatar_index': profileData['avatar_index'] ?? 0,
          'monthly_budget':
              (profileData['monthly_budget'] as num?)?.toDouble() ?? 50000,
          'created_at': profileData['created_at'],
        });
      }

      await _localDb.setSyncMeta(
        'last_full_sync',
        DateTime.now().toIso8601String(),
      );
      await flushPendingWrites();
      debugPrint(
        'SyncService: full sync complete — ${txRows.length} transactions',
      );
    } catch (e) {
      debugPrint('SyncService: full sync failed — $e');
      _retryLater(() => fullSync(), 'fullSync');
    }
  }

  // ---------------------------------------------------------------------------
  // Delta sync — pulls rows newer than the newest `created_at` already in SQLite
  // ---------------------------------------------------------------------------

  Future<bool> deltaSync() => _serialized(_deltaSyncImpl);

  Future<bool> _deltaSyncImpl() async {
    if (_userId == null) return false;

    try {
      final uid = _userId!;
      final cachedCount = await _localDb.countTransactionsForUser(uid);
      final maxCreated = await _localDb.maxTransactionCreatedAtForUser(uid);

      // Empty cache or legacy rows missing created_at → full replace (same as fresh login).
      if (cachedCount == 0 || maxCreated == null || maxCreated.isEmpty) {
        await _fullSyncImpl();
        return true;
      }

      final newData = await _client
          .from('transactions')
          .select()
          .eq('user_id', uid)
          .gt('created_at', maxCreated)
          .order('date', ascending: false);

      final newRows = (newData as List)
          .map(
            (m) => <String, dynamic>{
              'id': m['id'].toString(),
              'amount': (m['amount'] as num).toDouble(),
              'category': m['category'] as String,
              'date': m['date'] as String,
              'notes': m['notes'] as String?,
              'user_id': m['user_id'] as String?,
              'brand': m['brand'] as String?,
              'created_at': m['created_at'] as String?,
              'updated_at': m['updated_at'] as String?,
            },
          )
          .toList();

      if (newRows.isNotEmpty) {
        await _localDb.upsertTransactions(newRows);
        await _rebuildTransactionCaches(uid: uid);
        debugPrint(
          'SyncService: delta sync — ${newRows.length} new transactions',
        );
      }

      final profileData = await _client
          .from('profiles')
          .select()
          .eq('id', uid)
          .maybeSingle();
      if (profileData != null) {
        await _localDb.upsertProfile({
          'id': profileData['id'],
          'name': profileData['name'],
          'age': profileData['age'],
          'email': profileData['email'],
          'phone': profileData['phone'],
          'avatar_index': profileData['avatar_index'] ?? 0,
          'monthly_budget':
              (profileData['monthly_budget'] as num?)?.toDouble() ?? 50000,
          'created_at': profileData['created_at'],
        });
      }

      await _localDb.setSyncMeta(
        'last_full_sync',
        DateTime.now().toIso8601String(),
      );
      await flushPendingWrites();
      return newRows.isNotEmpty;
    } catch (e) {
      debugPrint('SyncService: delta sync failed — $e');
      _retryLater(() => deltaSync(), 'deltaSync');
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Auto-retry with exponential backoff (silent, background)
  // ---------------------------------------------------------------------------

  final Map<String, int> _retryCount = {};

  void _retryLater(Future<void> Function() operation, String tag) {
    final count = _retryCount[tag] ?? 0;
    if (count >= _maxRetries) {
      debugPrint('SyncService: $tag — max retries reached, giving up');
      _retryCount.remove(tag);
      return;
    }

    final delay = Duration(seconds: 5 * (count + 1));
    debugPrint(
      'SyncService: $tag — retrying in ${delay.inSeconds}s (attempt ${count + 1}/$_maxRetries)',
    );
    _retryCount[tag] = count + 1;

    Future.delayed(delay, () async {
      try {
        await operation();
        _retryCount.remove(tag);
        debugPrint('SyncService: $tag — retry succeeded');
      } catch (e) {
        debugPrint('SyncService: $tag — retry failed: $e');
        _retryLater(operation, tag);
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Check if local cache has data
  // ---------------------------------------------------------------------------

  Future<bool> hasCachedData() async {
    final lastSync = await _localDb.getSyncMeta('last_full_sync');
    return lastSync != null;
  }

  // ---------------------------------------------------------------------------
  // Clear on logout
  // ---------------------------------------------------------------------------

  Future<void> clearCache() async {
    await _localDb.clearAll();
  }

  Future<void> flushPendingWrites() async {
    if (_userId == null) return;
    await TransactionRepository(_client).syncPendingWrites();
  }

  Future<void> _rebuildTransactionCaches({required String uid}) async {
    await _localDb.rebuildSummaryFromTransactions(uid);
    final allRows = await _localDb.getAllTransactions(userId: uid);
    final touchedMonths = <String, DateTime>{};
    for (final row in allRows.where((row) => row['user_id'] == uid)) {
      final date = DateTime.tryParse((row['date'] ?? '').toString());
      if (date == null) continue;
      touchedMonths['${date.year}-${date.month}'] = DateTime(
        date.year,
        date.month,
      );
    }
    for (final month in touchedMonths.values) {
      await _txProjection.recomputeMonth(
        userId: uid,
        year: month.year,
        month: month.month,
        lastSyncedAt: DateTime.now().toIso8601String(),
      );
    }
  }
}
