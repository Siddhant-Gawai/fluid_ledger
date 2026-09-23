import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../supabase/supabase_config.dart';
import 'local_db.dart';

/// Table names used for version tracking
class SyncTable {
  static const transactions = 'transactions';
  static const profiles = 'profiles';
  static const splitGroups = 'split_groups';
  static const groupMembers = 'group_members';
  static const splitExpenses = 'split_expenses';
  static const settlements = 'settlements';
  /// Matches Supabase table `weekly_manual_spend_logs`.
  static const weeklyManualSpendLogs = 'weekly_manual_spend_logs';

  static const all = [
    transactions,
    profiles,
    splitGroups,
    groupMembers,
    splitExpenses,
    settlements,
    weeklyManualSpendLogs,
  ];
}

/// Per-table version sync — only syncs what changed
class VersionSync {
  static final VersionSync instance = VersionSync._();
  VersionSync._();

  final _localDb = LocalDB.instance;
  SupabaseClient get _client => appSupabaseClient;
  String? get _userId => _client.auth.currentUser?.id;

  /// Check remote versions and sync only stale tables
  /// Returns list of table names that were synced
  Future<List<String>> syncStale() async {
    if (_userId == null) return [];

    try {
      // 1. Fetch all remote versions in ONE query
      final remoteData = await _client
          .from('user_sync_versions')
          .select('table_name, version')
          .eq('user_id', _userId!);

      final remoteVersions = <String, int>{};
      for (final row in (remoteData as List)) {
        remoteVersions[row['table_name'] as String] = (row['version'] as int?) ?? 0;
      }

      // 2. Get all local versions
      final localVersions = await _localDb.getAllLocalVersions();

      // 3. Find which tables are stale
      final stale = <String>[];
      for (final table in SyncTable.all) {
        final remote = remoteVersions[table] ?? 0;
        final local = localVersions[table] ?? 0;
        if (remote > local) {
          stale.add(table);
        }
      }

      if (stale.isEmpty) {
        debugPrint('VersionSync: all tables up to date');
        return [];
      }

      debugPrint('VersionSync: stale tables: $stale');

      // 4. Sync only stale tables
      for (final table in stale) {
        await _syncTable(table);
        await _localDb.setLocalVersion(table, remoteVersions[table] ?? 0);
      }

      return stale;
    } catch (e) {
      debugPrint('VersionSync: sync failed — $e');
      return [];
    }
  }

