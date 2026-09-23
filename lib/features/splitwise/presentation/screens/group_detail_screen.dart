import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../../core/common_widgets/hero_screen_themes.dart';
import '../../../../core/common_widgets/premium_modal.dart';
import '../../../../core/common_widgets/premium_surface_card.dart';
import '../../../../core/common_widgets/skeleton_loader.dart';
import '../../../../core/database/local_db.dart';
import '../../../../core/database/version_sync.dart';
import '../../../../core/utils/phone_utils.dart';
import '../../../../core/utils/snackbar_helper.dart';
import '../../data/splitwise_models.dart';
import '../../data/splitwise_realtime_service.dart';
import '../../data/splitwise_repository.dart';

class GroupDetailScreen extends ConsumerStatefulWidget {
  final String groupId;
  final bool autoOpenAddExpense;
  const GroupDetailScreen({
    super.key,
    required this.groupId,
    this.autoOpenAddExpense = false,
  });

  @override
  ConsumerState<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends ConsumerState<GroupDetailScreen> {
  List<GroupMember> _members = [];
  List<SplitExpense> _expenses = [];
  List<DebtEntry> _debts = [];
  List<Settlement> _settlements = [];
  List<ActivityEntry> _activity = [];
  Map<String, List<ExpenseSplit>> _splitsMap = {}; // expense_id -> splits
  bool _loading = true;
  String? _longPressedExpenseId;
  SplitGroup? _group;
  bool _settlingAllDebts = false;
  bool _handledAutoOpenAddExpense = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final repo = ref.read(splitwiseRepositoryProvider);
      await _loadLocalSnapshot();

      // 2. Sync only stale tables (lightweight version check)
      final synced = await VersionSync.instance.syncStale();
      final dataChanged =
          synced.contains(SyncTable.splitExpenses) ||
          synced.contains(SyncTable.settlements) ||
          synced.contains(SyncTable.groupMembers);

      // 3. Re-fetch from cloud only if data changed or empty
      if (dataChanged || _members.isEmpty) {
        final members = await repo.getMembers(widget.groupId);
        final expenses = await repo.getExpenses(widget.groupId);
        final settlements = await repo.getSettlements(widget.groupId);
        final allSplits = await repo.getSplits(widget.groupId);
        final debts = await repo.recomputeAndCacheGroupState(
          groupId: widget.groupId,
          members: members,
          expenses: expenses,
          splits: allSplits,
          settlements: settlements,
        );
        final activity = await repo.getActivity(widget.groupId);
        if (mounted) {
          setState(() {
            _members = members;
            _expenses = expenses;
            _debts = debts;
            _settlements = settlements;
            _activity = activity;
            _splitsMap = _splitsByExpense(allSplits);
            _loading = false;
          });
          _maybeAutoOpenAddExpense();
        }
      } else if (_activity.isEmpty) {
        // Activity not cached — always fetch on first load
        try {
          final activity = await repo.getActivity(widget.groupId);
          if (mounted) {
            setState(() => _activity = activity);
          }
        } catch (_) {}
        if (mounted) {
          setState(() {
            _loading = false;
          });
          _maybeAutoOpenAddExpense();
        }
      } else if (mounted) {
        setState(() {
          _loading = false;
        });
        _maybeAutoOpenAddExpense();
      }
    } catch (e) {
      debugPrint('Error in group_detail_screen.dart: $e');
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _maybeAutoOpenAddExpense() {
    if (!widget.autoOpenAddExpense || _handledAutoOpenAddExpense) return;
    _handledAutoOpenAddExpense = true;
    if (_members.length < 2) {
      showInfoSnackBar('Add members first to split an expense');
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _showAddExpense(Theme.of(context).colorScheme);
    });
  }

  String _memberName(String memberId) {
    final m = _members.firstWhere(
      (m) => m.id == memberId,
      orElse: () => GroupMember(groupId: '', name: '?'),
    );
    return m.isCurrentUser ? 'You' : m.name;
  }

  double get _totalExpenses => _expenses.fold(0.0, (s, e) => s + e.amount);

  List<ExpenseSplit> get _allSplits =>
      _splitsMap.values.expand((groupSplits) => groupSplits).toList();

  Map<String, List<ExpenseSplit>> _splitsByExpense(List<ExpenseSplit> splits) {
    final map = <String, List<ExpenseSplit>>{};
    for (final split in splits) {
      map.putIfAbsent(split.expenseId, () => []).add(split);
    }
    return map;
  }

  void _recomputeLocalDebts() {
    _debts = simplifyDebts(_expenses, _allSplits, _settlements);
  }

  DebtEntry? _primaryDebtForCurrentUser() {
    if (_debts.isEmpty) return null;
    final me = _members.where((m) => m.isCurrentUser).firstOrNull;
    if (me == null) return _debts.first;
    return _debts.where((d) => d.fromMemberId == me.id).firstOrNull ??
        _debts.first;
  }

  Future<void> _settleAllDebts(ColorScheme colors) async {
    if (_settlingAllDebts || _debts.isEmpty) return;
    final pending = List<DebtEntry>.from(_debts);
    final total = pending.fold<double>(0, (sum, d) => sum + d.amount);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Settle all balances?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This will record ${pending.length} settlement${pending.length == 1 ? '' : 's'} for a total of ₹${NumberFormat('#,##,###', 'en_IN').format(total.round())}.',
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    child: const Text('Settle all'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _settlingAllDebts = true);
    final optimistic = pending
        .map(
          (d) => Settlement(
            id: 'local_bulk_${DateTime.now().microsecondsSinceEpoch}_${d.fromMemberId}_${d.toMemberId}',
            groupId: widget.groupId,
            fromMember: d.fromMemberId,
            toMember: d.toMemberId,
            amount: d.amount,
            method: 'cash',
            createdAt: DateTime.now().toIso8601String(),
          ),
        )
        .toList();

    setState(() {
      _settlements.insertAll(0, optimistic);
      _recomputeLocalDebts();
    });

    try {
      final repo = ref.read(splitwiseRepositoryProvider);
      for (final d in pending) {
        await repo.addSettlement(
          Settlement(
            groupId: widget.groupId,
            fromMember: d.fromMemberId,
            toMember: d.toMemberId,
            amount: d.amount,
            method: 'cash',
          ),
        );
      }
      await _loadLocalSnapshot();
      if (!mounted) return;
      showSuccessSnackBar('All balances settled');
    } catch (_) {
      if (!mounted) return;
      setState(() {
        for (final s in optimistic) {
          _settlements.removeWhere((e) => e.id == s.id);
        }
        _recomputeLocalDebts();
      });
      showErrorSnackBar('Failed to settle all balances. Please retry.');
    } finally {
      if (mounted) {
        setState(() => _settlingAllDebts = false);
      }
    }
  }

  Color _memberAccent(ColorScheme colors, String memberId) {
    const palette = <Color>[
      Color(0xFF142A6E),
      Color(0xFF1D6B7A),
      Color(0xFF2E4AA3),
      Color(0xFF0F9D8A),
      Color(0xFFEF6C57),
      Color(0xFF6574CD),
    ];
    final index = memberId.isEmpty
        ? 0
        : memberId.codeUnitAt(0) % palette.length;
    return palette[index];
  }

  String _memberInitial(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    final parts = trimmed.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    final one = parts.first;
    return one.length >= 2 ? one.substring(0, 2).toUpperCase() : one[0].toUpperCase();
  }

  String _owedBreakdownText() {
    final me = _members.where((m) => m.isCurrentUser).firstOrNull;
    if (me == null) return '';
    final rows = _debts.where((d) => d.toMemberId == me.id).toList()
      ..sort((a, b) => b.amount.compareTo(a.amount));
    if (rows.isEmpty) return '';
    final parts = rows
        .take(3)
        .map((d) => '${_memberName(d.fromMemberId)} owes ₹${d.amount.round()}')
        .toList();
    if (rows.length > 3) parts.add('+${rows.length - 3} more');
    return parts.join(' · ');
  }

  Future<void> _loadLocalSnapshot({bool preserveActivity = true}) async {
    final repo = ref.read(splitwiseRepositoryProvider);
    final localDb = LocalDB.instance;

    final localGroups = await repo.getLocalGroups();
    final foundGroup = localGroups
        .where((g) => g.id == widget.groupId)
        .firstOrNull;

    final memberRows = await localDb.getMembers(widget.groupId);
    final expenseRows = await localDb.getExpenses(widget.groupId);
    final settlementRows = await localDb.getSettlements(widget.groupId);
    final debtRows = await localDb.getGroupDebts(widget.groupId);
    final splits = await repo.getCachedSplitsForGroup(widget.groupId);

    final members = memberRows
        .map((row) => GroupMember.fromMap(row, currentUserId: repo.userId))
        .toList();
    final expenses = expenseRows
        .map((row) => SplitExpense.fromMap(row))
        .toList();
    final settlements = settlementRows
        .map((row) => Settlement.fromMap(row))
        .toList();
    final debts = debtRows.isNotEmpty
        ? debtRows
              .map(
                (row) => DebtEntry(
                  fromMemberId: row['from_member'] as String,
                  toMemberId: row['to_member'] as String,
                  amount: (row['amount'] as num).toDouble(),
                ),
              )
              .toList()
        : simplifyDebts(expenses, splits, settlements);

    if (!mounted) return;
    if (members.isEmpty &&
        expenses.isEmpty &&
        settlements.isEmpty &&
        splits.isEmpty &&
        foundGroup == null) {
      return;
    }

    setState(() {
      if (foundGroup != null) {
        _group = foundGroup;
      }
      _members = members;
      _expenses = expenses;
      _settlements = settlements;
      _splitsMap = _splitsByExpense(splits);
      _debts = debts;
      if (!preserveActivity) {
        _activity = [];
      }
      _loading = false;
    });
  }

