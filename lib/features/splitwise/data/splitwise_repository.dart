import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/database/local_db.dart';
import '../../../core/database/version_sync.dart';
import '../../../core/supabase/supabase_config.dart';
import '../../../core/utils/phone_utils.dart';
import 'splitwise_models.dart';
import 'splitwise_projection_service.dart';

class SplitwiseRepository {
  final SupabaseClient _client;
  final _localDb = LocalDB.instance;

  SplitwiseRepository(this._client);

  String get _userId => _client.auth.currentUser!.id;
  String get userId => _userId;
  SplitwiseProjectionService get _projection =>
      SplitwiseProjectionService(_client);

  Future<List<ExpenseSplit>> getCachedSplitsForGroup(String groupId) async {
    try {
      final expenses = await _localDb.getExpenses(groupId);
      final expenseIds = expenses
          .map((row) => (row['id'] ?? '').toString())
          .where((id) => id.isNotEmpty)
          .toList();
      if (expenseIds.isEmpty) return [];
      final rows = await _localDb.getExpenseSplits(expenseIds);
      return rows.map((row) => ExpenseSplit.fromMap(row)).toList();
    } catch (e) {
      debugPrint('Local splits read failed: $e');
      return [];
    }
  }

  Future<List<SplitGroup>> getLocalGroups() async {
    final local = await _localDb.getGroups();
    return local.map((m) => SplitGroup.fromMap(m)).toList();
  }

  // ---------------------------------------------------------------------------
  // Groups
  // ---------------------------------------------------------------------------

  Future<List<SplitGroup>> getGroups() async {
    final userPhone = _client.auth.currentUser?.phone ?? '';

    // 1. Claim unclaimed memberships (backfill user_id where phone matches)
    try {
      await _client.rpc(
        'claim_memberships',
        params: {'p_user_id': _userId, 'p_phone': userPhone},
      );
    } catch (_) {}

    // 2. Get group IDs — try RPC first (bypasses RLS), fallback to direct query
    List<String> groupIds = [];
    try {
      final result = await _client.rpc(
        'get_my_group_ids',
        params: {'p_user_id': _userId, 'p_phone': userPhone},
      );
      groupIds = (result as List)
          .map((r) => r['group_id'] as String)
          .toSet()
          .toList();
    } catch (_) {
      // Fallback: direct query by user_id (works if claim_memberships already set it)
      final memberData = await _client
          .from('group_members')
          .select('group_id')
          .eq('user_id', _userId);
      groupIds = (memberData as List)
          .map((m) => m['group_id'] as String)
          .toSet()
          .toList();
    }

    if (groupIds.isEmpty) return [];

    // 3. Fetch the actual groups
    final data = await _client
        .from('split_groups')
        .select()
        .inFilter('id', groupIds)
        .order('created_at', ascending: false);

    final groups = (data as List).map((m) => SplitGroup.fromMap(m)).toList();

    // Cache locally
    try {
      await _localDb.upsertGroups(
        data
            .map(
              (m) => <String, dynamic>{
                'id': m['id'].toString(),
                'name': m['name'],
                'type': m['type'],
                'emoji': m['emoji'],
                'created_by': m['created_by'],
                'created_at': m['created_at'],
              },
            )
            .toList(),
      );
    } catch (e) {
      debugPrint('Cache groups failed: $e');
    }

    return groups;
  }

  /// Get groups from local cache first, fallback to cloud
  Future<List<SplitGroup>> getCachedGroups() async {
    try {
      final local = await _localDb.getGroups();
      if (local.isNotEmpty) {
        return local.map((m) => SplitGroup.fromMap(m)).toList();
      }
    } catch (e) {
      debugPrint('Local groups read failed: $e');
    }
    return getGroups();
  }

  Future<SplitGroup> createGroup(SplitGroup group) async {
    final data = await _client
        .from('split_groups')
        .insert(group.toInsertMap())
        .select()
        .single();
    VersionSync.instance.bumpVersion(SyncTable.splitGroups);
    return SplitGroup.fromMap(data);
  }

  Future<void> deleteGroup(String groupId) async {
    await _client.from('split_groups').delete().eq('id', groupId);
    await _localDb.deleteGroupCache(groupId);
    VersionSync.instance.bumpVersion(SyncTable.splitGroups);
  }

  // ---------------------------------------------------------------------------
  // Members
  // ---------------------------------------------------------------------------