  /// Sync a single table from Supabase to SQLite
  Future<void> _syncTable(String table) async {
    final uid = _userId!;
    debugPrint('VersionSync: syncing $table');

    switch (table) {
      case SyncTable.transactions:
        final data = await _client.from('transactions').select().eq('user_id', uid).order('date', ascending: false);
        final rows = (data as List).map((m) => <String, dynamic>{
          'id': m['id'].toString(), 'amount': (m['amount'] as num).toDouble(),
          'category': m['category'] as String, 'date': m['date'] as String,
          'notes': m['notes'] as String?, 'user_id': m['user_id'] as String?,
          'brand': m['brand'] as String?, 'created_at': m['created_at'] as String?,
          'updated_at': m['updated_at'] as String?,
        }).toList();
        await _localDb.clearTransactions();
        await _localDb.upsertTransactions(rows);
        // Also refresh summary
        final summary = await _client.from('transactions').select('date, amount, category').eq('user_id', uid);
        await _localDb.replaceSummary(List<Map<String, dynamic>>.from(summary));
        break;

      case SyncTable.profiles:
        final data = await _client.from('profiles').select().eq('id', uid).maybeSingle();
        if (data != null) {
          await _localDb.upsertProfile({
            'id': data['id'], 'name': data['name'], 'age': data['age'],
            'email': data['email'], 'phone': data['phone'],
            'avatar_index': data['avatar_index'] ?? 0,
            'monthly_budget': (data['monthly_budget'] as num?)?.toDouble() ?? 50000,
            'created_at': data['created_at'],
          });
        }
        break;

      case SyncTable.splitGroups:
        // Fetch groups where user is member
        final memberData = await _client.from('group_members').select('group_id').eq('user_id', uid);
        final groupIds = (memberData as List).map((m) => m['group_id'] as String).toList();
        if (groupIds.isNotEmpty) {
          final data = await _client.from('split_groups').select().inFilter('id', groupIds);
          await _localDb.upsertGroups((data as List).map((m) => <String, dynamic>{
            'id': m['id'].toString(), 'name': m['name'], 'type': m['type'],
            'emoji': m['emoji'], 'created_by': m['created_by'], 'created_at': m['created_at'],
          }).toList());
        }
        break;

      case SyncTable.groupMembers:
        // Sync all members for user's groups
        final memberData = await _client.from('group_members').select('group_id').eq('user_id', uid);
        final groupIds = (memberData as List).map((m) => m['group_id'] as String).toSet().toList();
        for (final gid in groupIds) {
          final data = await _client.from('group_members').select().eq('group_id', gid);
          await _localDb.upsertMembers(gid, (data as List).map((m) => <String, dynamic>{
            'id': m['id'].toString(), 'group_id': m['group_id'], 'name': m['name'],
            'phone': m['phone'], 'user_id': m['user_id'],
          }).toList());
        }
        break;

      case SyncTable.splitExpenses:
        final memberData = await _client.from('group_members').select('group_id').eq('user_id', uid);
        final groupIds = (memberData as List).map((m) => m['group_id'] as String).toSet().toList();
        for (final gid in groupIds) {
          final data = await _client.from('split_expenses').select().eq('group_id', gid);
          await _localDb.upsertExpenses(gid, (data as List).map((m) => <String, dynamic>{
            'id': m['id'].toString(), 'group_id': m['group_id'], 'description': m['description'],
            'amount': (m['amount'] as num).toDouble(), 'paid_by': m['paid_by'],
            'split_type': m['split_type'], 'category': m['category'], 'created_at': m['created_at'],
          }).toList());
          // Also sync expense splits
          final expIds = (data as List).map((m) => m['id'].toString()).toList();
          if (expIds.isNotEmpty) {
            final splits = await _client.from('expense_splits').select().inFilter('expense_id', expIds);
            await _localDb.upsertExpenseSplits((splits as List).map((m) => <String, dynamic>{
              'id': m['id'].toString(), 'expense_id': m['expense_id'],
              'member_id': m['member_id'], 'amount': (m['amount'] as num).toDouble(),
            }).toList());
          }
        }
        break;

      case SyncTable.settlements:
        final memberData = await _client.from('group_members').select('group_id').eq('user_id', uid);
        final groupIds = (memberData as List).map((m) => m['group_id'] as String).toSet().toList();
        for (final gid in groupIds) {
          final data = await _client.from('settlements').select().eq('group_id', gid);
          await _localDb.upsertSettlements(gid, (data as List).map((m) => <String, dynamic>{
            'id': m['id'].toString(), 'group_id': m['group_id'],
            'from_member': m['from_member'], 'to_member': m['to_member'],
            'amount': (m['amount'] as num).toDouble(), 'method': m['method'], 'created_at': m['created_at'],
          }).toList());
        }
        break;

      case SyncTable.weeklyManualSpendLogs:
        final data = await _client
            .from('weekly_manual_spend_logs')
            .select()
            .eq('user_id', uid)
            .order('occurred_at', ascending: false);
        final rows = (data as List).map((m) {
          String iso(dynamic v) {
            if (v == null) return '';
            if (v is String) return v;
            return v.toString();
          }

          return <String, dynamic>{
            'id': m['id'].toString(),
            'user_id': m['user_id'].toString(),
            'weekly_target_id': m['weekly_target_id']?.toString(),
            'category': m['category'] as String,
            'amount': (m['amount'] as num).toDouble(),
            'occurred_at': iso(m['occurred_at']),
            'created_at': iso(m['created_at']),
          };
        }).toList();
        await _localDb.replaceWeeklyManualSpendLogs(uid, rows);
        break;
    }
  }

  /// Bump a remote version after a write (call from repository after Supabase insert/update/delete)
  Future<void> bumpVersion(String tableName) async {
    if (_userId == null) return;
    try {
      await _client.rpc('bump_sync_version', params: {
        'p_user_id': _userId!,
        'p_table_name': tableName,
      });
      // Also bump local so syncStale() doesn't redundantly re-fetch this table
      final currentLocal = await _localDb.getLocalVersion(tableName);
      await _localDb.setLocalVersion(tableName, currentLocal + 1);
    } catch (e) {
      debugPrint('VersionSync: bump failed for $tableName — $e');
    }
  }

  /// Check if a specific table needs sync (without syncing)
  Future<bool> isStale(String tableName) async {
    if (_userId == null) return false;
    try {
      final data = await _client
          .from('user_sync_versions')
          .select('version')
          .eq('user_id', _userId!)
          .eq('table_name', tableName)
          .maybeSingle();
      final remote = (data?['version'] as int?) ?? 0;
      final local = await _localDb.getLocalVersion(tableName);
      return remote > local;
    } catch (e) {
      return true; // assume stale on error
    }
  }
}