  // ---------------------------------------------------------------------------
  // Add member — from phone contacts, saved contacts, or manual
  // ---------------------------------------------------------------------------
  void _showAddMember(ColorScheme colors) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _AddMemberSheet(
        colors: colors,
        groupId: widget.groupId,
        existingMembers: _members,
        repo: ref.read(splitwiseRepositoryProvider),
        onAdded: () {
          Navigator.pop(ctx);
          _load();
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Add / Edit expense
  // ---------------------------------------------------------------------------
  void _showAddExpense(ColorScheme colors, {SplitExpense? editing}) {
    if (_members.length < 2) {
      showInfoSnackBar('Add at least 2 members first');
      return;
    }

    final amountController = TextEditingController(
      text: editing != null
          ? (editing.amount == editing.amount.roundToDouble()
                ? editing.amount.round().toString()
                : editing.amount.toStringAsFixed(2))
          : '',
    );
    final descController = TextEditingController(
      text: editing?.description ?? '',
    );
    final noteController = TextEditingController(text: editing?.category ?? '');
    String? paidBy =
        editing?.paidBy ??
        (_members.where((m) => m.isCurrentUser).firstOrNull ??
                _members.firstOrNull)
            ?.id;
    final selected = Set<String>.from(_members.map((m) => m.id!));
    String splitType = editing?.splitType ?? 'equal';
    final exactControllers = <String, TextEditingController>{};
    for (final m in _members) {
      exactControllers[m.id!] = TextEditingController();
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, ss) {
          // Compute per-person amount for display
          final totalAmount =
              double.tryParse(amountController.text.trim()) ?? 0;
          final perPerson = selected.isNotEmpty && splitType == 'equal'
              ? totalAmount / selected.length
              : 0.0;

          return PremiumSheetContainer(
            variant: PremiumSurfaceVariant.split,
            maxHeight: MediaQuery.of(ctx).size.height * 0.92,
            padding: EdgeInsets.zero,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Scrollable content
                Flexible(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.only(
                      bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Handle bar
                        const SizedBox(height: 12),
                        Center(
                          child: Container(
                            width: 40,
                            height: 4,
                            decoration: BoxDecoration(
                              color: colors.outlineVariant.withValues(
                                alpha: 0.3,
                              ),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Title
                        Center(
                          child: Text(
                            'Split Expense',
                            style: GoogleFonts.manrope(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: colors.onSurface,
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // 1. AMOUNT HERO — gradient card
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF24389c), Color(0xFF3f51b5)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(32),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  'ENTER TOTAL AMOUNT',
                                  style: GoogleFonts.inter(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white.withValues(alpha: 0.6),
                                    letterSpacing: 1.5,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Text(
                                      '₹',
                                      style: GoogleFonts.manrope(
                                        fontSize: 36,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white.withValues(
                                          alpha: 0.4,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    IntrinsicWidth(
                                      child: TextField(
                                        controller: amountController,
                                        autofocus: editing == null,
                                        keyboardType: TextInputType.number,
                                        inputFormatters: [
                                          FilteringTextInputFormatter.allow(
                                            RegExp(r'[\d.]'),
                                          ),
                                        ],
                                        textAlign: TextAlign.center,
                                        onChanged: (_) => ss(() {}),
                                        style: GoogleFonts.manrope(
                                          fontSize: 48,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.white,
                                        ),
                                        decoration: InputDecoration(
                                          hintText: '0',
                                          hintStyle: GoogleFonts.manrope(
                                            fontSize: 48,
                                            fontWeight: FontWeight.w800,
                                            color: Colors.white.withValues(
                                              alpha: 0.3,
                                            ),
                                          ),
                                          border: InputBorder.none,
                                          filled: false,
                                          isDense: true,
                                          contentPadding: EdgeInsets.zero,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                // Description field inside gradient card
                                Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: TextField(
                                    controller: descController,
                                    textCapitalization:
                                        TextCapitalization.sentences,
                                    style: GoogleFonts.manrope(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    ),
                                    decoration: InputDecoration(
                                      hintText:
                                          'What was it for? (e.g. Dinner, Uber)',
                                      hintStyle: GoogleFonts.inter(
                                        fontSize: 14,
                                        color: Colors.white.withValues(
                                          alpha: 0.4,
                                        ),
                                      ),
                                      prefixIcon: Icon(
                                        Icons.receipt_outlined,
                                        size: 20,
                                        color: Colors.white.withValues(
                                          alpha: 0.5,
                                        ),
                                      ),
                                      border: InputBorder.none,
                                      filled: false,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 14,
                                          ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // 2. PAID BY — horizontal scrollable avatar chips
                        Padding(
                          padding: const EdgeInsets.only(left: 20),
                          child: Text(
                            'PAID BY',
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: colors.onSurfaceVariant,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 44,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            itemCount: _members.length,
                            separatorBuilder: (_, separatorIndex) =>
                                const SizedBox(width: 8),
                            itemBuilder: (_, i) {
                              final m = _members[i];
                              final isSel = paidBy == m.id;
                              return GestureDetector(
                                onTap: () => ss(() => paidBy = m.id),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isSel
                                        ? colors.primary
                                        : colors.surfaceContainerLowest,
                                    borderRadius: BorderRadius.circular(22),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      CircleAvatar(
                                        radius: 13,
                                        backgroundColor: isSel
                                            ? Colors.white.withValues(
                                                alpha: 0.2,
                                              )
                                            : colors.primary.withValues(
                                                alpha: 0.1,
                                              ),
                                        child: Text(
                                          (m.name.isNotEmpty ? m.name[0] : '?')
                                              .toUpperCase(),
                                          style: GoogleFonts.manrope(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: isSel
                                                ? Colors.white
                                                : colors.primary,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        m.isCurrentUser ? 'You' : m.name,
                                        style: GoogleFonts.inter(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: isSel
                                              ? Colors.white
                                              : colors.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 20),

                        // 3. SPLIT METHOD — card with toggle + member list
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: colors.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(32),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Header row: title + toggle chips
                                Row(
                                  children: [
                                    Text(
                                      'Split Method',
                                      style: GoogleFonts.manrope(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        color: colors.onSurface,
                                      ),
                                    ),
                                    const Spacer(),
                                    Container(
                                      padding: const EdgeInsets.all(3),
                                      decoration: BoxDecoration(
                                        color: colors.surfaceContainerLowest,
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          _splitToggleChip(
                                            'equal',
                                            'Equally',
                                            splitType,
                                            colors,
                                            (v) => ss(() => splitType = v),
                                          ),
                                          _splitToggleChip(
                                            'percentage',
                                            '%',
                                            splitType,
                                            colors,
                                            (v) => ss(() => splitType = v),
                                          ),
                                          _splitToggleChip(
                                            'exact',
                                            '₹',
                                            splitType,
                                            colors,
                                            (v) => ss(() => splitType = v),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),

                                // Member list
                                ..._members.map((m) {
                                  final isIn = selected.contains(m.id);
                                  final isPayer = m.id == paidBy;
                                  // Compute this member's share text
                                  String shareText;
                                  if (!isIn) {
                                    shareText = 'Excluded';
                                  } else if (isPayer) {
                                    shareText =
                                        'Paid ₹${totalAmount > 0 ? totalAmount.toStringAsFixed(2) : "0.00"}';
                                  } else {
                                    shareText = 'Owing portion';
                                  }
                                  // Compute displayed amount
                                  String amtText = '';
                                  if (isIn &&
                                      splitType == 'equal' &&
                                      totalAmount > 0) {
                                    amtText =
                                        '₹${perPerson.toStringAsFixed(0)}';
                                  } else if (isIn && splitType != 'equal') {
                                    final val =
                                        double.tryParse(
                                          exactControllers[m.id]?.text ?? '',
                                        ) ??
                                        0;
                                    if (splitType == 'exact') {
                                      amtText = val > 0
                                          ? '₹${val.toStringAsFixed(0)}'
                                          : '';
                                    } else {
                                      amtText = val > 0
                                          ? '${val.toStringAsFixed(0)}%'
                                          : '';
                                    }
                                  }

                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: Row(
                                      children: [
                                        // Avatar with green check badge if included
                                        Stack(
                                          clipBehavior: Clip.none,
                                          children: [
                                            CircleAvatar(
                                              radius: 20,
                                              backgroundColor: isIn
                                                  ? colors.primary.withValues(
                                                      alpha: 0.12,
                                                    )
                                                  : colors.outlineVariant
                                                        .withValues(
                                                          alpha: 0.12,
                                                        ),
                                              child: Text(
                                                (m.name.isNotEmpty
                                                        ? m.name[0]
                                                        : '?')
                                                    .toUpperCase(),
                                                style: GoogleFonts.manrope(
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w700,
                                                  color: isIn
                                                      ? colors.primary
                                                      : colors.outlineVariant,
                                                ),
                                              ),
                                            ),
                                            if (isIn)
                                              Positioned(
                                                right: -2,
                                                bottom: -2,
                                                child: Container(
                                                  width: 16,
                                                  height: 16,
                                                  decoration: BoxDecoration(
                                                    color: const Color(
                                                      0xFF4CAF50,
                                                    ),
                                                    shape: BoxShape.circle,
                                                    border: Border.all(
                                                      color: colors
                                                          .surfaceContainerLow,
                                                      width: 2,
                                                    ),
                                                  ),
                                                  child: const Icon(
                                                    Icons.check,
                                                    size: 9,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                        const SizedBox(width: 12),
                                        // Name + subtitle
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                m.isCurrentUser
                                                    ? 'You'
                                                    : m.name,
                                                style: GoogleFonts.manrope(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w600,
                                                  color: isIn
                                                      ? colors.onSurface
                                                      : colors.outlineVariant,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                shareText,
                                                style: GoogleFonts.inter(
                                                  fontSize: 11,
                                                  color: isIn
                                                      ? colors.onSurfaceVariant
                                                      : colors.outlineVariant,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        // Amount or input for non-equal
                                        if (isIn && splitType != 'equal')
                                          SizedBox(
                                            width: 80,
                                            child: TextField(
                                              controller:
                                                  exactControllers[m.id],
                                              keyboardType:
                                                  TextInputType.number,
                                              inputFormatters: [
                                                FilteringTextInputFormatter.allow(
                                                  RegExp(r'[\d.]'),
                                                ),
                                              ],
                                              textAlign: TextAlign.right,
                                              onChanged: (_) => ss(() {}),
                                              style: GoogleFonts.manrope(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w700,
                                                color: colors.primary,
                                              ),
                                              decoration: InputDecoration(
                                                hintText: splitType == 'exact'
                                                    ? '₹'
                                                    : '%',
                                                hintStyle: GoogleFonts.manrope(
                                                  fontSize: 15,
                                                  color: colors.outlineVariant,
                                                ),
                                                border: InputBorder.none,
                                                filled: false,
                                                isDense: true,
                                                contentPadding:
                                                    const EdgeInsets.symmetric(
                                                      vertical: 8,
                                                    ),
                                              ),
                                            ),
                                          )
                                        else if (isIn && amtText.isNotEmpty)
                                          Text(
                                            amtText,
                                            style: GoogleFonts.manrope(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w700,
                                              color: colors.onSurface,
                                            ),
                                          ),
                                        const SizedBox(width: 8),
                                        // Checkbox to include/exclude
                                        GestureDetector(
                                          onTap: () => ss(() {
                                            if (isIn && selected.length > 1) {
                                              selected.remove(m.id);
                                            } else {
                                              selected.add(m.id!);
                                            }
                                          }),
                                          child: Container(
                                            width: 24,
                                            height: 24,
                                            decoration: BoxDecoration(
                                              color: isIn
                                                  ? colors.primary
                                                  : Colors.transparent,
                                              borderRadius:
                                                  BorderRadius.circular(7),
                                              border: isIn
                                                  ? null
                                                  : Border.all(
                                                      color: colors
                                                          .outlineVariant
                                                          .withValues(
                                                            alpha: 0.4,
                                                          ),
                                                      width: 1.5,
                                                    ),
                                            ),
                                            child: isIn
                                                ? const Icon(
                                                    Icons.check,
                                                    size: 15,
                                                    color: Colors.white,
                                                  )
                                                : null,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }),

                                // Live total validation indicator
                                if (splitType != 'equal')
                                  Builder(
                                    builder: (_) {
                                      final amount =
                                          double.tryParse(
                                            amountController.text.trim(),
                                          ) ??
                                          0;
                                      double enteredTotal = 0;
                                      for (final id in selected) {
                                        enteredTotal +=
                                            double.tryParse(
                                              exactControllers[id]?.text ?? '',
                                            ) ??
                                            0;
                                      }

                                      String label;
                                      bool isValid;
                                      if (splitType == 'exact') {
                                        final diff = amount - enteredTotal;
                                        isValid = diff.abs() < 0.01;
                                        label = isValid
                                            ? 'Totals match'
                                            : '₹${diff.abs().toStringAsFixed(2)} ${diff > 0 ? "remaining" : "over"}';
                                      } else if (splitType == 'percentage') {
                                        isValid =
                                            (enteredTotal - 100).abs() < 0.01;
                                        label = isValid
                                            ? '100%'
                                            : '${enteredTotal.toStringAsFixed(1)}% of 100%';
                                      } else {
                                        isValid = true;
                                        label = '';
                                      }

                                      return Padding(
                                        padding: const EdgeInsets.only(top: 8),
                                        child: Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 14,
                                            vertical: 10,
                                          ),
                                          decoration: BoxDecoration(
                                            color: isValid
                                                ? const Color(
                                                    0xFF4CAF50,
                                                  ).withValues(alpha: 0.08)
                                                : const Color(
                                                    0xFFFF6B6B,
                                                  ).withValues(alpha: 0.08),
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(
                                                isValid
                                                    ? Icons.check_circle_rounded
                                                    : Icons
                                                          .warning_amber_rounded,
                                                size: 16,
                                                color: isValid
                                                    ? const Color(0xFF4CAF50)
                                                    : const Color(0xFFFF6B6B),
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                label,
                                                style: GoogleFonts.inter(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                  color: isValid
                                                      ? const Color(0xFF4CAF50)
                                                      : const Color(0xFFFF6B6B),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),

                // STICKY CTA — "Confirm Split"
                Container(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    12,
                    20,
                    MediaQuery.of(ctx).viewInsets.bottom > 0 ? 12 : 28,
                  ),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerLowest,
                  ),
                  child: GestureDetector(
                    onTap: () {
                      final desc = descController.text.trim();
                      final amount =
                          double.tryParse(amountController.text.trim()) ?? 0;
                      if (desc.isEmpty) {
                        showInfoSnackBar('Enter a description');
                        return;
                      }
                      if (amount <= 0) {
                        showInfoSnackBar('Enter an amount');
                        return;
                      }
                      if (paidBy == null || selected.isEmpty) return;

                      if (splitType == 'exact') {
                        double total = 0;
                        bool hasEmpty = false;
                        for (final id in selected) {
                          final val = double.tryParse(
                            exactControllers[id]?.text ?? '',
                          );
                          if (val == null || val <= 0) hasEmpty = true;
                          total += val ?? 0;
                        }
                        if (hasEmpty) {
                          showErrorSnackBar('Enter amount for every member');
                          return;
                        }
                        if ((total - amount).abs() >= 0.01) {
                          showErrorSnackBar(
                            'Amounts must add up to ₹${amount.toStringAsFixed(2)}',
                          );
                          return;
                        }
                      } else if (splitType == 'percentage') {
                        double total = 0;
                        bool hasEmpty = false;
                        for (final id in selected) {
                          final val = double.tryParse(
                            exactControllers[id]?.text ?? '',
                          );
                          if (val == null || val <= 0) hasEmpty = true;
                          total += val ?? 0;
                        }
                        if (hasEmpty) {
                          showErrorSnackBar(
                            'Enter percentage for every member',
                          );
                          return;
                        }
                        if ((total - 100).abs() >= 0.01) {
                          showErrorSnackBar('Must add up to 100%');
                          return;
                        }
                      }

                      Navigator.pop(ctx);

                      List<ExpenseSplit> splits;
                      if (splitType == 'equal') {
                        final pp = amount / selected.length;
                        splits = selected
                            .map(
                              (id) => ExpenseSplit(
                                expenseId: '',
                                memberId: id,
                                amount: pp,
                              ),
                            )
                            .toList();
                      } else if (splitType == 'exact') {
                        splits = selected
                            .map(
                              (id) => ExpenseSplit(
                                expenseId: '',
                                memberId: id,
                                amount:
                                    double.tryParse(
                                      exactControllers[id]?.text ?? '',
                                    ) ??
                                    0,
                              ),
                            )
                            .toList();
                      } else {
                        // percentage
                        splits = selected
                            .map(
                              (id) => ExpenseSplit(
                                expenseId: '',
                                memberId: id,
                                amount:
                                    amount *
                                    (double.tryParse(
                                          exactControllers[id]?.text ?? '',
                                        ) ??
                                        0) /
                                    100,
                              ),
                            )
                            .toList();
                      }

                      if (!mounted) return;
                      final category = noteController.text.trim().isEmpty
                          ? null
                          : noteController.text.trim();
                      final optimisticExpense = SplitExpense(
                        id: 'local_${DateTime.now().millisecondsSinceEpoch}',
                        groupId: widget.groupId,
                        description: desc,
                        amount: amount,
                        paidBy: paidBy!,
                        splitType: splitType,
                        category: category,
                        createdAt: DateTime.now().toIso8601String(),
                      );
                      final optimisticSplits = splits
                          .map(
                            (split) => ExpenseSplit(
                              expenseId: optimisticExpense.id!,
                              memberId: split.memberId,
                              amount: split.amount,
                            ),
                          )
                          .toList();
                      final previousSplits =
                          editing != null && editing.id != null
                          ? List<ExpenseSplit>.from(
                              _splitsMap[editing.id!] ?? const <ExpenseSplit>[],
                            )
                          : const <ExpenseSplit>[];
                      setState(() {
                        if (editing != null) {
                          _expenses.removeWhere((e) => e.id == editing.id);
                          _splitsMap.remove(editing.id);
                        }
                        _expenses.insert(0, optimisticExpense);
                        _splitsMap[optimisticExpense.id!] = optimisticSplits;
                        _recomputeLocalDebts();
                      });
                      showSuccessSnackBar(
                        editing != null ? 'Expense updated' : 'Expense added',
                      );

                      () async {
                        try {
                          final repo = ref.read(splitwiseRepositoryProvider);
                          if (editing != null) {
                            await repo.updateExpense(
                              editing.id!,
                              SplitExpense(
                                groupId: widget.groupId,
                                description: desc,
                                amount: amount,
                                paidBy: paidBy!,
                                splitType: splitType,
                                category: category,
                              ),
                              splits,
                            );
                          } else {
                            await repo.addExpense(
                              SplitExpense(
                                groupId: widget.groupId,
                                description: desc,
                                amount: amount,
                                paidBy: paidBy!,
                                splitType: splitType,
                                category: category,
                              ),
                              splits,
                            );
                          }
                          await _loadLocalSnapshot();
                          if (editing != null) {
                            final changes = <String>[];
                            if (editing.description != desc) {
                              changes.add('${editing.description} → $desc');
                            }
                            if ((editing.amount - amount).abs() > 0.01) {
                              changes.add(
                                '₹${editing.amount.round()} → ₹${amount.round()}',
                              );
                            }
                            if (editing.paidBy != paidBy) {
                              changes.add('Payer changed');
                            }
                            if (editing.splitType != splitType) {
                              changes.add(
                                'Split: ${editing.splitType} → $splitType',
                              );
                            }
                            repo.logActivity(
                              groupId: widget.groupId,
                              action: 'edited',
                              description: desc,
                              details: changes.isNotEmpty
                                  ? changes.join(' · ')
                                  : null,
                            );
                          } else {
                            repo.logActivity(
                              groupId: widget.groupId,
                              action: 'added',
                              description: desc,
                              details:
                                  '₹${amount.round()} paid by ${_memberName(paidBy!)}',
                            );
                          }
                        } catch (e) {
                          if (mounted) {
                            setState(() {
                              _expenses.removeWhere(
                                (ex) => ex.id == optimisticExpense.id,
                              );
                              _splitsMap.remove(optimisticExpense.id);
                              if (editing != null) {
                                _expenses.insert(0, editing);
                                if (editing.id != null) {
                                  _splitsMap[editing.id!] = previousSplits;
                                }
                              }
                              _recomputeLocalDebts();
                            });
                            showErrorSnackBar(
                              'Sync failed. Check your connection.',
                            );
                          }
                        }
                      }();
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        gradient: LinearGradient(
                          colors: [colors.primary, colors.tertiary],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: colors.primary.withValues(alpha: 0.25),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          editing != null ? 'Update Split' : 'Confirm Split',
                          style: GoogleFonts.manrope(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _splitToggleChip(
    String value,
    String label,
    String current,
    ColorScheme colors,
    ValueChanged<String> onTap,
  ) {
    final isSel = current == value;
    return GestureDetector(
      onTap: () => onTap(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSel ? colors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: isSel ? Colors.white : colors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Settle up
  // ---------------------------------------------------------------------------
  void _showSettleUp(
    DebtEntry debt,
    ColorScheme colors, {
    bool isRecordPayment = false,
  }) {
    String method = 'cash';
    final amtController = TextEditingController(
      text: debt.amount.toStringAsFixed(0),
    );
    bool isFullPayment = true;
    final payerName = _memberName(debt.fromMemberId);
    final payeeName = _memberName(debt.toMemberId);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, ss) => SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.88,
            ),
            child: PremiumSheetContainer(
              variant: PremiumSurfaceVariant.split,
              padding: const EdgeInsets.only(bottom: 8),
              child: SingleChildScrollView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(ctx).viewInsets.bottom + 8,
                ),
                child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle bar
                const SizedBox(height: 12),
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colors.outlineVariant.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Mode label
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: isRecordPayment
                        ? colors.secondary.withValues(alpha: 0.1)
                        : colors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    isRecordPayment ? 'RECORD PAYMENT' : 'SETTLE UP',
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
                      color: isRecordPayment
                          ? colors.secondary
                          : colors.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // 1. HERO SECTION — payer → payee flow
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Row(
                    children: [
                      // Payer
                      Expanded(
                        child: Column(
                          children: [
                            CircleAvatar(
                              radius: 28,
                              backgroundColor: const Color(
                                0xFFFF6B6B,
                              ).withValues(alpha: 0.12),
                              child: Text(
                                (payerName.isNotEmpty ? payerName[0] : '?')
                                    .toUpperCase(),
                                style: GoogleFonts.manrope(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFFFF6B6B),
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              payerName,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: colors.onSurface,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                            ),
                            Text(
                              'pays',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Arrow
                      Padding(
                        padding: const EdgeInsets.only(bottom: 20),
                        child: Icon(
                          Icons.arrow_forward_rounded,
                          size: 22,
                          color: colors.outlineVariant,
                        ),
                      ),
                      // Payee
                      Expanded(
                        child: Column(
                          children: [
                            CircleAvatar(
                              radius: 28,
                              backgroundColor: colors.primary.withValues(
                                alpha: 0.12,
                              ),
                              child: Text(
                                (payeeName.isNotEmpty ? payeeName[0] : '?')
                                    .toUpperCase(),
                                style: GoogleFonts.manrope(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                  color: colors.primary,
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              payeeName,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: colors.onSurface,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                            ),
                            Text(
                              'receives',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // 2. AMOUNT SECTION
                Text(
                  'Amount',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                if (isFullPayment)
                  Text(
                    '₹${NumberFormat('#,##,###', 'en_IN').format(debt.amount.round())}',
                    style: GoogleFonts.manrope(
                      fontSize: 42,
                      fontWeight: FontWeight.w800,
                      color: colors.onSurface,
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 60),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '₹',
                          style: GoogleFonts.manrope(
                            fontSize: 32,
                            fontWeight: FontWeight.w600,
                            color: colors.primary.withValues(alpha: 0.4),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: TextField(
                            controller: amtController,
                            autofocus: true,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'[\d.]'),
                              ),
                            ],
                            textAlign: TextAlign.center,
                            style: GoogleFonts.manrope(
                              fontSize: 42,
                              fontWeight: FontWeight.w800,
                              color: colors.onSurface,
                            ),
                            decoration: InputDecoration(
                              hintText: '0',
                              hintStyle: GoogleFonts.manrope(
                                fontSize: 42,
                                fontWeight: FontWeight.w800,
                                color: colors.outlineVariant,
                              ),
                              border: InputBorder.none,
                              filled: false,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 20),

                // 3. FULL / PARTIAL TOGGLE
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () => ss(() {
                              isFullPayment = true;
                              amtController.text = debt.amount.toStringAsFixed(
                                0,
                              );
                            }),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: isFullPayment
                                    ? colors.primary
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(13),
                              ),
                              child: Center(
                                child: Text(
                                  'Full Payment',
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: isFullPayment
                                        ? Colors.white
                                        : colors.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: GestureDetector(
                            onTap: () => ss(() {
                              isFullPayment = false;
                              amtController.clear();
                            }),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: !isFullPayment
                                    ? colors.primary
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(13),
                              ),
                              child: Center(
                                child: Text(
                                  'Partial',
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: !isFullPayment
                                        ? Colors.white
                                        : colors.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // 4. SELECT PAYMENT METHOD
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'SELECT PAYMENT METHOD',
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: colors.onSurfaceVariant,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                ...[
                  {
                    'key': 'upi',
                    'icon': Icons.qr_code,
                    'title': 'UPI Transfer',
                    'subtitle': 'Pay via any UPI app',
                  },
                  {
                    'key': 'bank',
                    'icon': Icons.account_balance,
                    'title': 'Bank Transfer',
                    'subtitle': 'NEFT / IMPS / RTGS',
                  },
                  {
                    'key': 'cash',
                    'icon': Icons.money,
                    'title': 'Cash',
                    'subtitle': 'Paid in cash',
                  },
                ].map((m) {
                  final isSel = method == m['key'];
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
                    child: GestureDetector(
                      onTap: () => ss(() => method = m['key'] as String),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isSel
                              ? colors.surfaceContainerLowest
                              : colors.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: isSel
                                    ? colors.primary.withValues(alpha: 0.1)
                                    : colors.outlineVariant.withValues(
                                        alpha: 0.1,
                                      ),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Icon(
                                m['icon'] as IconData,
                                size: 22,
                                color: isSel
                                    ? colors.primary
                                    : colors.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    m['title'] as String,
                                    style: GoogleFonts.manrope(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: colors.onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    m['subtitle'] as String,
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      color: colors.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isSel
                                    ? colors.primary
                                    : Colors.transparent,
                                border: isSel
                                    ? null
                                    : Border.all(
                                        color: colors.outlineVariant.withValues(
                                          alpha: 0.4,
                                        ),
                                        width: 1.5,
                                      ),
                              ),
                              child: isSel
                                  ? const Icon(
                                      Icons.check,
                                      size: 14,
                                      color: Colors.white,
                                    )
                                  : null,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 8),

                // 5. INFO TEXT
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.auto_awesome,
                        size: 16,
                        color: colors.primary.withValues(alpha: 0.5),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          isRecordPayment
                              ? 'Record a payment made outside the app. This updates the group balance.'
                              : 'This will update the balance between $payerName and $payeeName.',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: colors.onSurfaceVariant,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // 6. CONFIRM SETTLEMENT CTA
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                  child: GestureDetector(
                    onTap: () async {
                      double settleAmount;
                      if (isFullPayment) {
                        settleAmount = debt.amount;
                      } else {
                        final parsed = double.tryParse(amtController.text);
                        if (parsed == null || parsed <= 0) {
                          showErrorSnackBar('Enter a valid amount');
                          return;
                        }
                        if (parsed > debt.amount + 0.01) {
                          showErrorSnackBar(
                            'Cannot settle more than owed (₹${debt.amount.toStringAsFixed(0)})',
                          );
                          return;
                        }
                        settleAmount = parsed;
                      }
                      if (settleAmount <= 0) return;
                      Navigator.pop(ctx);
                      if (!mounted) return;

                      // Optimistic: remove debt + add to settlement history instantly
                      final optimisticSettlement = Settlement(
                        id: 'local_${DateTime.now().millisecondsSinceEpoch}',
                        groupId: widget.groupId,
                        fromMember: debt.fromMemberId,
                        toMember: debt.toMemberId,
                        amount: settleAmount,
                        method: method,
                        createdAt: DateTime.now().toIso8601String(),
                      );
                      setState(() {
                        _settlements.insert(0, optimisticSettlement);
                        _recomputeLocalDebts();
                      });
                      showSuccessSnackBar(
                        isRecordPayment
                            ? 'Payment of ₹${settleAmount.round()} recorded'
                            : 'Settled ₹${settleAmount.round()}',
                      );

                      // Sync in background — no _load() on success
                      () async {
                        try {
                          final repo = ref.read(splitwiseRepositoryProvider);
                          await repo.addSettlement(
                            Settlement(
                              groupId: widget.groupId,
                              fromMember: debt.fromMemberId,
                              toMember: debt.toMemberId,
                              amount: settleAmount,
                              method: method,
                            ),
                          );
                          await _loadLocalSnapshot();
                          repo.logActivity(
                            groupId: widget.groupId,
                            action: 'settled',
                            description:
                                '${_memberName(debt.fromMemberId)} → ${_memberName(debt.toMemberId)}',
                            details:
                                '₹${settleAmount.round()} via ${method.toUpperCase()}',
                          );
                        } catch (e) {
                          if (mounted) {
                            setState(() {
                              _settlements.remove(optimisticSettlement);
                              _recomputeLocalDebts();
                            });
                            showErrorSnackBar(
                              'Sync failed. Check your connection.',
                            );
                          }
                        }
                      }();
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        gradient: const LinearGradient(
                          colors: [Color(0xFF0F766E), Color(0xFF22A06B)],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(
                              0xFF0F766E,
                            ).withValues(alpha: 0.25),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          isRecordPayment
                              ? 'Record Payment'
                              : 'Confirm Settlement',
                          style: GoogleFonts.manrope(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Confirm undo settlement
  // ---------------------------------------------------------------------------
  void _confirmUndoSettlement(Settlement s, ColorScheme colors) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Undo Settlement',
          style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
        ),
        content: Text(
          'Undo ₹${s.amount.round()} payment from ${_memberName(s.fromMember)} to ${_memberName(s.toMember)}? This will restore the original debt.',
          style: GoogleFonts.inter(color: colors.onSurfaceVariant, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: GoogleFonts.inter(fontWeight: FontWeight.w600),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final removed = s;
              setState(() {
                _settlements.removeWhere((st) => st.id == s.id);
                _recomputeLocalDebts();
              });
              showSuccessSnackBar('Settlement undone');
              try {
                final repo = ref.read(splitwiseRepositoryProvider);
                await repo.deleteSettlement(s.id!, groupId: widget.groupId);
                await _loadLocalSnapshot();
                repo.logActivity(
                  groupId: widget.groupId,
                  action: 'deleted',
                  description:
                      'Settlement: ${_memberName(s.fromMember)} → ${_memberName(s.toMember)}',
                  details: '₹${s.amount.round()} reversed',
                );
              } catch (e) {
                if (mounted) {
                  setState(() {
                    _settlements.add(removed);
                    _recomputeLocalDebts();
                  });
                  showErrorSnackBar('Could not undo. Check your connection.');
                }
              }
            },
            child: Text(
              'Undo',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w600,
                color: colors.error,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Confirm remove member
  // ---------------------------------------------------------------------------
  void _confirmRemoveMember(GroupMember m, ColorScheme colors) {
    // Check if member has pending balance
    final hasBalance = _debts.any(
      (d) => d.fromMemberId == m.id || d.toMemberId == m.id,
    );

    if (hasBalance) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            'Cannot Remove',
            style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
          ),
          content: Text(
            '${m.name} has pending balances in this group. Settle all debts before removing.',
            style: GoogleFonts.inter(
              color: colors.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                'OK',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w600,
                  color: colors.primary,
                ),
              ),
            ),
          ],
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Remove Member',
          style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
        ),
        content: Text(
          'Remove ${m.name} from this group?',
          style: GoogleFonts.inter(color: colors.onSurfaceVariant),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: GoogleFonts.inter(fontWeight: FontWeight.w600),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              // Optimistic: remove from UI instantly
              final removedMember = m;
              setState(
                () => _members.removeWhere((member) => member.id == m.id),
              );
              showSuccessSnackBar('${m.name} removed');
              // Sync in background — don't _load() on success, optimistic state is correct
              try {
                await ref.read(splitwiseRepositoryProvider).removeMember(m.id!);
              } catch (e) {
                // Rollback — re-add and reload
                setState(() => _members.add(removedMember));
                debugPrint('Remove member failed: $e');
                showErrorSnackBar('Could not remove member. Try again.');
              }
            },
            child: Text(
              'Remove',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w600,
                color: colors.error,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Show members & group settings bottom sheet (gear icon)
  // ---------------------------------------------------------------------------
  void _showGroupSettings(ColorScheme colors) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => PremiumSheetContainer(
        variant: PremiumSurfaceVariant.split,
        maxHeight: MediaQuery.of(ctx).size.height * 0.7,
        padding: EdgeInsets.zero,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
              child: Column(
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: colors.outlineVariant.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Text(
                        'Members',
                        style: GoogleFonts.manrope(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: () {
                          Navigator.pop(ctx);
                          _showAddMember(colors);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [colors.primary, colors.primaryContainer],
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.person_add,
                                size: 16,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Add',
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                itemCount: _members.length,
                itemBuilder: (_, i) {
                  final m = _members[i];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: colors.surface,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Row(
                        children: [
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              CircleAvatar(
                                radius: 22,
                                backgroundColor: m.userId != null
                                    ? colors.primary.withValues(alpha: 0.15)
                                    : colors.outlineVariant.withValues(
                                        alpha: 0.15,
                                      ),
                                child: Text(
                                  (m.name.isNotEmpty ? m.name[0] : '?')
                                      .toUpperCase(),
                                  style: GoogleFonts.manrope(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: m.userId != null
                                        ? colors.primary
                                        : colors.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              if (m.userId != null)
                                Positioned(
                                  right: -2,
                                  bottom: -2,
                                  child: Container(
                                    width: 16,
                                    height: 16,
                                    decoration: BoxDecoration(
                                      color: colors.secondary,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: colors.surfaceContainerLowest,
                                        width: 2,
                                      ),
                                    ),
                                    child: const Icon(
                                      Icons.check,
                                      size: 9,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        m.name,
                                        style: GoogleFonts.manrope(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (m.isCurrentUser) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: colors.secondary.withValues(
                                            alpha: 0.1,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                        ),
                                        child: Text(
                                          'You',
                                          style: GoogleFonts.inter(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                            color: colors.secondary,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                if (m.phone != null)
                                  Row(
                                    children: [
                                      Text(
                                        m.phone!,
                                        style: GoogleFonts.inter(
                                          fontSize: 12,
                                          color: colors.onSurfaceVariant,
                                        ),
                                      ),
                                      if (m.userId != null) ...[
                                        const SizedBox(width: 4),
                                        Text(
                                          '· On Fluid Ledger',
                                          style: GoogleFonts.inter(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                            color: colors.secondary,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                              ],
                            ),
                          ),
                          if (!m.isCurrentUser)
                            IconButton(
                              icon: Icon(
                                Icons.remove_circle_outline,
                                color: colors.error.withValues(alpha: 0.6),
                                size: 20,
                              ),
                              onPressed: () {
                                Navigator.pop(ctx);
                                _confirmRemoveMember(m, colors);
                              },
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Show insights / summary bottom sheet ("View Insights" link)
  // ---------------------------------------------------------------------------
  void _showInsightsSheet(ColorScheme colors, NumberFormat fmt) {
    // Per-member spending (what they paid)
    final paidByMap = <String, double>{};
    for (final e in _expenses) {
      paidByMap[e.paidBy] = (paidByMap[e.paidBy] ?? 0) + e.amount;
    }
    final spenders = paidByMap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topSpender = spenders.isNotEmpty ? spenders.first : null;

    // Category breakdown
    final catMap = <String, double>{};
    for (final e in _expenses) {
      final cat = e.category?.isNotEmpty == true ? e.category! : 'General';
      catMap[cat] = (catMap[cat] ?? 0) + e.amount;
    }
    final catSorted = catMap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * 0.85,
        ),
        decoration: BoxDecoration(
          color: colors.surfaceContainerLowest,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
              child: Column(
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: colors.outlineVariant.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Group Insights',
                    style: GoogleFonts.manrope(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Total card
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [colors.primary, colors.primaryContainer],
                        ),
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'GROUP SUMMARY',
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Colors.white.withValues(alpha: 0.7),
                              letterSpacing: 1.5,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '₹${fmt.format(_totalExpenses.round())}',
                            style: GoogleFonts.manrope(
                              fontSize: 34,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            '${_expenses.length} expenses · ${_members.length} members',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: Colors.white.withValues(alpha: 0.6),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Top spender
                    if (topSpender != null) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF3E0),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFFFFB74D,
                                ).withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Center(
                                child: Text(
                                  '🏆',
                                  style: TextStyle(fontSize: 22),
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Top Spender',
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: colors.onSurfaceVariant,
                                    ),
                                  ),
                                  Text(
                                    _memberName(topSpender.key),
                                    style: GoogleFonts.manrope(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              '₹${fmt.format(topSpender.value.round())}',
                              style: GoogleFonts.manrope(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: colors.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],

                    // Per-member breakdown
                    Text(
                      'WHO PAID WHAT',
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: colors.primary,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...spenders.map((entry) {
                      final pct = _totalExpenses > 0
                          ? (entry.value / _totalExpenses * 100).round()
                          : 0;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: colors.surface,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 18,
                                backgroundColor: colors.primary.withValues(
                                  alpha: 0.1,
                                ),
                                child: Text(
                                  _memberName(entry.key)[0],
                                  style: GoogleFonts.manrope(
                                    fontWeight: FontWeight.w700,
                                    color: colors.primary,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _memberName(entry.key),
                                      style: GoogleFonts.manrope(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(3),
                                      child: LinearProgressIndicator(
                                        value: (pct / 100).clamp(0.0, 1.0),
                                        backgroundColor: colors.outlineVariant
                                            .withValues(alpha: 0.1),
                                        valueColor: AlwaysStoppedAnimation(
                                          colors.primary,
                                        ),
                                        minHeight: 4,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    '₹${fmt.format(entry.value.round())}',
                                    style: GoogleFonts.manrope(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    '$pct%',
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      color: colors.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    }),

                    // Net balances
                    if (_debts.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      Text(
                        'NET BALANCES',
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: colors.primary,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ..._debts.map(
                        (d) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            decoration: BoxDecoration(
                              color: colors.surface,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Row(
                              children: [
                                Text(
                                  _memberName(d.fromMemberId),
                                  style: GoogleFonts.manrope(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFFFF6B6B),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Icon(
                                  Icons.arrow_forward,
                                  size: 14,
                                  color: colors.outlineVariant,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _memberName(d.toMemberId),
                                  style: GoogleFonts.manrope(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: colors.secondary,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  '₹${fmt.format(d.amount.round())}',
                                  style: GoogleFonts.manrope(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],

                    // Categories
                    if (catSorted.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      Text(
                        'BY CATEGORY',
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: colors.primary,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ...catSorted.map(
                        (c) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  c.key,
                                  style: GoogleFonts.inter(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              Text(
                                '₹${fmt.format(c.value.round())}',
                                style: GoogleFonts.manrope(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],

                    // Activity log
                    if (_activity.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      Text(
                        'ACTIVITY',
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: colors.primary,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ..._activity.take(20).map((a) {
                        final dt = DateTime.tryParse(a.createdAt ?? '');
                        final actionIcons = {
                          'added': Icons.add_circle_outline,
                          'edited': Icons.edit_outlined,
                          'deleted': Icons.delete_outline,
                          'settled': Icons.check_circle_outline,
                        };
                        final actionColors = {
                          'added': colors.secondary,
                          'edited': colors.primary,
                          'deleted': const Color(0xFFFF6B6B),
                          'settled': const Color(0xFF00897B),
                        };
                        final color =
                            actionColors[a.action] ?? colors.onSurfaceVariant;
                        final actorName =
                            _members
                                .where((m) => m.userId == a.userId)
                                .map((m) => m.name)
                                .firstOrNull ??
                            'Someone';

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: colors.surface,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: color.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    actionIcons[a.action] ?? Icons.info_outline,
                                    size: 16,
                                    color: color,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      RichText(
                                        text: TextSpan(
                                          style: GoogleFonts.inter(
                                            fontSize: 13,
                                            color: colors.onSurface,
                                          ),
                                          children: [
                                            TextSpan(
                                              text: actorName,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                            TextSpan(text: ' ${a.action} '),
                                            TextSpan(
                                              text: a.description,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (a.details != null) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          a.details!,
                                          style: GoogleFonts.inter(
                                            fontSize: 11,
                                            color: colors.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                      if (dt != null) ...[
                                        const SizedBox(height: 3),
                                        Text(
                                          DateFormat(
                                            'd MMM, h:mm a',
                                          ).format(dt),
                                          style: GoogleFonts.inter(
                                            fontSize: 10,
                                            color: colors.outline,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Build — single scrollable page (no tabs)
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    ref.watch(splitwiseRealtimeBootstrapProvider);
    ref.listen<AsyncValue<SplitwiseInvalidation>>(
      splitwiseRealtimeEventsProvider,
      (_, next) {
        next.whenData((event) {
          if (!mounted) return;
          if (event.groupsChanged || event.groupIds.contains(widget.groupId)) {
            _load();
          }
        });
      },
    );
    final colors = Theme.of(context).colorScheme;
    final fmt = NumberFormat('#,##,###', 'en_IN');

    return Scaffold(
      backgroundColor: colors.surface,
      body: SafeArea(
        bottom: false,
        child: _loading ? const GroupDetailSkeleton() : _buildBody(colors, fmt),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Main body — single scrollable page
  // ---------------------------------------------------------------------------
  Widget _buildBody(ColorScheme colors, NumberFormat fmt) {
    // Empty state: not enough members
    if (_members.length < 2) {
      return _buildEmptyState(colors, needsMembers: true);
    }

    // Empty state: no expenses yet
    if (_expenses.isEmpty) {
      return _buildEmptyState(colors, needsMembers: false);
    }

    // Compute current user balance for hero card
    final me = _members.where((m) => m.isCurrentUser).firstOrNull;
    double myNetCredit = 0;
    double myNetDebt = 0;
    if (me != null) {
      myNetCredit = _debts
          .where((d) => d.toMemberId == me.id)
          .fold(0.0, (s, d) => s + d.amount);
      myNetDebt = _debts
          .where((d) => d.fromMemberId == me.id)
          .fold(0.0, (s, d) => s + d.amount);
    }
    final myBalance = myNetCredit - myNetDebt;
    final balanceLabel = myBalance >= 0 ? 'You are owed' : 'You owe';

    return RefreshIndicator(
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(colors),
            const SizedBox(height: 20),
            _buildHeroCard(colors, fmt, myBalance, balanceLabel),
            const SizedBox(height: 18),
            _buildWorkspaceBoard(colors),
            const SizedBox(height: 24),

            if (_debts.isNotEmpty) ...[
              _buildPendingDebtsSection(colors, fmt),
              const SizedBox(height: 24),
            ],

            _buildFluidInsightsCard(colors, fmt),
            const SizedBox(height: 24),

            _buildSectionHeader(
              colors,
              eyebrow: 'LEDGER',
              title: 'Recent Activity',
              actionLabel: 'View Insights',
              onAction: () => _showInsightsSheet(colors, fmt),
            ),
            const SizedBox(height: 14),
            _buildExpensesList(colors, fmt),

            if (_settlements.isNotEmpty) ...[
              const SizedBox(height: 24),
              _buildSettlementHistory(colors, fmt),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildWorkspaceBoard(ColorScheme colors) {
    return PremiumSurfaceCard(
      variant: PremiumSurfaceVariant.split,
      radius: 30,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'WORKSPACE',
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: colors.primary,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Manage people, expenses, and settlements.',
            style: GoogleFonts.manrope(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: colors.onSurface,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          _buildMembersRow(colors),
          const SizedBox(height: 12),
          _buildCtaRow(colors),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Empty state
  // ---------------------------------------------------------------------------
  Widget _buildEmptyState(ColorScheme colors, {required bool needsMembers}) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          child: _buildHeader(colors),
        ),
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(40),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      color: colors.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: Icon(
                      needsMembers
                          ? Icons.person_add_outlined
                          : Icons.receipt_long_outlined,
                      size: 44,
                      color: colors.primary,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    needsMembers ? 'Add Members First' : 'No Expenses Yet',
                    style: GoogleFonts.manrope(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: colors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    needsMembers
                        ? 'Add at least 2 members to start splitting expenses'
                        : 'Add your first expense to start splitting with the group.',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: colors.onSurfaceVariant,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 28),
                  GestureDetector(
                    onTap: needsMembers
                        ? () => _showAddMember(colors)
                        : () => _showAddExpense(colors),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 16,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        gradient: LinearGradient(
                          colors: [colors.primary, colors.primaryContainer],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: colors.primary.withValues(alpha: 0.25),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            needsMembers ? Icons.person_add : Icons.add,
                            size: 20,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            needsMembers ? 'Add Members' : 'Add Expense',
                            style: GoogleFonts.manrope(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Hero balance card — gradient blue
  // ---------------------------------------------------------------------------
  Widget _buildHeroCard(
    ColorScheme colors,
    NumberFormat fmt,
    double myBalance,
    String balanceLabel,
  ) {
    final accent = myBalance >= 0
        ? const Color(0xFF63E6BE)
        : const Color(0xFFFFB38A);
    final progress = _totalExpenses <= 0
        ? 0.0
        : (myBalance.abs() / _totalExpenses).clamp(0.0, 1.0);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: HeroScreenThemes.splitGradient,
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF142A6E).withValues(alpha: 0.28),
            blurRadius: 28,
            offset: const Offset(0, 14),
            spreadRadius: -6,
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(child: HeroScreenThemes.splitWatermark()),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'CURRENT BALANCE',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.white.withValues(alpha: 0.62),
                      letterSpacing: 1.5,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      balanceLabel.toUpperCase(),
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: accent,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '₹${fmt.format(myBalance.abs().round())}',
                style: GoogleFonts.manrope(
                  fontSize: 38,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                myBalance.abs() <= 0.5 ? 'All balances settled' : balanceLabel,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.white.withValues(alpha: 0.74),
                ),
              ),
              if (myBalance > 0.5) ...[
                const SizedBox(height: 4),
                Text(
                  _owedBreakdownText(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withValues(alpha: 0.8),
                    height: 1.3,
                  ),
                ),
              ],
              const SizedBox(height: 18),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _buildHeroMetric(
                      label: 'Members',
                      value: '${_members.length}',
                      icon: Icons.people_alt_outlined,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildHeroMetric(
                      label: 'Expenses',
                      value: '${_expenses.length}',
                      icon: Icons.receipt_long_outlined,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildHeroMetric(
                      label: 'Total settled',
                      value:
                          '₹${fmt.format(_settlements.fold<double>(0.0, (sum, settlement) => sum + settlement.amount).round())}',
                      icon: Icons.task_alt_outlined,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  backgroundColor: Colors.white.withValues(alpha: 0.12),
                  valueColor: AlwaysStoppedAnimation<Color>(accent),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Text(
                    '${_members.length} members',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.58),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    width: 3,
                    height: 3,
                    decoration: const BoxDecoration(
                      color: Colors.white38,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '₹${fmt.format(_totalExpenses.round())} total',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.58),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeroMetric({
    required String label,
    required String value,
    required IconData icon,
  }) {
    return PremiumMetricBox(
      label: label,
      value: value,
      labelColor: Colors.white.withValues(alpha: 0.62),
      valueColor: Colors.white,
      backgroundColor: Colors.white.withValues(alpha: 0.1),
      icon: icon,
      valueFontSize: 17,
      labelFontSize: 10,
      minHeight: 90,
      labelFirst: false,
    );
  }

  Widget _buildSectionHeader(
    ColorScheme colors, {
    required String eyebrow,
    required String title,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                eyebrow,
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: colors.primary,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                title,
                style: GoogleFonts.manrope(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: colors.onSurface,
                ),
              ),
            ],
          ),
        ),
        if (actionLabel != null && onAction != null)
          GestureDetector(
            onTap: onAction,
            child: Text(
              actionLabel,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: colors.primary,
              ),
            ),
          ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Pending debts section
  // ---------------------------------------------------------------------------
  Widget _buildPendingDebtsSection(ColorScheme colors, NumberFormat fmt) {
    final totalPending = _debts.fold<double>(0, (sum, d) => sum + d.amount);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          colors,
          eyebrow: 'PENDING',
          title: 'Outstanding Balances',
        ),
        const SizedBox(height: 14),
        PremiumSurfaceCard(
          variant: PremiumSurfaceVariant.split,
          radius: 20,
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Settlement Assistant',
                style: GoogleFonts.manrope(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: colors.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${_debts.length} pending settlement${_debts.length == 1 ? '' : 's'} · ₹${fmt.format(totalPending.round())} to settle',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        final debt = _primaryDebtForCurrentUser();
                        if (debt != null) {
                          _showSettleUp(debt, colors);
                        }
                      },
                      child: const Text('Request Payment'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: _settlingAllDebts
                          ? null
                          : () => _settleAllDebts(colors),
                      child: Text(
                        _settlingAllDebts ? 'Settling...' : 'Settle All',
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        ..._debts.asMap().entries.map((entry) {
          final index = entry.key;
          final d = entry.value;
          // Find how long this debt has been pending
          String pendingLabel = '';
          final relevantDates = _expenses
              .where(
                (e) => e.paidBy == d.toMemberId || e.paidBy == d.fromMemberId,
              )
              .map((e) => DateTime.tryParse(e.createdAt ?? ''))
              .whereType<DateTime>()
              .toList();
          if (relevantDates.isNotEmpty) {
            relevantDates.sort();
            final oldest = relevantDates.first;
            final days = DateTime.now().difference(oldest).inDays;
            if (days == 0) {
              pendingLabel = 'Since today';
            } else if (days == 1) {
              pendingLabel = 'Since yesterday';
            } else if (days < 30) {
              pendingLabel = 'Pending $days days';
            } else {
              pendingLabel =
                  'Pending ${(days / 30).floor()} month${(days / 30).floor() > 1 ? 's' : ''}';
            }
          }
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: PremiumSurfaceCard(
              variant: PremiumSurfaceVariant.negative,
              radius: 30,
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _memberName(d.fromMemberId),
                          style: GoogleFonts.manrope(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFFFF6B6B),
                          ),
                        ),
                        Row(
                          children: [
                            const Icon(
                              Icons.arrow_forward,
                              size: 14,
                              color: Colors.grey,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'owes ${_memberName(d.toMemberId)}',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                        if (pendingLabel.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            pendingLabel,
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: colors.outline,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: colors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '${index + 1}/${_debts.length}',
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: colors.primary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '₹${fmt.format(d.amount.round())}',
                        style: GoogleFonts.manrope(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF142A6E),
                        ),
                      ),
                      const SizedBox(height: 8),
                      GestureDetector(
                        onTap: () =>
                            _showSettleUp(d, colors, isRecordPayment: true),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.85),
                            border: Border.all(color: const Color(0xFFF1BEAE)),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            'Record',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFFEF6C57),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Expense cards list
  // ---------------------------------------------------------------------------
  Widget _buildExpensesList(ColorScheme colors, NumberFormat fmt) {
    // Expense icon/color mapping by category or description
    final expenseIcons = <String, IconData>{
      'food': Icons.restaurant_outlined,
      'dinner': Icons.restaurant_outlined,
      'lunch': Icons.restaurant_outlined,
      'breakfast': Icons.restaurant_outlined,
      'groceries': Icons.shopping_cart_outlined,
      'shopping': Icons.shopping_bag_outlined,
      'uber': Icons.directions_car_outlined,
      'cab': Icons.directions_car_outlined,
      'taxi': Icons.directions_car_outlined,
      'travel': Icons.flight_outlined,
      'rent': Icons.home_outlined,
      'bills': Icons.receipt_long_outlined,
      'electricity': Icons.bolt_outlined,
      'wifi': Icons.wifi_outlined,
      'internet': Icons.wifi_outlined,
      'movie': Icons.movie_outlined,
      'entertainment': Icons.movie_outlined,
      'drinks': Icons.local_bar_outlined,
      'coffee': Icons.coffee_outlined,
      'medical': Icons.medical_services_outlined,
      'general': Icons.receipt_outlined,
    };
    final expenseColors = <String, Color>{
      'food': const Color(0xFFFF7043),
      'dinner': const Color(0xFFFF7043),
      'lunch': const Color(0xFFFF7043),
      'breakfast': const Color(0xFFFF7043),
      'groceries': const Color(0xFF66BB6A),
      'shopping': const Color(0xFFAB47BC),
      'uber': const Color(0xFF42A5F5),
      'cab': const Color(0xFF42A5F5),
      'taxi': const Color(0xFF42A5F5),
      'travel': const Color(0xFF26C6DA),
      'rent': const Color(0xFF8D6E63),
      'bills': const Color(0xFFFFCA28),
      'entertainment': const Color(0xFFEC407A),
      'drinks': const Color(0xFFEF5350),
      'coffee': const Color(0xFF8D6E63),
      'medical': const Color(0xFF26A69A),
      'general': const Color(0xFF78909C),
    };

    IconData iconFor(SplitExpense e) {
      final cat = (e.category ?? '').toLowerCase();
      final desc = e.description.toLowerCase();
      for (final key in expenseIcons.keys) {
        if (cat.contains(key) || desc.contains(key)) return expenseIcons[key]!;
      }
      return Icons.receipt_outlined;
    }

    Color colorFor(SplitExpense e) {
      final cat = (e.category ?? '').toLowerCase();
      final desc = e.description.toLowerCase();
      for (final key in expenseColors.keys) {
        if (cat.contains(key) || desc.contains(key)) return expenseColors[key]!;
      }
      return const Color(0xFF78909C);
    }

    final me = _members.where((m) => m.isCurrentUser).firstOrNull;

    final items = _expenses.asMap().entries.map((entry) {
      final i = entry.key;
      final e = entry.value;
      final dt = DateTime.tryParse(e.createdAt ?? '');
      final isLongPressed = _longPressedExpenseId == e.id;
      final iconColor = colorFor(e);

      // Compute YOUR SHARE
      String yourShareText = '';
      if (me != null && e.id != null && _splitsMap.containsKey(e.id)) {
        final mySplit = _splitsMap[e.id]!
            .where((s) => s.memberId == me.id)
            .firstOrNull;
        if (mySplit != null) {
          yourShareText = '₹${fmt.format(mySplit.amount.round())}';
        }
      } else if (me != null && _members.isNotEmpty) {
        yourShareText = '₹${fmt.format((e.amount / _members.length).round())}';
      }

      return GestureDetector(
        key: ValueKey(e.id),
        onTap: () => _showAddExpense(colors, editing: e),
        onLongPressStart: (_) => setState(() => _longPressedExpenseId = e.id),
        onLongPress: () {
          HapticFeedback.mediumImpact();
          showDialog(
            context: context,
            builder: (ctx) => PremiumDialog(
              title: 'Delete Expense',
              body: 'Delete "${e.description}"?',
              primaryLabel: 'Delete',
              destructive: true,
              onSecondary: () {
                Navigator.pop(ctx);
                setState(() => _longPressedExpenseId = null);
              },
              onPrimary: () async {
                Navigator.pop(ctx);
                final removedExpense = e;
                final removedSplits =
                    _splitsMap[e.id] ?? const <ExpenseSplit>[];
                setState(() {
                  _expenses.removeWhere((ex) => ex.id == e.id);
                  _splitsMap.remove(e.id);
                  _recomputeLocalDebts();
                  _longPressedExpenseId = null;
                });
                showSuccessSnackBar('Expense deleted');
                try {
                  final repo = ref.read(splitwiseRepositoryProvider);
                  await repo.deleteExpense(e.id!, groupId: widget.groupId);
                  await _loadLocalSnapshot();
                  await repo.logActivity(
                    groupId: widget.groupId,
                    action: 'deleted',
                    description: e.description,
                    details: '₹${e.amount.round()}',
                  );
                } catch (err) {
                  setState(() {
                    _expenses.insert(0, removedExpense);
                    if (e.id != null) {
                      _splitsMap[e.id!] = removedSplits;
                    }
                    _recomputeLocalDebts();
                  });
                  debugPrint('Delete expense failed: $err');
                  showErrorSnackBar('Could not delete. Check your connection.');
                }
              },
            ),
          );
        },
        onLongPressEnd: (_) {
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted && _longPressedExpenseId == e.id) {
              setState(() => _longPressedExpenseId = null);
            }
          });
        },
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          decoration: BoxDecoration(
            color: isLongPressed
                ? colors.error.withValues(alpha: 0.05)
                : Colors.white.withValues(alpha: i.isEven ? 0.42 : 0.18),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(iconFor(e), size: 22, color: iconColor),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      e.description,
                      style: GoogleFonts.manrope(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: colors.onSurface,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Text(
                          'Paid by ${_memberName(e.paidBy)}',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                        if (e.splitType != 'equal') ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: colors.secondary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              e.splitType,
                              style: GoogleFonts.inter(
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                                color: colors.secondary,
                              ),
                            ),
                          ),
                        ],
                        if (dt != null)
                          Text(
                            ' · ${DateFormat('d MMM').format(dt)}',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                    if (yourShareText.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        'YOUR SHARE: $yourShareText',
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: colors.primary,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Text(
                '₹${fmt.format(e.amount.round())}',
                style: GoogleFonts.manrope(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: colors.onSurface,
                ),
              ),
            ],
          ),
        ),
      );
    }).toList();

    return PremiumSurfaceCard(
      variant: PremiumSurfaceVariant.split,
      radius: 30,
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          for (var index = 0; index < items.length; index++) ...[
            items[index],
            if (index < items.length - 1) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Settlement history section
  // ---------------------------------------------------------------------------
  Widget _buildSettlementHistory(ColorScheme colors, NumberFormat fmt) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          colors,
          eyebrow: 'SETTLEMENTS',
          title: 'Settlement History',
        ),
        const SizedBox(height: 14),
        ..._settlements.map((s) {
          final dt = DateTime.tryParse(s.createdAt ?? '');
          final methodIcons = {
            'cash': Icons.money,
            'upi': Icons.qr_code,
            'bank': Icons.account_balance,
          };
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: PremiumSurfaceCard(
              variant: PremiumSurfaceVariant.positive,
              radius: 28,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F766E).withValues(alpha: 0.09),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      methodIcons[s.method] ?? Icons.payment,
                      size: 18,
                      color: const Color(0xFF0F766E),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        RichText(
                          text: TextSpan(
                            style: GoogleFonts.manrope(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: colors.onSurface,
                            ),
                            children: [
                              TextSpan(text: _memberName(s.fromMember)),
                              TextSpan(
                                text: ' paid ',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w400,
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                              TextSpan(text: _memberName(s.toMember)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Text(
                              s.method.toUpperCase(),
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: colors.outline,
                              ),
                            ),
                            if (dt != null) ...[
                              Text(
                                ' · ',
                                style: GoogleFonts.inter(
                                  fontSize: 10,
                                  color: colors.outline,
                                ),
                              ),
                              Text(
                                DateFormat('d MMM, h:mm a').format(dt),
                                style: GoogleFonts.inter(
                                  fontSize: 10,
                                  color: colors.outline,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '₹${fmt.format(s.amount.round())}',
                        style: GoogleFonts.manrope(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF0F766E),
                        ),
                      ),
                      if (s.id != null) ...[
                        const SizedBox(height: 4),
                        GestureDetector(
                          onTap: () => _confirmUndoSettlement(s, colors),
                          child: Text(
                            'Undo',
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: colors.error,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // New header row — group type label + name + back + settings
  // ---------------------------------------------------------------------------
  Widget _buildHeader(ColorScheme colors) {
    final typeLabel = (_group?.type ?? 'group').toUpperCase();
    final groupName = _group?.name ?? '';

    return Row(
      children: [
        GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              Icons.arrow_back_ios_new_rounded,
              size: 18,
              color: colors.onSurface,
            ),
          ),
        ),
        Expanded(
          child: Column(
            children: [
              Text(
                typeLabel,
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: colors.primary,
                  letterSpacing: 1.5,
                ),
              ),
              if (groupName.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  groupName,
                  style: GoogleFonts.manrope(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: colors.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
        GestureDetector(
          onTap: () => _showGroupSettings(colors),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(Icons.tune_rounded, size: 20, color: colors.onSurface),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Members avatar row — horizontal scroll with add button
  // ---------------------------------------------------------------------------
  Widget _buildMembersRow(ColorScheme colors) {
    return SizedBox(
      height: 70,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _members.length + 1,
        separatorBuilder: (_, separatorIndex) => const SizedBox(width: 12),
        itemBuilder: (_, i) {
          if (i == _members.length) {
            return GestureDetector(
              onTap: () => _showAddMember(colors),
              child: Column(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      color: Colors.white.withValues(alpha: 0.72),
                      border: Border.all(color: colors.outlineVariant),
                    ),
                    child: Icon(
                      Icons.add,
                      size: 18,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Add',
                    style: GoogleFonts.inter(
                      fontSize: 9,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            );
          }
          final m = _members[i];
          final label = m.isCurrentUser ? 'You' : m.name.split(' ').first;
          final accent = _memberAccent(colors, m.id ?? '');
          return Column(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  color: accent.withValues(alpha: 0.14),
                  border: Border.all(color: accent.withValues(alpha: 0.35)),
                ),
                child: Center(
                  child: Text(
                    _memberInitial(m.name),
                    style: GoogleFonts.manrope(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: accent,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 9,
                  color: colors.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // CTA row — Add Expense (filled) + Settle Up (outlined)
  // ---------------------------------------------------------------------------
  Widget _buildCtaRow(ColorScheme colors) {
    final hasDebts = _debts.isNotEmpty;
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: () => _showAddExpense(colors),
            child: Container(
              height: 56,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF142A6E), Color(0xFF2E4AA3)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF142A6E).withValues(alpha: 0.22),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.add_rounded, size: 20, color: Colors.white),
                  const SizedBox(width: 6),
                  Text(
                    'Add Expense',
                    style: GoogleFonts.manrope(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (hasDebts) ...[
          const SizedBox(width: 12),
          Expanded(
            child: GestureDetector(
              onTap: () {
                final debt = _primaryDebtForCurrentUser();
                if (debt != null) _showSettleUp(debt, colors);
              },
              child: Container(
                height: 56,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFE8FFF6), Color(0xFFD5F6EA)],
                  ),
                  border: Border.all(
                    color: const Color(0xFF22A06B),
                    width: 1.2,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.check_circle_outline_rounded,
                      size: 20,
                      color: Color(0xFF0F766E),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Settle Up',
                      style: GoogleFonts.manrope(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF0F766E),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Fluid Insights card — AI-style insight at bottom
  // ---------------------------------------------------------------------------
  Widget _buildFluidInsightsCard(ColorScheme colors, NumberFormat fmt) {
    // Per-member spending
    final paidByMap = <String, double>{};
    for (final e in _expenses) {
      paidByMap[e.paidBy] = (paidByMap[e.paidBy] ?? 0) + e.amount;
    }
    final spenders = paidByMap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topSpender = spenders.isNotEmpty ? spenders.first : null;
    final me = _members.where((m) => m.isCurrentUser).firstOrNull;

    // Generate insight text
    String insightText = '';
    if (me != null) {
      final myPaid = paidByMap[me.id] ?? 0;
      final avgPerPerson = _members.isNotEmpty
          ? _totalExpenses / _members.length
          : 0.0;
      final myNetDebt = _debts
          .where((d) => d.fromMemberId == me.id)
          .fold(0.0, (s, d) => s + d.amount);
      final myNetCredit = _debts
          .where((d) => d.toMemberId == me.id)
          .fold(0.0, (s, d) => s + d.amount);

      if (topSpender != null && topSpender.key == me.id) {
        insightText =
            'You\'re the top spender in this group with ₹${fmt.format(myPaid.round())} paid. ';
      } else if (myPaid > 0) {
        final myPct = _totalExpenses > 0
            ? (myPaid / _totalExpenses * 100).round()
            : 0;
        insightText =
            'You\'ve covered $myPct% of group spending (₹${fmt.format(myPaid.round())}). ';
      }

      if (myNetDebt > 0) {
        insightText +=
            'You owe ₹${fmt.format(myNetDebt.round())} — consider settling up soon.';
      } else if (myNetCredit > 0) {
        insightText +=
            'You\'re owed ₹${fmt.format(myNetCredit.round())} from the group.';
      } else if (_debts.isEmpty) {
        insightText += 'All balances are settled. Great teamwork!';
      }

      if (insightText.isEmpty && _expenses.isNotEmpty) {
        insightText =
            'This group has ₹${fmt.format(_totalExpenses.round())} in total expenses across ${_members.length} members. Average per person: ₹${fmt.format(avgPerPerson.round())}.';
      }
    } else if (_expenses.isNotEmpty) {
      final avgPerPerson = _members.isNotEmpty
          ? _totalExpenses / _members.length
          : 0.0;
      insightText =
          'Group total: ₹${fmt.format(_totalExpenses.round())} across ${_expenses.length} expenses. Average per person: ₹${fmt.format(avgPerPerson.round())}.';
    }

    if (insightText.isEmpty) return const SizedBox.shrink();

    return PremiumSurfaceCard(
      variant: PremiumSurfaceVariant.dashboard,
      radius: 30,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFF142A6E).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.auto_awesome,
                  size: 20,
                  color: Color(0xFF142A6E),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Fluid Insights',
                style: GoogleFonts.manrope(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF142A6E),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            insightText,
            style: GoogleFonts.inter(
              fontSize: 13,
              color: colors.onSurface,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Add Member bottom sheet with contacts, saved, and manual
// ---------------------------------------------------------------------------

class _AddMemberSheet extends StatefulWidget {
  final ColorScheme colors;
  final String groupId;
  final List<GroupMember> existingMembers;
  final SplitwiseRepository repo;
  final VoidCallback onAdded;

  const _AddMemberSheet({
    required this.colors,
    required this.groupId,
    required this.existingMembers,
    required this.repo,
    required this.onAdded,
  });

  @override
  State<_AddMemberSheet> createState() => _AddMemberSheetState();
}

class _AddMemberSheetState extends State<_AddMemberSheet> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _searchController = TextEditingController();
  List<Map<String, String>> _savedContacts = [];
  List<Contact> _phoneContacts = [];
  bool _loadingContacts = false;
  bool _adding = false;
  // Live copy of members — updated after each add
  late List<GroupMember> _currentMembers;
  String _tab = 'saved'; // 'saved', 'phone', 'manual'

  @override
  void initState() {
    super.initState();
    _currentMembers = List.of(widget.existingMembers);
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    try {
      final saved = await widget.repo.getSavedContacts();
      if (mounted) setState(() => _savedContacts = saved);
    } catch (e) {
      debugPrint('Error in group_detail_screen.dart: $e');
    }
  }

  Future<void> _loadPhoneContacts() async {
    if (_phoneContacts.isNotEmpty) return;
    setState(() => _loadingContacts = true);
    try {
      // Request permission — may show system dialog
      await FlutterContacts.requestPermission();
      // Small delay to let the OS update permission state after dialog
      await Future.delayed(const Duration(milliseconds: 300));
      // Now check the actual granted status
      final granted = await FlutterContacts.requestPermission(readonly: true);
      if (granted) {
        final contacts = await FlutterContacts.getContacts(
          withProperties: true,
        );
        if (mounted) {
          setState(() {
            _phoneContacts = contacts;
            _loadingContacts = false;
          });
        }
      } else {
        if (mounted) {
          setState(() => _loadingContacts = false);
        }
        showInfoSnackBar('Please allow contacts access in Settings');
      }
    } catch (e) {
      debugPrint('Load contacts failed: $e');
      if (mounted) setState(() => _loadingContacts = false);
    }
  }

  Future<void> _addMember(String name, String? phone) async {
    if (_adding) return; // prevent double-tap
    final trimName = name.trim();
    if (trimName.isEmpty) return;
    final normalizedPhone = normalizePhone(phone);

    // Check duplicate by name OR normalized phone
    final isDuplicate = _currentMembers.any((m) {
      final existingPhone = normalizePhone(m.phone);
      final byName = m.name.toLowerCase() == trimName.toLowerCase();
      final byPhone =
          normalizedPhone != null &&
          normalizedPhone.isNotEmpty &&
          existingPhone != null &&
          existingPhone.isNotEmpty &&
          existingPhone == normalizedPhone;
      return byName || byPhone;
    });
    if (isDuplicate) {
      showInfoSnackBar('$trimName is already in this group');
      return;
    }

    setState(() => _adding = true);
    try {
      final added = await widget.repo.addMember(
        GroupMember(
          groupId: widget.groupId,
          name: trimName,
          phone: normalizedPhone,
        ),
      );
      _currentMembers.add(added);
      // Save to contacts for reuse (non-blocking)
      widget.repo.saveContact(trimName, normalizedPhone);
      showSuccessSnackBar('$trimName added');
      widget.onAdded();
    } catch (e) {
      debugPrint('Add member failed: $e');
      if (e.toString().contains('duplicate') ||
          e.toString().contains('unique')) {
        showInfoSnackBar('$trimName is already in this group');
      } else {
        showErrorSnackBar('Could not add member. Check your connection.');
      }
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final query = _searchController.text.toLowerCase();

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      padding: EdgeInsets.fromLTRB(
        24,
        24,
        24,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLowest,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.outlineVariant.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Add Member',
              style: GoogleFonts.manrope(
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 16),

            // Tab selector
            Row(
              children: [
                _tabChip('saved', '⭐ Saved', colors),
                const SizedBox(width: 8),
                _tabChip('phone', '📱 Phone', colors),
                const SizedBox(width: 8),
                _tabChip('manual', '✏️ Manual', colors),
              ],
            ),
            const SizedBox(height: 16),

            if (_tab == 'manual') ...[
              // Manual entry
              TextField(
                controller: _nameController,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                style: GoogleFonts.manrope(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                decoration: InputDecoration(
                  hintText: 'Name',
                  prefixIcon: const Icon(Icons.person_outline, size: 20),
                  filled: true,
                  fillColor: colors.surfaceContainerLow,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                style: GoogleFonts.manrope(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                decoration: InputDecoration(
                  hintText: 'Phone (optional)',
                  prefixIcon: const Icon(Icons.phone_outlined, size: 20),
                  filled: true,
                  fillColor: colors.surfaceContainerLow,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              GestureDetector(
                onTap: _adding
                    ? null
                    : () {
                        final name = _nameController.text.trim();
                        if (name.isEmpty) return;
                        final phone = _phoneController.text.trim();
                        _addMember(name, phone.isEmpty ? null : phone);
                      },
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: _adding ? 0.6 : 1.0,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: LinearGradient(
                        colors: [colors.primary, colors.primaryContainer],
                      ),
                    ),
                    child: Center(
                      child: _adding
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              'Add Member',
                              style: GoogleFonts.manrope(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            ] else ...[
              // Search
              TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                style: GoogleFonts.inter(fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Search...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  filled: true,
                  fillColor: colors.surfaceContainerLow,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
              const SizedBox(height: 12),

              // Contact list
              SizedBox(
                height: 300,
                child: _tab == 'saved'
                    ? _buildSavedList(colors, query)
                    : _buildPhoneList(colors, query),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _tabChip(String value, String label, ColorScheme colors) {
    final isSel = _tab == value;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() => _tab = value);
          if (value == 'phone') _loadPhoneContacts();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSel ? colors.primary : colors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isSel ? Colors.white : colors.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSavedList(ColorScheme colors, String query) {
    final filtered = _savedContacts
        .where(
          (c) =>
              c['name']!.toLowerCase().contains(query) ||
              (c['phone'] ?? '').contains(query),
        )
        .toList();

    if (filtered.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _savedContacts.isEmpty
                ? 'No saved contacts yet.\nAdd members manually first — they\'ll appear here next time.'
                : 'No matches',
            style: GoogleFonts.inter(
              fontSize: 14,
              color: colors.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      itemCount: filtered.length,
      itemBuilder: (_, i) =>
          _contactTile(filtered[i]['name']!, filtered[i]['phone'], colors),
    );
  }

  Widget _buildPhoneList(ColorScheme colors, String query) {
    if (_loadingContacts) {
      return const Center(child: CircularProgressIndicator());
    }

    final filtered = _phoneContacts
        .where((c) => c.displayName.toLowerCase().contains(query))
        .toList();

    if (filtered.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'No contacts found',
            style: GoogleFonts.inter(
              fontSize: 14,
              color: colors.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      itemCount: filtered.length,
      itemBuilder: (_, i) {
        final c = filtered[i];
        final phone = c.phones.isNotEmpty ? c.phones.first.number : null;
        return _contactTile(c.displayName, phone, colors);
      },
    );
  }

  Widget _contactTile(String name, String? phone, ColorScheme colors) {
    final normalizedPhone = normalizePhone(phone);
    final alreadyAdded = _currentMembers.any((m) {
      final byName = m.name.toLowerCase() == name.trim().toLowerCase();
      final existingPhone = normalizePhone(m.phone);
      final byPhone =
          normalizedPhone != null &&
          normalizedPhone.isNotEmpty &&
          existingPhone != null &&
          existingPhone == normalizedPhone;
      return byName || byPhone;
    });
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: GestureDetector(
        onTap: alreadyAdded || _adding ? null : () => _addMember(name, phone),
        child: Opacity(
          opacity: alreadyAdded ? 0.5 : 1.0,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: colors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: colors.primary.withValues(alpha: 0.1),
                  child: Text(
                    (name.isNotEmpty ? name[0] : '?').toUpperCase(),
                    style: GoogleFonts.manrope(
                      fontWeight: FontWeight.w700,
                      color: colors.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: GoogleFonts.manrope(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (phone != null && phone.isNotEmpty)
                        Text(
                          phone,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                alreadyAdded
                    ? Icon(
                        Icons.check_circle,
                        color: colors.secondary,
                        size: 22,
                      )
                    : Icon(
                        Icons.add_circle_outline,
                        color: colors.primary,
                        size: 22,
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