  Future<List<GroupMember>> getMembers(String groupId) async {
    final data = await _client
        .from('group_members')
        .select()
        .eq('group_id', groupId);
    var members = (data as List)
        .map((m) => GroupMember.fromMap(m, currentUserId: _userId))
        .toList();
    members = await _hydrateMemberNames(members);

    // Cache
    try {
      await _localDb.upsertMembers(
        groupId,
        members
            .map(
              (m) => <String, dynamic>{
                'id': m.id,
                'group_id': m.groupId,
                'name': m.name,
                'phone': m.phone,
                'user_id': m.userId,
              },
            )
            .toList(),
      );
    } catch (e) {
      debugPrint('Cache members failed: $e');
    }

    return members;
  }

  Future<List<GroupMember>> getCachedMembers(String groupId) async {
    try {
      final local = await _localDb.getMembers(groupId);
      if (local.isNotEmpty) {
        return local
            .map((m) => GroupMember.fromMap(m, currentUserId: _userId))
            .toList();
      }
    } catch (e) {
      debugPrint('Local members read failed: $e');
    }
    return getMembers(groupId);
  }

  Future<GroupMember> addMember(GroupMember member) async {
    final phone = normalizePhone(member.phone);
    String? linkedUserId = member.userId;

    // If no userId provided, try to match phone to a registered user
    // Uses RPC to bypass RLS (profiles table restricts cross-user reads)
    if (linkedUserId == null && phone != null && phone.isNotEmpty) {
      try {
        final result = await _client.rpc(
          'lookup_user_by_phone',
          params: {'p_phone': phone},
        );
        if (result != null &&
            result.toString().isNotEmpty &&
            result.toString() != 'null') {
          linkedUserId = result.toString();
        }
      } catch (_) {}
    }

    final normalized = GroupMember(
      groupId: member.groupId,
      name: member.name,
      phone: phone,
      userId: linkedUserId,
    );

    // App-side duplicate guard (name / phone / linked user) before insert.
    final existingRows = await _client
        .from('group_members')
        .select('name, phone, user_id')
        .eq('group_id', member.groupId);
    final existing = List<Map<String, dynamic>>.from(existingRows as List);
    final normalizedName = normalized.name.trim().toLowerCase();
    final hasDuplicate = existing.any((row) {
      final rowName = ((row['name'] as String?) ?? '').trim().toLowerCase();
      final rowPhone = normalizePhone(row['phone'] as String?);
      final rowUserId = (row['user_id'] as String?) ?? '';
      final byName = normalizedName.isNotEmpty && rowName == normalizedName;
      final byPhone =
          phone != null &&
          phone.isNotEmpty &&
          rowPhone != null &&
          rowPhone.isNotEmpty &&
          rowPhone == phone;
      final byUserId =
          linkedUserId != null &&
          linkedUserId!.isNotEmpty &&
          rowUserId.isNotEmpty &&
          rowUserId == linkedUserId;
      return byName || byPhone || byUserId;
    });
    if (hasDuplicate) {
      throw StateError('duplicate member');
    }

    final data = await _client
        .from('group_members')
        .insert(normalized.toInsertMap())
        .select()
        .single();
    await _projection.markGroupDirty(member.groupId, reason: 'member_added');
    VersionSync.instance.bumpVersion(SyncTable.groupMembers);
    return GroupMember.fromMap(data, currentUserId: _userId);
  }

  Future<List<GroupMember>> _hydrateMemberNames(
    List<GroupMember> members,
  ) async {
    final userIds = members
        .map((member) => member.userId)
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    if (userIds.isEmpty) return members;

    final lookups = await Future.wait(
      userIds.map((userId) async {
        try {
          final profileName = await _client.rpc(
            'lookup_profile_name',
            params: {'p_user_id': userId},
          );
          final name = profileName?.toString();
          if (name == null || name.isEmpty || name == 'null') {
            return MapEntry(userId, null);
          }
          return MapEntry(userId, name);
        } catch (_) {
          return MapEntry(userId, null);
        }
      }),
    );

    final nameByUserId = <String, String>{};
    for (final entry in lookups) {
      final name = entry.value;
      if (name != null && name.isNotEmpty) {
        nameByUserId[entry.key] = name;
      }
    }

    return members.map((member) {
      final userId = member.userId;
      final hydratedName = userId == null ? null : nameByUserId[userId];
      if (hydratedName == null || hydratedName == member.name) {
        return member;
      }
      return member.copyWith(name: hydratedName);
    }).toList();
  }

