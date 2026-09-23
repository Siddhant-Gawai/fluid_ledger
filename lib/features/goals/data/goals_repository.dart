import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../../core/constants/categories.dart';
import '../../../core/database/local_db.dart';
import '../../../core/database/version_sync.dart';
import '../../../core/supabase/supabase_config.dart';

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------

class Goal {
  final String? id;
  final String userId;
  final String name;
  final String emoji;
  final double targetAmount;
  final double savedAmount;
  final String? deadline; // ISO date string, nullable
  final String? createdAt;
  final bool pinned;

  Goal({
    this.id,
    required this.userId,
    required this.name,
    required this.emoji,
    required this.targetAmount,
    this.savedAmount = 0,
    this.deadline,
    this.createdAt,
    this.pinned = false,
  });

  double get progress => targetAmount > 0 ? (savedAmount / targetAmount).clamp(0.0, 1.0) : 0;
  bool get isCompleted => savedAmount >= targetAmount;

  Map<String, dynamic> toInsertMap() => {
    'user_id': userId,
    'name': name,
    'emoji': emoji,
    'target_amount': targetAmount,
    'saved_amount': savedAmount,
    'deadline': deadline,
  };

  Map<String, dynamic> toCacheMap() => {
    if (id != null) 'id': id,
    'user_id': userId,
    'name': name,
    'emoji': emoji,
    'target_amount': targetAmount,
    'saved_amount': savedAmount,
    'deadline': deadline,
    'created_at': createdAt,
  };

  factory Goal.fromMap(Map<String, dynamic> m) => Goal(
    id: m['id']?.toString(),
    userId: m['user_id'] as String,
    name: m['name'] as String,
    emoji: m['emoji'] as String? ?? '🎯',
    targetAmount: (m['target_amount'] as num).toDouble(),
    savedAmount: (m['saved_amount'] as num?)?.toDouble() ?? 0,
    deadline: m['deadline'] as String?,
    createdAt: m['created_at'] as String?,
    pinned: (m['pinned'] as bool?) ?? ((m['pinned'] as int?) == 1),
  );

  Goal copyWith({
    double? savedAmount,
    String? name,
    String? emoji,
    double? targetAmount,
    String? deadline,
    bool? pinned,
  }) => Goal(
    id: id,
    userId: userId,
    name: name ?? this.name,
    emoji: emoji ?? this.emoji,
    targetAmount: targetAmount ?? this.targetAmount,
    savedAmount: savedAmount ?? this.savedAmount,
    deadline: deadline ?? this.deadline,
    createdAt: createdAt,
    pinned: pinned ?? this.pinned,
  );
}

class WeeklyTarget {
  final String? id;
  final String userId;
  final String category; // matches ExpenseCategory.name
  /// Weekly spend ceiling (edited in “Edit target”).
  final double limitAmount;
  /// Spend logged via Goals → Log spend (cash / off‑app); **added** to transaction spend toward [limitAmount].
  final double manualSpentTopUp;
  final String? createdAt;
  final bool pinned;

  WeeklyTarget({
    this.id,
    required this.userId,
    required this.category,
    required this.limitAmount,
    this.manualSpentTopUp = 0,
    this.createdAt,
    this.pinned = false,
  });

  Map<String, dynamic> toInsertMap() => {
    'user_id': userId,
    'category': category,
    'limit_amount': limitAmount,
    'spent_manual_top_up': manualSpentTopUp,
  };

  Map<String, dynamic> toCacheMap() => {
    if (id != null) 'id': id,
    'user_id': userId,
    'category': category,
    'limit_amount': limitAmount,
    'spent_manual_top_up': manualSpentTopUp,
    'created_at': createdAt,
  };

  factory WeeklyTarget.fromMap(Map<String, dynamic> m) => WeeklyTarget(
    id: m['id']?.toString(),
    userId: m['user_id'] as String,
    category: m['category'] as String,
    limitAmount: (m['limit_amount'] as num?)?.toDouble() ?? 0,
    manualSpentTopUp: (m['spent_manual_top_up'] as num?)?.toDouble() ??
        (m['top_up_allowance'] as num?)?.toDouble() ??
        0,
    createdAt: m['created_at'] as String?,
    pinned: (m['pinned'] as bool?) ?? ((m['pinned'] as int?) == 1),
  );

