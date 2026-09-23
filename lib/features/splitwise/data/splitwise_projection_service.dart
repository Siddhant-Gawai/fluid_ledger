import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/database/local_db.dart';
import '../../../core/supabase/supabase_config.dart';
import 'splitwise_models.dart';

class SplitwiseGroupSummary {
  final String groupId;
  final int memberCount;
  final int expenseCount;
  final int settlementCount;
  final double totalExpenses;
  final String? lastActivityAt;
  final double youOwe;
  final double owedToYou;
  final double net;
  final String? updatedAt;

  const SplitwiseGroupSummary({
    required this.groupId,
    required this.memberCount,
    required this.expenseCount,
    required this.settlementCount,
    required this.totalExpenses,
    required this.lastActivityAt,
    required this.youOwe,
    required this.owedToYou,
    required this.net,
    required this.updatedAt,
  });

  factory SplitwiseGroupSummary.fromMap(Map<String, dynamic> row) {
    return SplitwiseGroupSummary(
      groupId: (row['group_id'] ?? '').toString(),
      memberCount: (row['member_count'] as num?)?.toInt() ?? 0,
      expenseCount: (row['expense_count'] as num?)?.toInt() ?? 0,
      settlementCount: (row['settlement_count'] as num?)?.toInt() ?? 0,
      totalExpenses: (row['total_expenses'] as num?)?.toDouble() ?? 0,
      lastActivityAt: row['last_activity_at'] as String?,
      youOwe: (row['you_owe'] as num?)?.toDouble() ?? 0,
      owedToYou: (row['owed_to_you'] as num?)?.toDouble() ?? 0,
      net: (row['net'] as num?)?.toDouble() ?? 0,
      updatedAt: row['updated_at'] as String?,
    );
  }
}

class SplitwiseProjectionService {
  SplitwiseProjectionService(this._client);

  final SupabaseClient _client;
  final LocalDB _localDb = LocalDB.instance;

  String get _userId => _client.auth.currentUser!.id;

  Future<void> markGroupDirty(String groupId, {String? reason}) {
    return _localDb.markGroupRecomputeDirty(groupId, reason: reason);
  }

  Future<Map<String, SplitwiseGroupSummary>> getCachedSummaries() async {
    final rows = await _localDb.getAllGroupSummaries();
    return rows.map(
      (groupId, row) => MapEntry(groupId, SplitwiseGroupSummary.fromMap(row)),
    );
  }

  Future<SplitwiseGroupSummary?> getCachedSummary(String groupId) async {
    final row = await _localDb.getGroupSummary(groupId);
    if (row == null) return null;
    return SplitwiseGroupSummary.fromMap(row);
  }