  Future<void> removeMember(String memberId) async {
    final localRows = await _localDb.database.then(
      (db) => db.query(
        'group_members_cache',
        columns: ['group_id'],
        where: 'id = ?',
        whereArgs: [memberId],
        limit: 1,
      ),
    );
    await _client.from('group_members').delete().eq('id', memberId);
    final groupId = localRows.isNotEmpty
        ? (localRows.first['group_id'] ?? '').toString()
        : '';
    if (groupId.isNotEmpty) {
      await _projection.markGroupDirty(groupId, reason: 'member_removed');
    }
    VersionSync.instance.bumpVersion(SyncTable.groupMembers);
  }

  // ---------------------------------------------------------------------------
  // Saved Contacts (friends across groups)
  // ---------------------------------------------------------------------------

  Future<List<Map<String, String>>> getSavedContacts() async {
    final data = await _client
        .from('saved_contacts')
        .select()
        .eq('user_id', _userId)
        .order('name');
    return (data as List)
        .map(
          (m) => {
            'id': m['id'].toString(),
            'name': m['name'] as String,
            'phone': (m['phone'] as String?) ?? '',
          },
        )
        .toList();
  }

  Future<void> saveContact(String name, String? phone) async {
    try {
      await _client.from('saved_contacts').upsert({
        'user_id': _userId,
        'name': name,
        'phone': normalizePhone(phone),
      }, onConflict: 'user_id,name');
    } catch (_) {
      // Silently ignore — contact already saved, not critical
    }
  }

  // ---------------------------------------------------------------------------
  // Expenses
  // ---------------------------------------------------------------------------

  Future<List<SplitExpense>> getExpenses(String groupId) async {
    final data = await _client
        .from('split_expenses')
        .select()
        .eq('group_id', groupId)
        .order('created_at', ascending: false);
    final expenses = (data as List)
        .map((m) => SplitExpense.fromMap(m))
        .toList();

    try {
      await _localDb.upsertExpenses(
        groupId,
        data
            .map(
              (m) => <String, dynamic>{
                'id': m['id'].toString(),
                'group_id': m['group_id'],
                'description': m['description'],
                'amount': (m['amount'] as num).toDouble(),
                'paid_by': m['paid_by'],
                'split_type': m['split_type'],
                'category': m['category'],
                'created_at': m['created_at'],
              },
            )
            .toList(),
      );
    } catch (e) {
      debugPrint('Cache expenses failed: $e');
    }

    return expenses;
  }

  Future<List<SplitExpense>> getCachedExpenses(String groupId) async {
    try {
      final local = await _localDb.getExpenses(groupId);
      if (local.isNotEmpty) {
        return local.map((m) => SplitExpense.fromMap(m)).toList();
      }
    } catch (e) {
      debugPrint('Local expenses read failed: $e');
    }
    return getExpenses(groupId);
  }

  Future<SplitExpense> addExpense(
    SplitExpense expense,
    List<ExpenseSplit> splits,
  ) async {
    await _projection.markGroupDirty(expense.groupId, reason: 'expense_added');
    // Insert expense
    final expData = await _client
        .from('split_expenses')
        .insert(expense.toInsertMap())
        .select()
        .single();
    final created = SplitExpense.fromMap(expData);

    // Insert splits
    final splitRows = splits
        .map(
          (s) => {
            'expense_id': created.id,
            'member_id': s.memberId,
            'amount': s.amount,
          },
        )
        .toList();
    final splitData = await _client
        .from('expense_splits')
        .insert(splitRows)
        .select();

    try {
      await _localDb.upsertExpense({
        'id': created.id.toString(),
        'group_id': created.groupId,
        'description': created.description,
        'amount': created.amount,
        'paid_by': created.paidBy,
        'split_type': created.splitType,
        'category': created.category,
        'created_at': created.createdAt,
      });
      await _localDb.replaceExpenseSplitsForExpense(
        created.id!,
        (splitData as List)
            .map(
              (row) => <String, dynamic>{
                'id': row['id'].toString(),
                'expense_id': row['expense_id'],
                'member_id': row['member_id'],
                'amount': (row['amount'] as num).toDouble(),
              },
            )
            .toList(),
      );
      await _projection.recomputeGroupFromLocal(expense.groupId);
    } catch (e) {
      debugPrint('Local expense cache update failed: $e');
    }

    VersionSync.instance.bumpVersion(SyncTable.splitExpenses);
    return created;
  }