  WeeklyTarget copyWith({double? limitAmount, double? manualSpentTopUp, bool? pinned}) => WeeklyTarget(
    id: id,
    userId: userId,
    category: category,
    limitAmount: limitAmount ?? this.limitAmount,
    manualSpentTopUp: manualSpentTopUp ?? this.manualSpentTopUp,
    createdAt: createdAt,
    pinned: pinned ?? this.pinned,
  );
}

/// Computed weekly spend per category (from transactions table for current week)
class WeeklySpend {
  final String category;
  final double spent;
  WeeklySpend({required this.category, required this.spent});
}

class WeeklyTargetHistoryEntry {
  final DateTime weekStart; // Monday
  final DateTime weekEnd; // Sunday (inclusive)
  final double txnSpend;
  final double manualSpend;
  final double limit;

  WeeklyTargetHistoryEntry({
    required this.weekStart,
    required this.weekEnd,
    required this.txnSpend,
    required this.manualSpend,
    required this.limit,
  });

  double get total => txnSpend + manualSpend;
}

// ---------------------------------------------------------------------------
// Repository
// ---------------------------------------------------------------------------

bool _weeklyManualColumnMissing(Object e) {
  final s = e.toString().toLowerCase();
  return s.contains('spent_manual_top_up') ||
      (s.contains('top_up_allowance') && s.contains('column'));
}

/// Local calendar day `YYYY-MM-DD` for consistent SQLite `substr(date,1,10)` filtering.
String _formatGoalYmd(DateTime localDay) {
  return '${localDay.year.toString().padLeft(4, '0')}-'
      '${localDay.month.toString().padLeft(2, '0')}-'
      '${localDay.day.toString().padLeft(2, '0')}';
}

/// Merge legacy labels (e.g. Transport → Travel) into canonical category names from [defaultCategories].
Map<String, double> _canonicalCategorySpendMap(Map<String, double> raw) {
  final out = <String, double>{};
  for (final e in raw.entries) {
    final name = getCategoryByName(e.key).name;
    out[name] = (out[name] ?? 0) + e.value;
  }
  return out;
}

WeeklyTarget _mergeWeeklyManual(WeeklyTarget fromRemote, WeeklyTarget requested) {
  return WeeklyTarget(
    id: fromRemote.id,
    userId: fromRemote.userId,
    category: fromRemote.category,
    limitAmount: fromRemote.limitAmount,
    manualSpentTopUp: requested.manualSpentTopUp,
    createdAt: fromRemote.createdAt,
  );
}

class GoalsRepository {
  final SupabaseClient _client;
  final _localDb = LocalDB.instance;

  GoalsRepository(this._client);

  String get _userId => _client.auth.currentUser!.id;
  String get userId => _userId;

  // ── Goals ──────────────────────────────────────────────────────────────────

  Future<List<Goal>> getCachedGoals() async {
    try {
      final local = await _localDb.getGoals(_userId);
      if (local.isNotEmpty) {
        final pinned = await _localDb.getPinnedItemIds(userId: _userId, itemType: 'goal');
        return local
            .map((m) => Goal.fromMap(m))
            .map((g) => g.copyWith(pinned: g.id != null && pinned.contains(g.id)))
            .toList();
      }
    } catch (e) { debugPrint('getCachedGoals local: $e'); }
    return getGoals();
  }

  Future<List<Goal>> getGoals() async {
    final data = await _client
        .from('goals')
        .select()
        .eq('user_id', _userId)
        .order('created_at', ascending: true);
    final goals = (data as List).map((m) => Goal.fromMap(m)).toList();
    try {
      await _localDb.upsertGoals(_userId, goals.map((g) => g.toCacheMap()).toList());
    } catch (e) { debugPrint('getGoals cache: $e'); }
    try {
      final pinned = await _localDb.getPinnedItemIds(userId: _userId, itemType: 'goal');
      return goals.map((g) => g.copyWith(pinned: g.id != null && pinned.contains(g.id))).toList();
    } catch (_) {
      return goals;
    }
  }

