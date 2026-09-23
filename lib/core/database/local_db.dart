import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

/// Local SQLite cache — mirrors Supabase for instant UI
class LocalDB {
  static final LocalDB instance = LocalDB._();
  static Database? _db;

  LocalDB._();

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDB();
    return _db!;
  }

  Future<Database> _initDB() async {
    // Web (ffi_web): use a plain filename; path_provider-style dirs are not used.
    final path = kIsWeb
        ? 'fluid_ledger_cache.db'
        : join(await getDatabasesPath(), 'fluid_ledger_cache.db');

    return openDatabase(
      path,
      version: 17,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
      onOpen: (db) => _migrateLegacyCategoryNames(db),
    );
  }

  Future<void> _createDB(Database db, int version) async {
    await _createTables(db);
    await _createIndexes(db);
  }

  Future<void> _createTables(Database db) async {
    // Transactions cache
    await db.execute('''
      CREATE TABLE IF NOT EXISTS transactions_cache (
        id TEXT PRIMARY KEY,
        amount REAL NOT NULL,
        category TEXT NOT NULL,
        date TEXT NOT NULL,
        notes TEXT,
        user_id TEXT,
        brand TEXT,
        created_at TEXT,
        updated_at TEXT,
        dirty INTEGER NOT NULL DEFAULT 0,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        last_synced_at TEXT,
        sync_action TEXT
      )
    ''');

    // Transaction summary cache (lightweight)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS transactions_summary (
        date TEXT NOT NULL,
        amount REAL NOT NULL,
        category TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS monthly_aggregate_cache (
        user_id TEXT NOT NULL,
        year INTEGER NOT NULL,
        month INTEGER NOT NULL,
        total_spend REAL NOT NULL DEFAULT 0,
        transaction_count INTEGER NOT NULL DEFAULT 0,
        category_count INTEGER NOT NULL DEFAULT 0,
        last_transaction_at TEXT,
        updated_at TEXT,
        last_synced_at TEXT,
        PRIMARY KEY (user_id, year, month)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS monthly_category_totals_cache (
        user_id TEXT NOT NULL,
        year INTEGER NOT NULL,
        month INTEGER NOT NULL,
        category TEXT NOT NULL,
        total_spend REAL NOT NULL DEFAULT 0,
        transaction_count INTEGER NOT NULL DEFAULT 0,
        updated_at TEXT,
        last_synced_at TEXT,
        PRIMARY KEY (user_id, year, month, category)
      )
    ''');

    // Profile cache
    await db.execute('''
      CREATE TABLE IF NOT EXISTS profile_cache (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        age INTEGER NOT NULL,
        email TEXT NOT NULL,
        phone TEXT NOT NULL,
        avatar_index INTEGER DEFAULT 0,
        monthly_budget REAL DEFAULT 50000,
        created_at TEXT
      )
    ''');

    // Sync metadata
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_meta (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    // Splitwise cache tables
    await db.execute('''
      CREATE TABLE IF NOT EXISTS split_groups_cache (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        type TEXT,
        emoji TEXT,
        created_by TEXT,
        created_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS group_members_cache (
        id TEXT PRIMARY KEY,
        group_id TEXT NOT NULL,
        name TEXT NOT NULL,
        phone TEXT,
        user_id TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS split_expenses_cache (
        id TEXT PRIMARY KEY,
        group_id TEXT NOT NULL,
        description TEXT NOT NULL,
        amount REAL NOT NULL,
        paid_by TEXT NOT NULL,
        split_type TEXT,
        category TEXT,
        created_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS expense_splits_cache (
        id TEXT PRIMARY KEY,
        expense_id TEXT NOT NULL,
        member_id TEXT NOT NULL,
        amount REAL NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS settlements_cache (
        id TEXT PRIMARY KEY,
        group_id TEXT NOT NULL,
        from_member TEXT NOT NULL,
        to_member TEXT NOT NULL,
        amount REAL NOT NULL,
        method TEXT,
        created_at TEXT
      )
    ''');

    // Pre-computed group balances cache
    await db.execute('''
      CREATE TABLE IF NOT EXISTS group_balances_cache (
        group_id TEXT PRIMARY KEY,
        you_owe REAL DEFAULT 0,
        owed_to_you REAL DEFAULT 0,
        net REAL DEFAULT 0,
        updated_at TEXT
      )
    ''');

    // Pre-computed debts cache
    await db.execute('''
      CREATE TABLE IF NOT EXISTS group_debts_cache (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        group_id TEXT NOT NULL,
        from_member TEXT NOT NULL,
        to_member TEXT NOT NULL,
        amount REAL NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS group_summary_cache (
        group_id TEXT PRIMARY KEY,
        member_count INTEGER DEFAULT 0,
        expense_count INTEGER DEFAULT 0,
        settlement_count INTEGER DEFAULT 0,
        total_expenses REAL DEFAULT 0,
        last_activity_at TEXT,
        you_owe REAL DEFAULT 0,
        owed_to_you REAL DEFAULT 0,
        net REAL DEFAULT 0,
        updated_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS pending_group_recompute (
        group_id TEXT PRIMARY KEY,
        reason TEXT,
        updated_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS merchant_category_overrides (
        merchant_key TEXT PRIMARY KEY,
        category TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        dirty INTEGER NOT NULL DEFAULT 1,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        last_synced_at TEXT
      )
    ''');

    // Local sync versions — tracks which tables need refresh
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_versions (
        table_name TEXT PRIMARY KEY,
        local_version INTEGER DEFAULT 0
      )
    ''');

    // Goals cache
    await db.execute('''
      CREATE TABLE IF NOT EXISTS goals_cache (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        name TEXT NOT NULL,
        emoji TEXT NOT NULL,
        target_amount REAL NOT NULL,
        saved_amount REAL NOT NULL DEFAULT 0,
        deadline TEXT,
        created_at TEXT
      )
    ''');

    // Weekly targets cache
    await db.execute('''
      CREATE TABLE IF NOT EXISTS weekly_targets_cache (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        category TEXT NOT NULL,
        limit_amount REAL NOT NULL,
        spent_manual_top_up REAL NOT NULL DEFAULT 0,
        created_at TEXT
      )
    ''');

    // Pinned items (UI preference) — keep separate so remote sync doesn't wipe it.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS pinned_items (
        user_id TEXT NOT NULL,
        item_type TEXT NOT NULL,
        item_id TEXT NOT NULL,
        pinned_at TEXT,
        PRIMARY KEY (user_id, item_type, item_id)
      )
    ''');

    // Weekly manual spend logs — mirrors Supabase `weekly_manual_spend_logs` (UUID PK)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS weekly_manual_spend_logs (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        weekly_target_id TEXT,
        category TEXT NOT NULL,
        amount REAL NOT NULL,
        occurred_at TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');

    // Indexes
    // Archived split groups (local UI — hide from home preview until restored)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS archived_split_groups (
        user_id TEXT NOT NULL,
        group_id TEXT NOT NULL,
        archived_at TEXT,
        PRIMARY KEY (user_id, group_id)
      )
    ''');
  }

  Future<void> _createIndexes(Database db) async {
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_gd_group ON group_debts_cache(group_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_gs_updated ON group_summary_cache(updated_at)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_pgr_updated ON pending_group_recompute(updated_at)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_tx_date ON transactions_cache(date)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_tx_user ON transactions_cache(user_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_tx_dirty ON transactions_cache(user_id, dirty)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_monthly_agg_user_month ON monthly_aggregate_cache(user_id, year, month)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_monthly_cat_user_month ON monthly_category_totals_cache(user_id, year, month)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_gm_group ON group_members_cache(group_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_se_group ON split_expenses_cache(group_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_es_expense ON expense_splits_cache(expense_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_st_group ON settlements_cache(group_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_wmsl_user_occurred ON weekly_manual_spend_logs(user_id, occurred_at)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_mco_dirty_updated ON merchant_category_overrides(dirty, updated_at)',
    );
  }

  /// One-time label fix: canonical category is now [Travel] (was [Transport]).
  Future<void> _migrateLegacyCategoryNames(Database db) async {
    await db.rawUpdate(
      "UPDATE transactions_cache SET category = 'Travel' WHERE lower(category) = 'transport'",
    );
    await db.rawUpdate(
      "UPDATE transactions_summary SET category = 'Travel' WHERE lower(category) = 'transport'",
    );
    await db.rawUpdate(
      "UPDATE split_expenses_cache SET category = 'Travel' WHERE lower(category) = 'transport'",
    );
  }

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    await _createTables(db);
    await _ensureColumn(db, 'transactions_cache', 'brand', 'TEXT');
    await _ensureColumn(db, 'transactions_cache', 'created_at', 'TEXT');
    await _ensureColumn(db, 'transactions_cache', 'updated_at', 'TEXT');
    await _ensureColumn(
      db,
      'transactions_cache',
      'dirty',
      'INTEGER NOT NULL DEFAULT 0',
    );
    await _ensureColumn(
      db,
      'transactions_cache',
      'is_deleted',
      'INTEGER NOT NULL DEFAULT 0',
    );
    await _ensureColumn(db, 'transactions_cache', 'last_synced_at', 'TEXT');
    await _ensureColumn(db, 'transactions_cache', 'sync_action', 'TEXT');
    await _ensureColumn(
      db,
      'profile_cache',
      'avatar_index',
      'INTEGER DEFAULT 0',
    );
    await _ensureColumn(
      db,
      'profile_cache',
      'monthly_budget',
      'REAL DEFAULT 50000',
    );
    await _ensureColumn(
      db,
      'weekly_targets_cache',
      'spent_manual_top_up',
      'REAL NOT NULL DEFAULT 0',
    );
    await _ensureColumn(db, 'group_balances_cache', 'updated_at', 'TEXT');
    await _ensureColumn(
      db,
      'group_summary_cache',
      'member_count',
      'INTEGER DEFAULT 0',
    );
    await _ensureColumn(
      db,
      'group_summary_cache',
      'expense_count',
      'INTEGER DEFAULT 0',
    );
    await _ensureColumn(
      db,
      'group_summary_cache',
      'settlement_count',
      'INTEGER DEFAULT 0',
    );
    await _ensureColumn(
      db,
      'group_summary_cache',
      'total_expenses',
      'REAL DEFAULT 0',
    );
    await _ensureColumn(db, 'group_summary_cache', 'last_activity_at', 'TEXT');
    await _ensureColumn(db, 'group_summary_cache', 'you_owe', 'REAL DEFAULT 0');
    await _ensureColumn(
      db,
      'group_summary_cache',
      'owed_to_you',
      'REAL DEFAULT 0',
    );
    await _ensureColumn(db, 'group_summary_cache', 'net', 'REAL DEFAULT 0');
    await _ensureColumn(db, 'group_summary_cache', 'updated_at', 'TEXT');
    await _createIndexes(db);
  }

  Future<void> _ensureColumn(
    Database db,
    String tableName,
    String columnName,
    String definition,
  ) async {
    final columns = await db.rawQuery('PRAGMA table_info($tableName)');
    final exists = columns.any((row) => row['name'] == columnName);
    if (!exists) {
      await db.execute(
        'ALTER TABLE $tableName ADD COLUMN $columnName $definition',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Transactions
  // ---------------------------------------------------------------------------

  Future<void> upsertTransactions(
    List<Map<String, dynamic>> transactions,
  ) async {
    final db = await database;
    final batch = db.batch();
    for (final tx in transactions) {
      batch.insert(
        'transactions_cache',
        _normalizeTransactionRow(tx),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> upsertTransaction(Map<String, dynamic> transaction) async {
    final db = await database;
    await db.insert(
      'transactions_cache',
      _normalizeTransactionRow(transaction),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getTransactions({
    int page = 0,
    int pageSize = 30,
    String? userId,
  }) async {
    final db = await database;
    final whereClauses = <String>['is_deleted = 0'];
    final whereArgs = <Object?>[];
    if (userId != null && userId.isNotEmpty) {
      whereClauses.add('user_id = ?');
      whereArgs.add(userId);
    }
    return db.query(
      'transactions_cache',
      where: whereClauses.join(' AND '),
      whereArgs: whereArgs,
      orderBy: 'date DESC',
      limit: pageSize,
      offset: page * pageSize,
    );
  }

  Future<List<Map<String, dynamic>>> getTransactionsForMonth(
    int year,
    int month,
    String? userId,
  ) async {
    final rows = await getAllTransactions(userId: userId);
    final inMonth = rows.where((row) {
      final date = DateTime.tryParse((row['date'] ?? '').toString());
      return date != null && date.year == year && date.month == month;
    }).toList();
    inMonth.sort((a, b) {
      final ad = DateTime.tryParse((a['date'] ?? '').toString());
      final bd = DateTime.tryParse((b['date'] ?? '').toString());
      if (ad == null && bd == null) return 0;
      if (ad == null) return 1;
      if (bd == null) return -1;
      return bd.compareTo(ad);
    });
    return inMonth;
  }

  /// Recent `amount`/`date` rows for duplicate checks (avoids fragile ISO string range on SQLite).
  Future<List<Map<String, dynamic>>> getSpendDigestsForUser(
    String userId, {
    int limit = 32000,
  }) async {
    if (userId.isEmpty) return [];
    final db = await database;
    return db.query(
      'transactions_cache',
      columns: ['amount', 'date'],
      where: 'user_id = ? AND is_deleted = 0',
      whereArgs: [userId],
      orderBy: 'date DESC',
      limit: limit,
    );
  }

  /// Ledger rows with similar amount (then compare times in Dart — same as cloud dedupe).
  Future<List<Map<String, dynamic>>> getSpendDigestsNearAmount({
    required String userId,
    required double amount,
    double epsilon = 0.02,
  }) async {
    if (userId.isEmpty) return [];
    final db = await database;
    return db.rawQuery(
      '''
      SELECT amount, date FROM transactions_cache
      WHERE user_id = ? AND is_deleted = 0 AND ABS(amount - ?) < ?
      ''',
      [userId, amount, epsilon],
    );
  }

  Future<List<Map<String, dynamic>>> getAllTransactions({
    String? userId,
  }) async {
    final db = await database;
    final whereClauses = <String>['is_deleted = 0'];
    final whereArgs = <Object?>[];
    if (userId != null && userId.isNotEmpty) {
      whereClauses.add('user_id = ?');
      whereArgs.add(userId);
    }
    return db.query(
      'transactions_cache',
      where: whereClauses.join(' AND '),
      whereArgs: whereArgs,
      orderBy: 'date DESC',
    );
  }

  Future<List<Map<String, dynamic>>> searchTransactions({
    required String userId,
    required String query,
    int? year,
    int? month,
    int limit = 500,
  }) async {
    final db = await database;
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return [];
    final rows = await db.rawQuery(
      '''
      SELECT *
      FROM transactions_cache
      WHERE is_deleted = 0
        AND user_id = ?
        AND (
          lower(COALESCE(notes, '')) LIKE ?
          OR lower(COALESCE(category, '')) LIKE ?
          OR lower(COALESCE(brand, '')) LIKE ?
          OR CAST(amount AS TEXT) LIKE ?
        )
      ORDER BY date DESC
      LIMIT ?
      ''',
      [userId, '%$q%', '%$q%', '%$q%', '%$q%', limit],
    );
    if (year == null || month == null) return rows;
    return rows.where((row) {
      final d = DateTime.tryParse((row['date'] ?? '').toString());
      return d != null && d.year == year && d.month == month;
    }).toList();
  }

  Future<void> clearTransactions() async {
    final db = await database;
    await db.delete('transactions_cache');
  }

  Map<String, dynamic> _normalizeTransactionRow(Map<String, dynamic> row) {
    if (!row.containsKey('date')) return row;
    final raw = row['date']?.toString();
    if (raw == null || raw.trim().isEmpty) return row;
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return row;
    final normalized = Map<String, dynamic>.from(row);
    normalized['date'] = parsed.toUtc().toIso8601String();
    return normalized;
  }

  /// Remove one row after a successful cloud delete (otherwise local-first reads bring it back).
  Future<void> deleteCachedTransaction(String id) async {
    final db = await database;
    await db.delete('transactions_cache', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> markTransactionDeletedLocally({
    required String id,
    required String userId,
    required String date,
  }) async {
    final db = await database;
    await db.insert('transactions_cache', {
      'id': id,
      'amount': 0,
      'category': 'Deleted',
      'date': date,
      'user_id': userId,
      'dirty': 1,
      'is_deleted': 1,
      'sync_action': 'delete',
      'updated_at': DateTime.now().toIso8601String(),
      'last_synced_at': null,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// How many cached rows exist for this user (sync / empty-cache decisions).
  Future<int> countTransactionsForUser(String userId) async {
    if (userId.isEmpty) return 0;
    final db = await database;
    final r = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM transactions_cache WHERE user_id = ? AND is_deleted = 0',
      [userId],
    );
    return Sqflite.firstIntValue(r) ?? 0;
  }

  /// Latest `created_at` in cache — used as a delta cursor (must not use wall-clock sync time).
  Future<String?> maxTransactionCreatedAtForUser(String userId) async {
    if (userId.isEmpty) return null;
    final db = await database;
    final r = await db.rawQuery(
      '''
      SELECT MAX(created_at) AS m FROM transactions_cache
      WHERE user_id = ? AND is_deleted = 0
        AND created_at IS NOT NULL AND TRIM(created_at) != ''
      ''',
      [userId],
    );
    if (r.isEmpty) return null;
    final m = r.first['m'];
    if (m == null) return null;
    final s = m.toString().trim();
    return s.isEmpty ? null : s;
  }

  // ---------------------------------------------------------------------------
  // Summary
  // ---------------------------------------------------------------------------

  Future<void> replaceSummary(List<Map<String, dynamic>> summary) async {
    final db = await database;
    await db.delete('transactions_summary');
    final batch = db.batch();
    for (final s in summary) {
      batch.insert('transactions_summary', {
        'date': s['date'],
        'amount': s['amount'],
        'category': s['category'],
      });
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> getSummary() async {
    final db = await database;
    return db.query('transactions_summary');
  }

  Future<void> rebuildSummaryFromTransactions(String userId) async {
    if (userId.isEmpty) return;
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('transactions_summary');
      await txn.execute(
        '''
        INSERT INTO transactions_summary(date, amount, category)
        SELECT date, amount, category
        FROM transactions_cache
        WHERE user_id = ? AND is_deleted = 0
        ORDER BY date DESC
        ''',
        [userId],
      );
    });
  }

  Future<void> replaceMonthlyAggregate({
    required String userId,
    required int year,
    required int month,
    required double totalSpend,
    required int transactionCount,
    required int categoryCount,
    required String? lastTransactionAt,
    required String updatedAt,
    String? lastSyncedAt,
  }) async {
    final db = await database;
    await db.insert('monthly_aggregate_cache', {
      'user_id': userId,
      'year': year,
      'month': month,
      'total_spend': totalSpend,
      'transaction_count': transactionCount,
      'category_count': categoryCount,
      'last_transaction_at': lastTransactionAt,
      'updated_at': updatedAt,
      'last_synced_at': lastSyncedAt,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> replaceMonthlyCategoryTotals({
    required String userId,
    required int year,
    required int month,
    required List<Map<String, dynamic>> rows,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete(
        'monthly_category_totals_cache',
        where: 'user_id = ? AND year = ? AND month = ?',
        whereArgs: [userId, year, month],
      );
      final batch = txn.batch();
      for (final row in rows) {
        batch.insert(
          'monthly_category_totals_cache',
          row,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  Future<Map<String, dynamic>?> getMonthlyAggregate({
    required String userId,
    required int year,
    required int month,
  }) async {
    final db = await database;
    final rows = await db.query(
      'monthly_aggregate_cache',
      where: 'user_id = ? AND year = ? AND month = ?',
      whereArgs: [userId, year, month],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<List<Map<String, dynamic>>> getMonthlyCategoryTotals({
    required String userId,
    required int year,
    required int month,
  }) async {
    final db = await database;
    return db.query(
      'monthly_category_totals_cache',
      where: 'user_id = ? AND year = ? AND month = ?',
      whereArgs: [userId, year, month],
      orderBy: 'total_spend DESC',
    );
  }

  Future<List<Map<String, dynamic>>> getDirtyTransactions(String userId) async {
    if (userId.isEmpty) return [];
    final db = await database;
    return db.query(
      'transactions_cache',
      where: 'user_id = ? AND dirty = 1',
      whereArgs: [userId],
      orderBy: 'date ASC',
    );
  }

  Future<void> markTransactionSynced({
    required String id,
    required String syncedAt,
  }) async {
    final db = await database;
    await db.update(
      'transactions_cache',
      {'dirty': 0, 'sync_action': null, 'last_synced_at': syncedAt},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ---------------------------------------------------------------------------
  // Merchant category overrides
  // ---------------------------------------------------------------------------

  Future<void> upsertMerchantOverride({
    required String merchantKey,
    required String category,
    String? updatedAt,
    bool dirty = true,
    String? lastSyncedAt,
  }) async {
    final db = await database;
    await db.insert('merchant_category_overrides', {
      'merchant_key': merchantKey,
      'category': category,
      'updated_at': updatedAt ?? DateTime.now().toIso8601String(),
      'dirty': dirty ? 1 : 0,
      'is_deleted': 0,
      'last_synced_at': lastSyncedAt,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> markMerchantOverrideDeleted({
    required String merchantKey,
    String? updatedAt,
  }) async {
    final db = await database;
    await db.insert('merchant_category_overrides', {
      'merchant_key': merchantKey,
      'category': 'Other',
      'updated_at': updatedAt ?? DateTime.now().toIso8601String(),
      'dirty': 1,
      'is_deleted': 1,
      'last_synced_at': null,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> getMerchantOverrides({
    bool includeDeleted = false,
  }) async {
    final db = await database;
    return db.query(
      'merchant_category_overrides',
      where: includeDeleted ? null : 'is_deleted = 0',
      orderBy: 'updated_at DESC',
    );
  }

  Future<List<Map<String, dynamic>>> getDirtyMerchantOverrides() async {
    final db = await database;
    return db.query(
      'merchant_category_overrides',
      where: 'dirty = 1',
      orderBy: 'updated_at ASC',
    );
  }

  Future<void> markMerchantOverrideSynced({
    required String merchantKey,
    required String syncedAt,
  }) async {
    final db = await database;
    await db.update(
      'merchant_category_overrides',
      {'dirty': 0, 'last_synced_at': syncedAt},
      where: 'merchant_key = ?',
      whereArgs: [merchantKey],
    );
  }

  // ---------------------------------------------------------------------------
  // Profile
  // ---------------------------------------------------------------------------

  Future<void> upsertProfile(Map<String, dynamic> profile) async {
    final db = await database;
    await db.insert(
      'profile_cache',
      profile,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, dynamic>?> getProfile() async {
    final db = await database;
    final results = await db.query('profile_cache', limit: 1);
    return results.isEmpty ? null : results.first;
  }

  // ---------------------------------------------------------------------------
  // Sync metadata
  // ---------------------------------------------------------------------------

  Future<void> setSyncMeta(String key, String value) async {
    final db = await database;
    await db.insert('sync_meta', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<String?> getSyncMeta(String key) async {
    final db = await database;
    final results = await db.query(
      'sync_meta',
      where: 'key = ?',
      whereArgs: [key],
    );
    return results.isEmpty ? null : results.first['value'] as String?;
  }

  Future<void> clearAll() async {
    final db = await database;
    for (final table in [
      'transactions_cache',
      'transactions_summary',
      'monthly_aggregate_cache',
      'monthly_category_totals_cache',
      'profile_cache',
      'sync_meta',
      'split_groups_cache',
      'group_members_cache',
      'split_expenses_cache',
      'expense_splits_cache',
      'settlements_cache',
      'group_balances_cache',
      'group_debts_cache',
      'merchant_category_overrides',
      'sync_versions',
      'goals_cache',
      'weekly_targets_cache',
    ]) {
      await db.delete(table);
    }
  }

  // ---------------------------------------------------------------------------
  // Sync Versions — per-table version tracking
  // ---------------------------------------------------------------------------

  Future<int> getLocalVersion(String tableName) async {
    final db = await database;
    final rows = await db.query(
      'sync_versions',
      where: 'table_name = ?',
      whereArgs: [tableName],
    );
    if (rows.isEmpty) return 0;
    return (rows.first['local_version'] as int?) ?? 0;
  }

  Future<void> setLocalVersion(String tableName, int version) async {
    final db = await database;
    await db.insert('sync_versions', {
      'table_name': tableName,
      'local_version': version,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, int>> getAllLocalVersions() async {
    final db = await database;
    final rows = await db.query('sync_versions');
    final map = <String, int>{};
    for (final r in rows) {
      map[r['table_name'] as String] = (r['local_version'] as int?) ?? 0;
    }
    return map;
  }

  // ---------------------------------------------------------------------------
  // Pre-computed Group Balances
  // ---------------------------------------------------------------------------

  // Pre-computed debts per group (who owes whom)
  Future<void> saveGroupDebts(
    String groupId,
    List<Map<String, dynamic>> debts,
  ) async {
    final db = await database;
    await db.delete(
      'group_debts_cache',
      where: 'group_id = ?',
      whereArgs: [groupId],
    );
    final batch = db.batch();
    for (final d in debts) {
      batch.insert('group_debts_cache', {'group_id': groupId, ...d});
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> getGroupDebts(String groupId) async {
    final db = await database;
    return db.query(
      'group_debts_cache',
      where: 'group_id = ?',
      whereArgs: [groupId],
    );
  }

  Future<void> saveGroupBalance(
    String groupId,
    double youOwe,
    double owedToYou,
  ) async {
    final db = await database;
    await db.insert('group_balances_cache', {
      'group_id': groupId,
      'you_owe': youOwe,
      'owed_to_you': owedToYou,
      'net': owedToYou - youOwe,
      'updated_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, Map<String, double>>> getAllGroupBalances() async {
    final db = await database;
    final rows = await db.query('group_balances_cache');
    final result = <String, Map<String, double>>{};
    for (final r in rows) {
      result[r['group_id'] as String] = {
        'you_owe': (r['you_owe'] as num?)?.toDouble() ?? 0,
        'owed_to_you': (r['owed_to_you'] as num?)?.toDouble() ?? 0,
        'net': (r['net'] as num?)?.toDouble() ?? 0,
      };
    }
    return result;
  }

  Future<void> saveGroupSummary(
    String groupId, {
    required int memberCount,
    required int expenseCount,
    required int settlementCount,
    required double totalExpenses,
    String? lastActivityAt,
    required double youOwe,
    required double owedToYou,
  }) async {
    final db = await database;
    await db.insert('group_summary_cache', {
      'group_id': groupId,
      'member_count': memberCount,
      'expense_count': expenseCount,
      'settlement_count': settlementCount,
      'total_expenses': totalExpenses,
      'last_activity_at': lastActivityAt,
      'you_owe': youOwe,
      'owed_to_you': owedToYou,
      'net': owedToYou - youOwe,
      'updated_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, dynamic>?> getGroupSummary(String groupId) async {
    final db = await database;
    final rows = await db.query(
      'group_summary_cache',
      where: 'group_id = ?',
      whereArgs: [groupId],
      limit: 1,
    );
    return rows.isEmpty ? null : Map<String, dynamic>.from(rows.first);
  }

  Future<Map<String, Map<String, dynamic>>> getAllGroupSummaries() async {
    final db = await database;
    final rows = await db.query('group_summary_cache');
    final result = <String, Map<String, dynamic>>{};
    for (final row in rows) {
      final groupId = (row['group_id'] ?? '').toString();
      if (groupId.isEmpty) continue;
      result[groupId] = Map<String, dynamic>.from(row);
    }
    return result;
  }

  Future<void> markGroupRecomputeDirty(String groupId, {String? reason}) async {
    final db = await database;
    await db.insert('pending_group_recompute', {
      'group_id': groupId,
      'reason': reason,
      'updated_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> clearGroupRecomputeDirty(String groupId) async {
    final db = await database;
    await db.delete(
      'pending_group_recompute',
      where: 'group_id = ?',
      whereArgs: [groupId],
    );
  }

  Future<List<Map<String, dynamic>>> getDirtyGroupRecomputes() async {
    final db = await database;
    final rows = await db.query(
      'pending_group_recompute',
      orderBy: 'updated_at ASC',
    );
    return rows.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  // ---------------------------------------------------------------------------
  // Split Groups
  // ---------------------------------------------------------------------------

  Future<void> upsertGroups(List<Map<String, dynamic>> groups) async {
    final db = await database;
    final batch = db.batch();
    for (final g in groups) {
      batch.insert(
        'split_groups_cache',
        g,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> getGroups() async {
    final db = await database;
    return db.query('split_groups_cache', orderBy: 'created_at DESC');
  }

  Future<void> deleteGroupCache(String groupId) async {
    final db = await database;
    final expenseRows = await db.query(
      'split_expenses_cache',
      columns: ['id'],
      where: 'group_id = ?',
      whereArgs: [groupId],
    );
    final expenseIds = expenseRows
        .map((row) => (row['id'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toList();
    await db.delete(
      'split_groups_cache',
      where: 'id = ?',
      whereArgs: [groupId],
    );
    await db.delete(
      'group_members_cache',
      where: 'group_id = ?',
      whereArgs: [groupId],
    );
    await db.delete(
      'split_expenses_cache',
      where: 'group_id = ?',
      whereArgs: [groupId],
    );
    if (expenseIds.isNotEmpty) {
      final placeholders = expenseIds.map((_) => '?').join(',');
      await db.rawDelete(
        'DELETE FROM expense_splits_cache WHERE expense_id IN ($placeholders)',
        expenseIds,
      );
    }
    await db.delete(
      'settlements_cache',
      where: 'group_id = ?',
      whereArgs: [groupId],
    );
    await db.delete(
      'group_debts_cache',
      where: 'group_id = ?',
      whereArgs: [groupId],
    );
    await db.delete(
      'group_balances_cache',
      where: 'group_id = ?',
      whereArgs: [groupId],
    );
    await db.delete(
      'group_summary_cache',
      where: 'group_id = ?',
      whereArgs: [groupId],
    );
    await db.delete(
      'pending_group_recompute',
      where: 'group_id = ?',
      whereArgs: [groupId],
    );
    await db.delete(
      'archived_split_groups',
      where: 'group_id = ?',
      whereArgs: [groupId],
    );
    await db.delete(
      'pinned_items',
      where: 'item_type = ? AND item_id = ?',
      whereArgs: ['split_group', groupId],
    );
  }

  // ---------------------------------------------------------------------------
  // Split groups — archived (local)
  // ---------------------------------------------------------------------------

  Future<Set<String>> getArchivedSplitGroupIds(String userId) async {
    final db = await database;
    final rows = await db.query(
      'archived_split_groups',
      columns: ['group_id'],
      where: 'user_id = ?',
      whereArgs: [userId],
    );
    return rows
        .map((r) => (r['group_id'] ?? '').toString())
        .where((s) => s.isNotEmpty)
        .toSet();
  }

  Future<void> setSplitGroupArchived(
    String userId,
    String groupId,
    bool archived,
  ) async {
    final db = await database;
    if (archived) {
      await db.insert('archived_split_groups', {
        'user_id': userId,
        'group_id': groupId,
        'archived_at': DateTime.now().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    } else {
      await db.delete(
        'archived_split_groups',
        where: 'user_id = ? AND group_id = ?',
        whereArgs: [userId, groupId],
      );
    }
  }

  /// Cached expense rows for this group (0 if none synced yet).
  Future<int> countCachedExpensesForGroup(String groupId) async {
    final db = await database;
    final r = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM split_expenses_cache WHERE group_id = ?',
      [groupId],
    );
    return Sqflite.firstIntValue(r) ?? 0;
  }

  // ---------------------------------------------------------------------------
  // Group Members
  // ---------------------------------------------------------------------------

  Future<void> upsertMembers(
    String groupId,
    List<Map<String, dynamic>> members,
  ) async {
    final db = await database;
    await db.delete(
      'group_members_cache',
      where: 'group_id = ?',
      whereArgs: [groupId],
    );
    final batch = db.batch();
    for (final m in members) {
      batch.insert(
        'group_members_cache',
        m,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> getMembers(String groupId) async {
    final db = await database;
    return db.query(
      'group_members_cache',
      where: 'group_id = ?',
      whereArgs: [groupId],
    );
  }

  // ---------------------------------------------------------------------------
  // Split Expenses
  // ---------------------------------------------------------------------------

  Future<void> upsertExpenses(
    String groupId,
    List<Map<String, dynamic>> expenses,
  ) async {
    final db = await database;
    await db.delete(
      'split_expenses_cache',
      where: 'group_id = ?',
      whereArgs: [groupId],
    );
    final batch = db.batch();
    for (final e in expenses) {
      batch.insert(
        'split_expenses_cache',
        e,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> getExpenses(String groupId) async {
    final db = await database;
    return db.query(
      'split_expenses_cache',
      where: 'group_id = ?',
      whereArgs: [groupId],
      orderBy: 'created_at DESC',
    );
  }

  Future<void> upsertExpense(Map<String, dynamic> expense) async {
    final db = await database;
    await db.insert(
      'split_expenses_cache',
      expense,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteExpenseCache(String expenseId) async {
    final db = await database;
    await db.delete(
      'split_expenses_cache',
      where: 'id = ?',
      whereArgs: [expenseId],
    );
  }

  // ---------------------------------------------------------------------------
  // Expense Splits
  // ---------------------------------------------------------------------------

  Future<void> upsertExpenseSplits(List<Map<String, dynamic>> splits) async {
    final db = await database;
    final batch = db.batch();
    for (final s in splits) {
      batch.insert(
        'expense_splits_cache',
        s,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> getExpenseSplits(
    List<String> expenseIds,
  ) async {
    if (expenseIds.isEmpty) return [];
    final db = await database;
    final placeholders = expenseIds.map((_) => '?').join(',');
    return db.rawQuery(
      'SELECT * FROM expense_splits_cache WHERE expense_id IN ($placeholders)',
      expenseIds,
    );
  }

  Future<void> replaceExpenseSplitsForExpense(
    String expenseId,
    List<Map<String, dynamic>> splits,
  ) async {
    final db = await database;
    await db.delete(
      'expense_splits_cache',
      where: 'expense_id = ?',
      whereArgs: [expenseId],
    );
    final batch = db.batch();
    for (final split in splits) {
      batch.insert(
        'expense_splits_cache',
        split,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> deleteExpenseSplitsForExpense(String expenseId) async {
    final db = await database;
    await db.delete(
      'expense_splits_cache',
      where: 'expense_id = ?',
      whereArgs: [expenseId],
    );
  }

  // ---------------------------------------------------------------------------
  // Settlements
  // ---------------------------------------------------------------------------

  Future<void> upsertSettlements(
    String groupId,
    List<Map<String, dynamic>> settlements,
  ) async {
    final db = await database;
    await db.delete(
      'settlements_cache',
      where: 'group_id = ?',
      whereArgs: [groupId],
    );
    final batch = db.batch();
    for (final s in settlements) {
      batch.insert(
        'settlements_cache',
        s,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> getSettlements(String groupId) async {
    final db = await database;
    return db.query(
      'settlements_cache',
      where: 'group_id = ?',
      whereArgs: [groupId],
      orderBy: 'created_at DESC',
    );
  }

  Future<void> upsertSettlement(Map<String, dynamic> settlement) async {
    final db = await database;
    await db.insert(
      'settlements_cache',
      settlement,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteSettlementCache(String settlementId) async {
    final db = await database;
    await db.delete(
      'settlements_cache',
      where: 'id = ?',
      whereArgs: [settlementId],
    );
  }

  // ---------------------------------------------------------------------------
  // Goals
  // ---------------------------------------------------------------------------

  Future<void> upsertGoals(
    String userId,
    List<Map<String, dynamic>> goals,
  ) async {
    final db = await database;
    await db.delete('goals_cache', where: 'user_id = ?', whereArgs: [userId]);
    final batch = db.batch();
    for (final g in goals) {
      batch.insert(
        'goals_cache',
        g,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> upsertGoal(Map<String, dynamic> goal) async {
    final db = await database;
    await db.insert(
      'goals_cache',
      goal,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getGoals(String userId) async {
    final db = await database;
    return db.query(
      'goals_cache',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'created_at ASC',
    );
  }

  Future<void> deleteGoalCache(String id) async {
    final db = await database;
    await db.delete('goals_cache', where: 'id = ?', whereArgs: [id]);
    await db.delete(
      'pinned_items',
      where: 'item_type = ? AND item_id = ?',
      whereArgs: ['goal', id],
    );
  }

  // ---------------------------------------------------------------------------
  // Weekly Targets
  // ---------------------------------------------------------------------------

  Future<void> upsertWeeklyTargets(
    String userId,
    List<Map<String, dynamic>> targets,
  ) async {
    final db = await database;
    await db.delete(
      'weekly_targets_cache',
      where: 'user_id = ?',
      whereArgs: [userId],
    );
    final batch = db.batch();
    for (final t in targets) {
      batch.insert(
        'weekly_targets_cache',
        t,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> upsertWeeklyTarget(Map<String, dynamic> target) async {
    final db = await database;
    await db.insert(
      'weekly_targets_cache',
      target,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Updates [limit_amount] and [spent_manual_top_up] for one cached row (by id preferred, else user + category).
  Future<void> patchWeeklyTargetSnapshot({
    required String userId,
    String? id,
    required String category,
    required double limitAmount,
    required double manualSpentTopUp,
  }) async {
    final db = await database;
    final row = <String, Object?>{
      'limit_amount': limitAmount,
      'spent_manual_top_up': manualSpentTopUp,
    };
    final updated = id != null && id.isNotEmpty
        ? await db.update(
            'weekly_targets_cache',
            row,
            where: 'user_id = ? AND id = ?',
            whereArgs: [userId, id],
          )
        : await db.update(
            'weekly_targets_cache',
            row,
            where: 'user_id = ? AND category = ?',
            whereArgs: [userId, category],
          );
    if (updated == 0) {
      throw StateError('No matching weekly target in local cache.');
    }
  }

  Future<List<Map<String, dynamic>>> getWeeklyTargets(String userId) async {
    final db = await database;
    return db.query(
      'weekly_targets_cache',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'created_at ASC',
    );
  }

  Future<void> deleteWeeklyTargetCache(String id) async {
    final db = await database;
    await db.delete('weekly_targets_cache', where: 'id = ?', whereArgs: [id]);
    await db.delete(
      'pinned_items',
      where: 'item_type = ? AND item_id = ?',
      whereArgs: ['weekly_target', id],
    );
  }

  // ---------------------------------------------------------------------------
  // Pinned items (UI preference)
  // ---------------------------------------------------------------------------

  Future<Set<String>> getPinnedItemIds({
    required String userId,
    required String itemType,
  }) async {
    final db = await database;
    final rows = await db.query(
      'pinned_items',
      columns: ['item_id'],
      where: 'user_id = ? AND item_type = ?',
      whereArgs: [userId, itemType],
      orderBy: 'pinned_at ASC',
    );
    return rows
        .map((r) => (r['item_id'] ?? '').toString())
        .where((s) => s.isNotEmpty)
        .toSet();
  }

  Future<void> setPinnedItem({
    required String userId,
    required String itemType,
    required String itemId,
    required bool pinned,
    int maxPinned = 2,
  }) async {
    final db = await database;
    if (pinned) {
      final count =
          Sqflite.firstIntValue(
            await db.rawQuery(
              'SELECT COUNT(*) FROM pinned_items WHERE user_id = ? AND item_type = ?',
              [userId, itemType],
            ),
          ) ??
          0;
      if (count >= maxPinned) {
        throw StateError('You can pin at most $maxPinned items.');
      }
      await db.insert('pinned_items', {
        'user_id': userId,
        'item_type': itemType,
        'item_id': itemId,
        'pinned_at': DateTime.now().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    } else {
      await db.delete(
        'pinned_items',
        where: 'user_id = ? AND item_type = ? AND item_id = ?',
        whereArgs: [userId, itemType, itemId],
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Weekly manual spend logs (history)
  // ---------------------------------------------------------------------------

  /// Upsert one log row (same [id] as Supabase).
  Future<void> upsertWeeklyManualSpendLog(Map<String, dynamic> row) async {
    final db = await database;
    await db.insert(
      'weekly_manual_spend_logs',
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Replace all cached logs for [userId] with the remote snapshot (version sync).
  Future<void> replaceWeeklyManualSpendLogs(
    String userId,
    List<Map<String, dynamic>> rows,
  ) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete(
        'weekly_manual_spend_logs',
        where: 'user_id = ?',
        whereArgs: [userId],
      );
      final batch = txn.batch();
      for (final r in rows) {
        batch.insert(
          'weekly_manual_spend_logs',
          r,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  /// Sums manual "Log spend" rows for \[startYmd, endYmdInclusive] (local calendar days),
  /// using `substr(occurred_at,1,10)` so mixed ISO formats compare reliably.
  Future<Map<String, double>> sumWeeklyManualSpendByCategoryForDateYmdRange({
    required String userId,
    required String startYmd,
    required String endYmdInclusive,
  }) async {
    if (userId.isEmpty) return {};
    final db = await database;
    final rows = await db.rawQuery(
      '''
      SELECT category, SUM(amount) AS total
      FROM weekly_manual_spend_logs
      WHERE user_id = ?
        AND LENGTH(occurred_at) >= 10
        AND substr(occurred_at, 1, 10) >= ?
        AND substr(occurred_at, 1, 10) <= ?
      GROUP BY category
      ''',
      [userId, startYmd, endYmdInclusive],
    );
    final out = <String, double>{};
    for (final r in rows) {
      final cat = r['category']?.toString();
      if (cat == null || cat.isEmpty) continue;
      final v = r['total'];
      final amt = (v is num)
          ? v.toDouble()
          : double.tryParse(v.toString()) ?? 0.0;
      out[cat] = amt;
    }
    return out;
  }

  /// Sum transaction amounts per category for \[startYmd, endYmdInclusive] (local calendar days).
  ///
  /// Uses `substr(date, 1, 10)` so ledger rows still match when `date` mixes `Z`, offsets, or lengths.
  Future<Map<String, double>> sumTransactionsByCategoryForUserDateRange({
    required String userId,
    required String startYmd,
    required String endYmdInclusive,
  }) async {
    if (userId.isEmpty) return {};
    final db = await database;
    final rows = await db.rawQuery(
      '''
      SELECT category, SUM(amount) AS total
      FROM transactions_cache
      WHERE user_id = ?
        AND LENGTH(date) >= 10
        AND substr(date, 1, 10) >= ?
        AND substr(date, 1, 10) <= ?
      GROUP BY category
      ''',
      [userId, startYmd, endYmdInclusive],
    );
    final out = <String, double>{};
    for (final r in rows) {
      final cat = r['category']?.toString();
      if (cat == null || cat.isEmpty) continue;
      final v = r['total'];
      final amt = (v is num)
          ? v.toDouble()
          : double.tryParse(v.toString()) ?? 0.0;
      out[cat] = amt;
    }
    return out;
  }
}