  Future<SplitExpense> updateExpense(
    String expenseId,
    SplitExpense expense,
    List<ExpenseSplit> splits,
  ) async {
    await _projection.markGroupDirty(
      expense.groupId,
      reason: 'expense_updated',
    );
    final expData = await _client
        .from('split_expenses')
        .update({
          'description': expense.description,
          'amount': expense.amount,
          'paid_by': expense.paidBy,
          'split_type': expense.splitType,
          'category': expense.category,
        })
        .eq('id', expenseId)
        .select()
        .single();
    final updated = SplitExpense.fromMap(expData);

    await _client.from('expense_splits').delete().eq('expense_id', expenseId);
    final splitRows = splits
        .map(
          (s) => {
            'expense_id': expenseId,
            'member_id': s.memberId,
            'amount': s.amount,
          },
        )
        .toList();
    final splitData = await _client
        .from('expense_splits')
        .insert(splitRows)
        .select();

    try {
      await _localDb.upsertExpense({
        'id': updated.id.toString(),
        'group_id': updated.groupId,
        'description': updated.description,
        'amount': updated.amount,
        'paid_by': updated.paidBy,
        'split_type': updated.splitType,
        'category': updated.category,
        'created_at': updated.createdAt,
      });
      await _localDb.replaceExpenseSplitsForExpense(
        expenseId,
        (splitData as List)
            .map(
              (row) => <String, dynamic>{
                'id': row['id'].toString(),
                'expense_id': row['expense_id'],
                'member_id': row['member_id'],
                'amount': (row['amount'] as num).toDouble(),
              },
            )
            .toList(),
      );
      await _projection.recomputeGroupFromLocal(expense.groupId);
    } catch (e) {
      debugPrint('Local expense update cache failed: $e');
    }

    VersionSync.instance.bumpVersion(SyncTable.splitExpenses);
    return updated;
  }

  Future<void> deleteExpense(
    String expenseId, {
    required String groupId,
  }) async {
    await _projection.markGroupDirty(groupId, reason: 'expense_deleted');
    await _client.from('split_expenses').delete().eq('id', expenseId);
    try {
      await _localDb.deleteExpenseCache(expenseId);
      await _localDb.deleteExpenseSplitsForExpense(expenseId);
      await _projection.recomputeGroupFromLocal(groupId);
    } catch (e) {
      debugPrint('Local expense delete cache failed: $e');
    }
    VersionSync.instance.bumpVersion(SyncTable.splitExpenses);
  }

  // ---------------------------------------------------------------------------
  // Splits
  // ---------------------------------------------------------------------------

  Future<List<ExpenseSplit>> getSplits(String groupId) async {
    final expenses = await getExpenses(groupId);
    return _getSplitsForExpenses(expenses);
  }

  /// Fetch splits for an already-loaded expense list (avoids a second getExpenses call)
  Future<List<ExpenseSplit>> _getSplitsForExpenses(
    List<SplitExpense> expenses,
  ) async {
    if (expenses.isEmpty) return [];

    final expenseIds = expenses.map((e) => e.id!).toList();
    final data = await _client
        .from('expense_splits')
        .select()
        .inFilter('expense_id', expenseIds);
    final splits = (data as List).map((m) => ExpenseSplit.fromMap(m)).toList();

    // Cache splits
    try {
      await _localDb.upsertExpenseSplits(
        data
            .map(
              (m) => <String, dynamic>{
                'id': m['id'].toString(),
                'expense_id': m['expense_id'],
                'member_id': m['member_id'],
                'amount': (m['amount'] as num).toDouble(),
              },
            )
            .toList(),
      );
    } catch (e) {
      debugPrint('Cache splits failed: $e');
    }

    return splits;
  }

  // ---------------------------------------------------------------------------
  // Settlements
  // ---------------------------------------------------------------------------

  Future<List<Settlement>> getSettlements(String groupId) async {
    final data = await _client
        .from('settlements')
        .select()
        .eq('group_id', groupId)
        .order('created_at', ascending: false);
    final settlements = (data as List)
        .map((m) => Settlement.fromMap(m))
        .toList();

    try {
      await _localDb.upsertSettlements(
        groupId,
        data
            .map(
              (m) => <String, dynamic>{
                'id': m['id'].toString(),
                'group_id': m['group_id'],
                'from_member': m['from_member'],
                'to_member': m['to_member'],
                'amount': (m['amount'] as num).toDouble(),
                'method': m['method'],
                'created_at': m['created_at'],
              },
            )
            .toList(),
      );
    } catch (e) {
      debugPrint('Cache settlements failed: $e');
    }

    return settlements;
  }

  Future<List<Settlement>> getCachedSettlements(String groupId) async {
    try {
      final local = await _localDb.getSettlements(groupId);
      if (local.isNotEmpty) {
        return local.map((m) => Settlement.fromMap(m)).toList();
      }
    } catch (e) {
      debugPrint('Local settlements read failed: $e');
    }
    return getSettlements(groupId);
  }