  Future<Goal> addGoal(Goal goal) async {
    final inserted = await _client.from('goals').insert(goal.toInsertMap()).select().single();
    final created = Goal.fromMap(inserted);
    try { await _localDb.upsertGoal(created.toCacheMap()); } catch (e) { debugPrint('addGoal cache: $e'); }
    return created;
  }

  Future<void> updateGoal(Goal goal) async {
    await _client.from('goals').update({
      'name': goal.name,
      'emoji': goal.emoji,
      'target_amount': goal.targetAmount,
      'saved_amount': goal.savedAmount,
      'deadline': goal.deadline,
    }).eq('id', goal.id!).eq('user_id', _userId);
    try { await _localDb.upsertGoal(goal.toCacheMap()); } catch (e) { debugPrint('updateGoal cache: $e'); }
  }

  Future<void> deleteGoal(String id) async {
    await _client.from('goals').delete().eq('id', id).eq('user_id', _userId);
    try { await _localDb.deleteGoalCache(id); } catch (e) { debugPrint('deleteGoal cache: $e'); }
  }

  // ── Weekly Targets ─────────────────────────────────────────────────────────

  Future<List<WeeklyTarget>> getCachedWeeklyTargets() async {
    try {
      final local = await _localDb.getWeeklyTargets(_userId);
      if (local.isNotEmpty) {
        final pinned = await _localDb.getPinnedItemIds(userId: _userId, itemType: 'weekly_target');
        return local
            .map((m) => WeeklyTarget.fromMap(m))
            .map((t) => t.copyWith(pinned: t.id != null && pinned.contains(t.id)))
            .toList();
      }
    } catch (e) { debugPrint('getCachedWeeklyTargets local: $e'); }
    return getWeeklyTargets();
  }

  Future<List<WeeklyTarget>> getWeeklyTargets() async {
    final data = await _client
        .from('weekly_targets')
        .select()
        .eq('user_id', _userId)
        .order('created_at', ascending: true);
    final remote = (data as List).map((m) => WeeklyTarget.fromMap(m)).toList();

    // When "Log spend" could not be written to Supabase (missing column, RLS, offline),
    // [updateWeeklyTarget] only patches SQLite. The next fetch used to wipe the cache from
    // remote rows with spent_manual_top_up = 0 — merge preserves that local manual spend.
    var targets = remote;
    try {
      final localRows = await _localDb.getWeeklyTargets(_userId);
      if (localRows.isNotEmpty) {
        final byId = <String, WeeklyTarget>{};
        final byCategory = <String, WeeklyTarget>{};
        for (final m in localRows) {
          final t = WeeklyTarget.fromMap(Map<String, dynamic>.from(m));
          final id = t.id;
          if (id != null && id.isNotEmpty) byId[id] = t;
          byCategory[t.category] = t;
        }
        targets = remote.map((row) {
          final local = (row.id != null && row.id!.isNotEmpty)
              ? byId[row.id!]
              : null;
          final match = local ?? byCategory[row.category];
          if (match == null) return row;
          final mergedManual = math.max(row.manualSpentTopUp, match.manualSpentTopUp);
          if (mergedManual == row.manualSpentTopUp) return row;
          return WeeklyTarget(
            id: row.id,
            userId: row.userId,
            category: row.category,
            limitAmount: row.limitAmount,
            manualSpentTopUp: mergedManual,
            createdAt: row.createdAt,
          );
        }).toList();

        for (var i = 0; i < targets.length; i++) {
          if (targets[i].manualSpentTopUp > remote[i].manualSpentTopUp) {
            final toSync = targets[i];
            Future<void>.microtask(() async {
              try {
                await updateWeeklyTarget(toSync);
              } catch (e) {
                debugPrint('getWeeklyTargets heal spent_manual_top_up: $e');
              }
            });
          }
        }
      }
    } catch (e) {
      debugPrint('getWeeklyTargets merge: $e');
    }

    try {
      await _localDb.upsertWeeklyTargets(_userId, targets.map((t) => t.toCacheMap()).toList());
    } catch (e) { debugPrint('getWeeklyTargets cache: $e'); }
    try {
      final pinned = await _localDb.getPinnedItemIds(userId: _userId, itemType: 'weekly_target');
      return targets.map((t) => t.copyWith(pinned: t.id != null && pinned.contains(t.id))).toList();
    } catch (_) {
      return targets;
    }
  }