  Future<List<String>> getDirtyGroupIds() async {
    final rows = await _localDb.getDirtyGroupRecomputes();
    return rows
        .map((row) => (row['group_id'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toList();
  }

  Future<SplitwiseGroupSummary> recomputeGroupFromLocal(String groupId) async {
    final memberRows = await _localDb.getMembers(groupId);
    final expenseRows = await _localDb.getExpenses(groupId);
    final settlementRows = await _localDb.getSettlements(groupId);
    final expenseIds = expenseRows
        .map((row) => (row['id'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toList();
    final splitRows = expenseIds.isEmpty
        ? const <Map<String, dynamic>>[]
        : await _localDb.getExpenseSplits(expenseIds);

    final members = memberRows
        .map((row) => GroupMember.fromMap(row, currentUserId: _userId))
        .toList();
    final expenses = expenseRows.map(SplitExpense.fromMap).toList();
    final settlements = settlementRows.map(Settlement.fromMap).toList();
    final splits = splitRows.map(ExpenseSplit.fromMap).toList();

    return recomputeGroupFromData(
      groupId: groupId,
      members: members,
      expenses: expenses,
      splits: splits,
      settlements: settlements,
    );
  }

  Future<SplitwiseGroupSummary> refreshGroupFromRemote(String groupId) async {
    final membersData = await _client
        .from('group_members')
        .select()
        .eq('group_id', groupId);
    final expensesData = await _client
        .from('split_expenses')
        .select()
        .eq('group_id', groupId)
        .order('created_at', ascending: false);
    final settlementsData = await _client
        .from('settlements')
        .select()
        .eq('group_id', groupId)
        .order('created_at', ascending: false);

    final expenseIds = (expensesData as List)
        .map((row) => (row['id'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toList();
    final splitsData = expenseIds.isEmpty
        ? <Map<String, dynamic>>[]
        : List<Map<String, dynamic>>.from(
            await _client
                .from('expense_splits')
                .select()
                .inFilter('expense_id', expenseIds),
          );

    await _localDb.upsertMembers(
      groupId,
      List<Map<String, dynamic>>.from(membersData).map((row) {
        return <String, dynamic>{
          'id': row['id']?.toString(),
          'group_id': row['group_id'],
          'name': row['name'],
          'phone': row['phone'],
          'user_id': row['user_id'],
        };
      }).toList(),
    );
    await _localDb.upsertExpenses(
      groupId,
      List<Map<String, dynamic>>.from(expensesData).map((row) {
        return <String, dynamic>{
          'id': row['id']?.toString(),
          'group_id': row['group_id'],
          'description': row['description'],
          'amount': (row['amount'] as num).toDouble(),
          'paid_by': row['paid_by'],
          'split_type': row['split_type'],
          'category': row['category'],
          'created_at': row['created_at'],
        };
      }).toList(),
    );
    await _localDb.upsertSettlements(
      groupId,
      List<Map<String, dynamic>>.from(settlementsData).map((row) {
        return <String, dynamic>{
          'id': row['id']?.toString(),
          'group_id': row['group_id'],
          'from_member': row['from_member'],
          'to_member': row['to_member'],
          'amount': (row['amount'] as num).toDouble(),
          'method': row['method'],
          'created_at': row['created_at'],
        };
      }).toList(),
    );
    await _localDb.upsertExpenseSplits(
      splitsData.map((row) {
        return <String, dynamic>{
          'id': row['id']?.toString(),
          'expense_id': row['expense_id'],
          'member_id': row['member_id'],
          'amount': (row['amount'] as num).toDouble(),
        };
      }).toList(),
    );

    final members = List<Map<String, dynamic>>.from(
      membersData,
    ).map((row) => GroupMember.fromMap(row, currentUserId: _userId)).toList();
    final expenses = List<Map<String, dynamic>>.from(
      expensesData,
    ).map(SplitExpense.fromMap).toList();
    final settlements = List<Map<String, dynamic>>.from(
      settlementsData,
    ).map(Settlement.fromMap).toList();
    final splits = splitsData.map(ExpenseSplit.fromMap).toList();

    return recomputeGroupFromData(
      groupId: groupId,
      members: members,
      expenses: expenses,
      splits: splits,
      settlements: settlements,
    );
  }

  Future<void> refreshGroupsFromRemote(Iterable<String> groupIds) async {
    final ids = groupIds.where((id) => id.isNotEmpty).toSet().toList();
    await Future.wait(
      ids.map((groupId) async {
        try {
          await refreshGroupFromRemote(groupId);
        } catch (e) {
          debugPrint('Projection refresh failed for $groupId: $e');
        }
      }),
    );
  }

  Future<void> refreshDirtyGroups() async {
    final ids = await getDirtyGroupIds();
    if (ids.isEmpty) return;
    await refreshGroupsFromRemote(ids);
  }

  Future<SplitwiseGroupSummary> recomputeGroupFromData({
    required String groupId,
    required List<GroupMember> members,
    required List<SplitExpense> expenses,
    required List<ExpenseSplit> splits,
    required List<Settlement> settlements,
  }) async {
    final debts = simplifyDebts(expenses, splits, settlements);
    await _localDb.saveGroupDebts(
      groupId,
      debts
          .map(
            (d) => {
              'from_member': d.fromMemberId,
              'to_member': d.toMemberId,
              'amount': d.amount,
            },
          )
          .toList(),
    );

    final me = members.where((member) => member.isCurrentUser).firstOrNull;
    var youOwe = 0.0;
    var owedToYou = 0.0;
    if (me != null && me.id != null) {
      for (final debt in debts) {
        if (debt.fromMemberId == me.id) {
          youOwe += debt.amount;
        } else if (debt.toMemberId == me.id) {
          owedToYou += debt.amount;
        }
      }
      await _localDb.saveGroupBalance(groupId, youOwe, owedToYou);
    }

    final totalExpenses = expenses.fold<double>(0, (sum, e) => sum + e.amount);
    final lastActivityAt =
        [
          ...expenses.map((e) => e.createdAt),
          ...settlements.map((s) => s.createdAt),
        ].whereType<String>().fold<String?>(null, (latest, value) {
          if (latest == null || value.compareTo(latest) > 0) return value;
          return latest;
        });

    await _localDb.saveGroupSummary(
      groupId,
      memberCount: members.length,
      expenseCount: expenses.length,
      settlementCount: settlements.length,
      totalExpenses: totalExpenses,
      lastActivityAt: lastActivityAt,
      youOwe: youOwe,
      owedToYou: owedToYou,
    );
    await _localDb.clearGroupRecomputeDirty(groupId);

    final summaryRow = await _localDb.getGroupSummary(groupId);
    return SplitwiseGroupSummary.fromMap(
      summaryRow ??
          <String, dynamic>{
            'group_id': groupId,
            'member_count': members.length,
            'expense_count': expenses.length,
            'settlement_count': settlements.length,
            'total_expenses': totalExpenses,
            'last_activity_at': lastActivityAt,
            'you_owe': youOwe,
            'owed_to_you': owedToYou,
            'net': owedToYou - youOwe,
          },
    );
  }
}

final splitwiseProjectionServiceProvider = Provider<SplitwiseProjectionService>(
  (ref) {
    final client = ref.watch(supabaseClientProvider);
    return SplitwiseProjectionService(client);
  },
);