  Future<void> addSettlement(Settlement settlement) async {
    await _projection.markGroupDirty(
      settlement.groupId,
      reason: 'settlement_added',
    );
    final inserted = await _client
        .from('settlements')
        .insert(settlement.toInsertMap())
        .select()
        .single();
    try {
      await _localDb.upsertSettlement({
        'id': inserted['id'].toString(),
        'group_id': inserted['group_id'],
        'from_member': inserted['from_member'],
        'to_member': inserted['to_member'],
        'amount': (inserted['amount'] as num).toDouble(),
        'method': inserted['method'],
        'created_at': inserted['created_at'],
      });
      await _projection.recomputeGroupFromLocal(settlement.groupId);
    } catch (e) {
      debugPrint('Local settlement cache update failed: $e');
    }
    VersionSync.instance.bumpVersion(SyncTable.settlements);
  }

  Future<void> deleteSettlement(
    String settlementId, {
    required String groupId,
  }) async {
    await _projection.markGroupDirty(groupId, reason: 'settlement_deleted');
    await _client.from('settlements').delete().eq('id', settlementId);
    try {
      await _localDb.deleteSettlementCache(settlementId);
      await _projection.recomputeGroupFromLocal(groupId);
    } catch (e) {
      debugPrint('Local settlement delete cache failed: $e');
    }
    VersionSync.instance.bumpVersion(SyncTable.settlements);
  }

  // ---------------------------------------------------------------------------
  // Activity Log
  // ---------------------------------------------------------------------------

  Future<void> logActivity({
    required String groupId,
    required String action,
    required String description,
    String? details,
  }) async {
    try {
      await _client
          .from('expense_activity')
          .insert(
            ActivityEntry(
              groupId: groupId,
              userId: _userId,
              action: action,
              description: description,
              details: details,
            ).toInsertMap(),
          );
    } catch (e) {
      debugPrint('Log activity failed: $e');
    }
  }

  Future<List<ActivityEntry>> getActivity(String groupId) async {
    final data = await _client
        .from('expense_activity')
        .select()
        .eq('group_id', groupId)
        .order('created_at', ascending: false)
        .limit(50);
    return (data as List).map((m) => ActivityEntry.fromMap(m)).toList();
  }

  // ---------------------------------------------------------------------------
  // Computed: Balances for a group
  // ---------------------------------------------------------------------------

  Future<List<DebtEntry>> getSimplifiedDebts(String groupId) async {
    final expenses = await getExpenses(groupId);
    final splits = await _getSplitsForExpenses(expenses);
    final settlements = await getSettlements(groupId);
    final members = await getCachedMembers(groupId);
    return recomputeAndCacheGroupState(
      groupId: groupId,
      members: members,
      expenses: expenses,
      splits: splits,
      settlements: settlements,
    );
  }

  Future<List<DebtEntry>> recomputeAndCacheGroupState({
    required String groupId,
    List<GroupMember>? members,
    List<SplitExpense>? expenses,
    List<ExpenseSplit>? splits,
    List<Settlement>? settlements,
  }) async {
    final resolvedMembers = members ?? await getCachedMembers(groupId);
    final resolvedExpenses = expenses ?? await getCachedExpenses(groupId);
    final resolvedSplits = splits ?? await getCachedSplitsForGroup(groupId);
    final resolvedSettlements =
        settlements ?? await getCachedSettlements(groupId);
    await _projection.recomputeGroupFromData(
      groupId: groupId,
      members: resolvedMembers,
      expenses: resolvedExpenses,
      splits: resolvedSplits,
      settlements: resolvedSettlements,
    );
    return simplifyDebts(resolvedExpenses, resolvedSplits, resolvedSettlements);
  }

  /// Fast: read pre-computed debts from cache (no network, no calculation)
  Future<List<DebtEntry>> getCachedSimplifiedDebts(String groupId) async {
    try {
      final cached = await _localDb.getGroupDebts(groupId);
      if (cached.isNotEmpty) {
        return cached
            .map(
              (m) => DebtEntry(
                fromMemberId: m['from_member'] as String,
                toMemberId: m['to_member'] as String,
                amount: (m['amount'] as num).toDouble(),
              ),
            )
            .toList();
      }
    } catch (e) {
      debugPrint('Cached debts read failed: $e');
    }
    return []; // Return empty — cloud will populate
  }
}

final splitwiseRepositoryProvider = Provider<SplitwiseRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return SplitwiseRepository(client);
});