  Future<void> setGoalPinned(Goal goal, bool pinned) async {
    final id = goal.id;
    if (id == null || id.isEmpty) {
      throw StateError('Goal must be saved before it can be pinned.');
    }
    await _localDb.setPinnedItem(
      userId: _userId,
      itemType: 'goal',
      itemId: id,
      pinned: pinned,
      maxPinned: 2,
    );
  }

  Future<void> setWeeklyTargetPinned(WeeklyTarget target, bool pinned) async {
    final id = target.id;
    if (id == null || id.isEmpty) {
      throw StateError('Target must be saved before it can be pinned.');
    }
    await _localDb.setPinnedItem(
      userId: _userId,
      itemType: 'weekly_target',
      itemId: id,
      pinned: pinned,
      maxPinned: 2,
    );
  }

  Future<WeeklyTarget> addWeeklyTarget(WeeklyTarget target) async {
    Map<String, dynamic> row;
    try {
      row = await _client.from('weekly_targets').insert(target.toInsertMap()).select().single();
    } catch (e) {
      if (!_weeklyManualColumnMissing(e)) rethrow;
      debugPrint('addWeeklyTarget: retry without spent_manual_top_up ($e)');
      final minimal = Map<String, dynamic>.from(target.toInsertMap())..remove('spent_manual_top_up');
      row = await _client.from('weekly_targets').insert(minimal).select().single();
    }
    final created = _mergeWeeklyManual(WeeklyTarget.fromMap(row), target);
    try {
      await _localDb.upsertWeeklyTarget(created.toCacheMap());
    } catch (e) {
      debugPrint('addWeeklyTarget cache: $e');
    }
    return created;
  }

  WeeklyTarget? _pickMatchingWeeklyTarget(List<WeeklyTarget> list, WeeklyTarget basis) {
    if (basis.id != null && basis.id!.isNotEmpty) {
      for (final t in list) {
        if (t.id == basis.id) return t;
      }
    }
    for (final t in list) {
      if (t.category == basis.category && t.userId == basis.userId) return t;
    }
    return null;
  }

  /// Adds [delta] to attributed **spent** (manually logged). Total toward the weekly target is
  /// transaction spend + [manualSpentTopUp], and cannot exceed [WeeklyTarget.limitAmount].
  Future<WeeklyTarget> addWeeklyManualSpendTopUp(WeeklyTarget basis, double delta) async {
    if (delta <= 0) {
      throw ArgumentError.value(delta, 'delta', 'Amount must be greater than zero.');
    }

    WeeklyTarget? current;

    try {
      final fresh = await getWeeklyTargets();
      current = _pickMatchingWeeklyTarget(fresh, basis);
    } catch (e) {
      debugPrint('addWeeklyManualSpendTopUp getWeeklyTargets: $e');
    }

    current ??= _pickMatchingWeeklyTarget(await getCachedWeeklyTargets(), basis);

    if (current == null) {
      try {
        final rows = await _localDb.getWeeklyTargets(_userId);
        final parsed = rows.map((m) => WeeklyTarget.fromMap(Map<String, dynamic>.from(m))).toList();
        current = _pickMatchingWeeklyTarget(parsed, basis);
      } catch (e) {
        debugPrint('addWeeklyManualSpendTopUp sqlite: $e');
      }
    }

    current ??= basis;

    final attributed = lookupWeeklySpendForCategory(
      await getWeeklyAttributedSpendByCategory(),
      current.category,
    );
    final limit = current.limitAmount;
    final manual = current.manualSpentTopUp;
    final room = limit - attributed;
    if (room <= 0) {
      throw StateError('Already at this week\'s spend target (₹${limit.round()}).');
    }
    final applied = delta > room ? room : delta;
    final next = WeeklyTarget(
      id: current.id,
      userId: current.userId,
      category: current.category,
      limitAmount: current.limitAmount,
      manualSpentTopUp: manual + applied,
      createdAt: current.createdAt,
    );
    final saved = await updateWeeklyTarget(next);
    if (applied > 0.001) {
      await _dualWriteWeeklyManualSpendLog(
        target: saved,
        amount: applied,
        occurredAt: DateTime.now(),
      );
    }
    return saved;
  }

  /// Persists manual “Log spend” detail to SQLite and Supabase (same row id).
  Future<void> _dualWriteWeeklyManualSpendLog({
    required WeeklyTarget target,
    required double amount,
    required DateTime occurredAt,
  }) async {
    final tid = target.id;
    if (tid == null || tid.isEmpty) {
      debugPrint('_dualWriteWeeklyManualSpendLog: skipping (no weekly target id)');
      return;
    }

    final id = const Uuid().v4();
    final occurredUtc = occurredAt.toUtc();
    final createdUtc = DateTime.now().toUtc();
    final row = <String, dynamic>{
      'id': id,
      'user_id': _userId,
      'weekly_target_id': tid,
      'category': target.category,
      'amount': amount,
      'occurred_at': occurredUtc.toIso8601String(),
      'created_at': createdUtc.toIso8601String(),
    };

    await _localDb.upsertWeeklyManualSpendLog(row);

    try {
      await _client.from('weekly_manual_spend_logs').insert({
        'id': id,
        'user_id': _userId,
        'weekly_target_id': tid,
        'category': target.category,
        'amount': amount,
        'occurred_at': occurredUtc.toIso8601String(),
        'created_at': createdUtc.toIso8601String(),
      });
      await VersionSync.instance.bumpVersion(SyncTable.weeklyManualSpendLogs);
    } catch (e, st) {
      debugPrint('weekly_manual_spend_logs cloud insert failed (local row saved): $e\n$st');
    }
  }

  /// Persists changes and returns the canonical row (remote when possible; otherwise local cache).
  ///
  /// Uses a plain [.select()] list response — PATCH + [.maybeSingle()] can yield null even when the
  /// row updated. Falls back to update-by-category, then local SQLite so changes work offline.
  Future<WeeklyTarget> updateWeeklyTarget(WeeklyTarget target) async {
    Map<String, dynamic>? firstRow(dynamic raw) {
      if (raw == null) return null;
      final list = raw is List ? raw : [raw];
      if (list.isEmpty) return null;
      final item = list.first;
      if (item is! Map) return null;
      return Map<String, dynamic>.from(item);
    }

    Future<Map<String, dynamic>?> remoteById() async {
      final id = target.id;
      if (id == null || id.isEmpty) return null;

      Future<Map<String, dynamic>?> patch(Map<String, dynamic> payload) async {
        final raw = await _client.from('weekly_targets').update(payload).eq('id', id).eq('user_id', _userId).select();
        return firstRow(raw);
      }

      final full = {
        'category': target.category,
        'limit_amount': target.limitAmount,
        'spent_manual_top_up': target.manualSpentTopUp,
      };
      try {
        return await patch(full);
      } catch (e) {
        if (!_weeklyManualColumnMissing(e)) {
          debugPrint('weekly_targets update by id: $e');
          return null;
        }
        debugPrint('weekly_targets update by id: retry without manual column ($e)');
        try {
          return await patch({
            'category': target.category,
            'limit_amount': target.limitAmount,
          });
        } catch (e2) {
          debugPrint('weekly_targets update by id fallback: $e2');
          return null;
        }
      }
    }

    Future<Map<String, dynamic>?> remoteByCategory() async {
      Future<Map<String, dynamic>?> patch(Map<String, dynamic> payload) async {
        final raw = await _client
            .from('weekly_targets')
            .update(payload)
            .eq('user_id', _userId)
            .eq('category', target.category)
            .select();
        return firstRow(raw);
      }

      final full = {
        'category': target.category,
        'limit_amount': target.limitAmount,
        'spent_manual_top_up': target.manualSpentTopUp,
      };
      try {
        return await patch(full);
      } catch (e) {
        if (!_weeklyManualColumnMissing(e)) {
          debugPrint('weekly_targets update by category: $e');
          return null;
        }
        debugPrint('weekly_targets update by category: retry without manual column ($e)');
        try {
          return await patch({
            'category': target.category,
            'limit_amount': target.limitAmount,
          });
        } catch (e2) {
          debugPrint('weekly_targets update by category fallback: $e2');
          return null;
        }
      }
    }

    Map<String, dynamic>? remote = await remoteById();
    remote ??= await remoteByCategory();

    if (remote != null) {
      final saved = _mergeWeeklyManual(WeeklyTarget.fromMap(remote), target);
      try {
        await _localDb.upsertWeeklyTarget(saved.toCacheMap());
      } catch (e) {
        debugPrint('updateWeeklyTarget cache: $e');
      }
      return saved;
    }

    // Offline / RLS / empty PATCH body: patch local cache so the UI updates immediately.
    try {
      await _localDb.patchWeeklyTargetSnapshot(
        userId: _userId,
        id: target.id,
        category: target.category,
        limitAmount: target.limitAmount,
        manualSpentTopUp: target.manualSpentTopUp,
      );
      final rows = await _localDb.getWeeklyTargets(_userId);
      Map<String, dynamic>? match;
      for (final m in rows) {
        final mid = m['id']?.toString();
        if (target.id != null && target.id!.isNotEmpty && mid == target.id) {
          match = Map<String, dynamic>.from(m);
          break;
        }
      }
      if (match == null) {
        for (final m in rows) {
          if (m['category'] == target.category) {
            match = Map<String, dynamic>.from(m);
            break;
          }
        }
      }
      if (match == null) {
        throw StateError('Weekly target not found after local update.');
      }
      final saved = WeeklyTarget.fromMap(match);
      try {
        await _localDb.upsertWeeklyTarget(saved.toCacheMap());
      } catch (e) {
        debugPrint('updateWeeklyTarget cache merge: $e');
      }
      return saved;
    } catch (e) {
      debugPrint('updateWeeklyTarget local fallback: $e');
      rethrow;
    }
  }

  Future<void> deleteWeeklyTarget(String id) async {
    await _client.from('weekly_targets').delete().eq('id', id).eq('user_id', _userId);
    try { await _localDb.deleteWeeklyTargetCache(id); } catch (e) { debugPrint('deleteWeeklyTarget cache: $e'); }
  }

  // ── Weekly Spend (computed from transactions) ──────────────────────────────

  /// Sums current week's (Mon–Sun) spending per category from transactions table
  Future<Map<String, double>> getWeeklySpendByCategory() async {
    final now = DateTime.now();
    // Monday as week start (local calendar)
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    final startDay = DateTime(weekStart.year, weekStart.month, weekStart.day);
    final todayDay = DateTime(now.year, now.month, now.day);
    final startYmd = _formatGoalYmd(startDay);
    final endYmd = _formatGoalYmd(todayDay);

    try {
      // Prefer local SQLite (calendar-day filter) so weekly cards match History.
      final cachedCount = await _localDb.countTransactionsForUser(_userId);
      if (cachedCount > 0) {
        final raw = await _localDb.sumTransactionsByCategoryForUserDateRange(
          userId: _userId,
          startYmd: startYmd,
          endYmdInclusive: endYmd,
        );
        return _canonicalCategorySpendMap(raw);
      }

      final data = await _client
          .from('transactions')
          .select('category, amount, date')
          .eq('user_id', _userId);

      final spendMap = <String, double>{};
      for (final row in (data as List)) {
        final dateStr = (row['date'] ?? '').toString();
        if (dateStr.length < 10) continue;
        final ymd = dateStr.substring(0, 10);
        if (ymd.compareTo(startYmd) < 0 || ymd.compareTo(endYmd) > 0) continue;
        final cat = row['category'] as String;
        final amt = (row['amount'] as num).toDouble();
        spendMap[cat] = (spendMap[cat] ?? 0) + amt;
      }
      return _canonicalCategorySpendMap(spendMap);
    } catch (e) {
      debugPrint('getWeeklySpendByCategory: $e');
      return {};
    }
  }

  /// Current week (Mon→today): **automatic** ledger spend plus **manual** rows from
  /// [weekly_manual_spend_logs] (same basis as weekly target history — not [WeeklyTarget.manualSpentTopUp]
  /// alone, which can drift).
  Future<Map<String, double>> getWeeklyAttributedSpendByCategory() async {
    final txn = await getWeeklySpendByCategory();
    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    final startYmd = _formatGoalYmd(DateTime(weekStart.year, weekStart.month, weekStart.day));
    final endYmd = _formatGoalYmd(DateTime(now.year, now.month, now.day));
    try {
      final manualRaw = await _localDb.sumWeeklyManualSpendByCategoryForDateYmdRange(
        userId: _userId,
        startYmd: startYmd,
        endYmdInclusive: endYmd,
      );
      final manual = _canonicalCategorySpendMap(manualRaw);
      final keys = {...txn.keys, ...manual.keys};
      final out = <String, double>{};
      for (final k in keys) {
        out[k] = (txn[k] ?? 0) + (manual[k] ?? 0);
      }
      return out;
    } catch (e) {
      debugPrint('getWeeklyAttributedSpendByCategory manual sum: $e — txn only');
      return txn;
    }
  }

  // ── Summary stats ──────────────────────────────────────────────────────────

  /// Total across all goals: [totalSaved, totalTarget]
  static (double, double) totals(List<Goal> goals) {
    double saved = 0, target = 0;
    for (final g in goals) {
      saved += g.savedAmount;
      target += g.targetAmount;
    }
    return (saved, target);
  }

  /// Hybrid hero: headline uses [savedAll] (every goal); progress & “to go” use active goals only.
  static ({
    double savedAll,
    double activeSaved,
    double activeTarget,
    double activeRemaining,
    int activeCount,
    int completedCount,
  }) heroSnapshot(List<Goal> goals) {
    double savedAll = 0;
    double activeSaved = 0;
    double activeTarget = 0;
    var completedCount = 0;
    for (final g in goals) {
      savedAll += g.savedAmount;
      if (g.isCompleted) {
        completedCount++;
      } else {
        activeSaved += g.savedAmount;
        activeTarget += g.targetAmount;
      }
    }
    final activeRemaining = math.max(0.0, activeTarget - activeSaved);
    final activeCount = goals.length - completedCount;
    return (
      savedAll: savedAll,
      activeSaved: activeSaved,
      activeTarget: activeTarget,
      activeRemaining: activeRemaining,
      activeCount: activeCount,
      completedCount: completedCount,
    );
  }

  static DateTime weekStartMonday(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    return d.subtract(Duration(days: d.weekday - 1));
  }

  Future<List<WeeklyTargetHistoryEntry>> getWeeklyTargetHistory({
    required WeeklyTarget target,
    int weeksBack = 12,
  }) async {
    final now = DateTime.now();
    final thisWeekStart = weekStartMonday(now);
    final entries = <WeeklyTargetHistoryEntry>[];

    for (var i = 0; i < weeksBack; i++) {
      final start = thisWeekStart.subtract(Duration(days: 7 * i));
      final end = start.add(const Duration(days: 6));
      final startYmd = _formatGoalYmd(DateTime(start.year, start.month, start.day));
      final endYmd = _formatGoalYmd(DateTime(end.year, end.month, end.day));

      final txnRaw = await _localDb.sumTransactionsByCategoryForUserDateRange(
        userId: _userId,
        startYmd: startYmd,
        endYmdInclusive: endYmd,
      );
      final manualRaw = await _localDb.sumWeeklyManualSpendByCategoryForDateYmdRange(
        userId: _userId,
        startYmd: startYmd,
        endYmdInclusive: endYmd,
      );
      final txnByCanon = _canonicalCategorySpendMap(txnRaw);
      final manualByCanon = _canonicalCategorySpendMap(manualRaw);
      final canon = getCategoryByName(target.category).name;
      final txn = txnByCanon[canon] ?? 0;
      final manual = manualByCanon[canon] ?? 0;

      entries.add(WeeklyTargetHistoryEntry(
        weekStart: start,
        weekEnd: end,
        txnSpend: txn,
        manualSpend: manual,
        limit: target.limitAmount,
      ));
    }

    return entries;
  }
}

final goalsRepositoryProvider = Provider<GoalsRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return GoalsRepository(client);
});
