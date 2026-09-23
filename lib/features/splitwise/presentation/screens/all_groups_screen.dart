import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../../core/common_widgets/skeleton_loader.dart';
import '../../../../core/common_widgets/premium_modal.dart';
import '../../../../core/database/local_db.dart';
import '../../../../core/supabase/supabase_config.dart';
import '../../../../core/utils/phone_utils.dart';
import '../../../../core/utils/snackbar_helper.dart';
import '../../../profile/data/profile_repository.dart';
import '../../data/splitwise_models.dart';
import '../../data/splitwise_projection_service.dart';
import '../../data/splitwise_realtime_service.dart';
import '../../data/splitwise_repository.dart';

const _groupTypes = [
  {'type': 'trip', 'emoji': '✈️', 'label': 'Trip'},
  {'type': 'roommates', 'emoji': '🏠', 'label': 'Household'},
  {'type': 'couple', 'emoji': '❤️', 'label': 'Couple'},
  {'type': 'friends', 'emoji': '👥', 'label': 'Friends'},
  {'type': 'family', 'emoji': '👨‍👩‍👧‍👦', 'label': 'Family'},
  {'type': 'other', 'emoji': '📋', 'label': 'Other'},
];

enum _ListMode { active, archived }

class AllGroupsScreen extends ConsumerStatefulWidget {
  const AllGroupsScreen({super.key});

  @override
  ConsumerState<AllGroupsScreen> createState() => _AllGroupsScreenState();
}

class _AllGroupsScreenState extends ConsumerState<AllGroupsScreen> {
  List<SplitGroup> _groups = [];
  Set<String> _archivedIds = {};
  Set<String> _pinnedGroupIds = {};
  final Map<String, double> _groupBalances = {};
  final Map<String, int> _expenseCounts = {};
  final Map<String, SplitwiseGroupSummary> _groupSummaries = {};
  bool _loading = true;
  bool _balancesLoaded = false;
  _ListMode _mode = _ListMode.active;

  final _fmt = NumberFormat('#,##,###', 'en_IN');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() => _loading = true);
    }
    try {
      final repo = ref.read(splitwiseRepositoryProvider);
      final projection = ref.read(splitwiseProjectionServiceProvider);
      final client = ref.read(supabaseClientProvider);
      final uid = client.auth.currentUser?.id;
      Set<String> archived = {};
      Set<String> pinned = {};
      if (uid != null) {
        archived = await LocalDB.instance.getArchivedSplitGroupIds(uid);
        pinned = await LocalDB.instance.getPinnedItemIds(
          userId: uid,
          itemType: 'split_group',
        );
      }

      var groups = await repo.getLocalGroups();
      if (groups.isNotEmpty && mounted) {
        setState(() {
          _groups = groups;
          _archivedIds = archived;
          _pinnedGroupIds = pinned;
          _loading = false;
          _balancesLoaded = false;
        });
      }

      await _syncBalances(groups, projection);
      await _loadExpenseCounts(projection, groups);

      groups = await repo.getGroups();
      if (!mounted) return;

      setState(() {
        _groups = groups;
        _archivedIds = archived;
        _pinnedGroupIds = pinned;
        _loading = false;
        _balancesLoaded = false;
      });

      await _syncBalances(groups, projection);
      await _loadExpenseCounts(projection, groups);
    } catch (e) {
      debugPrint('AllGroupsScreen load: $e');
      if (mounted) {
        setState(() => _loading = false);
      }
      showErrorSnackBar('Failed to load groups: $e');
    }
  }

  Future<void> _loadExpenseCounts(
    SplitwiseProjectionService projection,
    List<SplitGroup> groups,
  ) async {
    final summaries = await projection.getCachedSummaries();
    final counts = <String, int>{};
    for (final g in groups) {
      final id = g.id;
      if (id == null) continue;
      counts[id] = summaries[id]?.expenseCount ?? 0;
    }
    if (!mounted) return;
    setState(() {
      _expenseCounts
        ..clear()
        ..addAll(counts);
      _groupSummaries
        ..clear()
        ..addAll(summaries);
    });
  }

  Future<void> _syncBalances(
    List<SplitGroup> groups,
    SplitwiseProjectionService projection,
  ) async {
    try {
      final cached = await projection.getCachedSummaries();
      if (cached.isNotEmpty && mounted) {
        final balances = <String, double>{};
        for (final g in groups) {
          final id = g.id;
          if (id == null) continue;
          final summary = cached[id];
          if (summary != null) {
            balances[id] = summary.net;
          }
        }
        setState(() {
          _groupBalances
            ..clear()
            ..addAll(balances);
          _groupSummaries
            ..clear()
            ..addAll(cached);
          _balancesLoaded = true;
        });
      }
    } catch (_) {}

    () async {
      try {
        await projection.refreshDirtyGroups();
        await projection.refreshGroupsFromRemote(
          groups.map((g) => g.id).whereType<String>(),
        );
        final summaries = await projection.getCachedSummaries();
        final balances = <String, double>{};
        for (final entry in summaries.entries) {
          balances[entry.key] = entry.value.net;
        }

        if (!mounted) return;
        setState(() {
          _groupBalances
            ..clear()
            ..addAll(balances);
          _groupSummaries
            ..clear()
            ..addAll(summaries);
          _balancesLoaded = true;
        });
        await _loadExpenseCounts(projection, groups);
      } catch (_) {}
    }();
  }

  List<SplitGroup> get _activeList {
    final list = _groups
        .where((g) => g.id != null && !_archivedIds.contains(g.id!))
        .toList();
    final pinned = list.where((g) => _pinnedGroupIds.contains(g.id)).toList();
    final rest = list.where((g) => !_pinnedGroupIds.contains(g.id)).toList();
    return [...pinned, ...rest];
  }

  List<SplitGroup> get _archivedList {
    return _groups
        .where((g) => g.id != null && _archivedIds.contains(g.id!))
        .toList();
  }

  Future<void> _togglePin(SplitGroup group) async {
    final id = group.id;
    if (id == null) return;
    final uid = ref.read(supabaseClientProvider).auth.currentUser?.id;
    if (uid == null) return;
    final db = LocalDB.instance;
    final pinned = _pinnedGroupIds.contains(id);
    try {
      await db.setPinnedItem(
        userId: uid,
        itemType: 'split_group',
        itemId: id,
        pinned: !pinned,
      );
      final next = await db.getPinnedItemIds(
        userId: uid,
        itemType: 'split_group',
      );
      if (!mounted) return;
      setState(() => _pinnedGroupIds = next);
    } catch (e) {
      showInfoSnackBar(e.toString().replaceFirst('StateError: ', ''));
    }
  }

  Future<void> _setArchived(SplitGroup group, bool archived) async {
    final id = group.id;
    if (id == null) return;
    final uid = ref.read(supabaseClientProvider).auth.currentUser?.id;
    if (uid == null) return;
    await LocalDB.instance.setSplitGroupArchived(uid, id, archived);
    final next = await LocalDB.instance.getArchivedSplitGroupIds(uid);
    if (!mounted) return;
    setState(() => _archivedIds = next);
    final projection = ref.read(splitwiseProjectionServiceProvider);
    await _syncBalances(_groups, projection);
  }

  Future<void> _confirmDelete(SplitGroup group) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => PremiumDialog(
        title: 'Delete Group',
        body:
            'Delete "${group.name}"? All expenses, splits, and settlements will be permanently removed.',
        primaryLabel: 'Delete',
        destructive: true,
        onPrimary: () => Navigator.pop(ctx, true),
        onSecondary: () => Navigator.pop(ctx, false),
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ref.read(splitwiseRepositoryProvider).deleteGroup(group.id!);
      showSuccessSnackBar('"${group.name}" deleted');
      await _load();
    } catch (_) {
      showErrorSnackBar('Could not delete group. Try again.');
    }
  }

  bool _canArchive(SplitGroup group) {
    final id = group.id;
    if (id == null) return false;
    final balance = (_groupBalances[id] ?? 0).abs();
    final settled = balance <= 0.5;
    final hasExpenses = (_expenseCounts[id] ?? 0) > 0;
    return settled && hasExpenses;
  }

  Future<void> _showCreateGroup(ColorScheme colors) async {
    final nameController = TextEditingController();
    String selectedType = 'friends';
    String selectedEmoji = '👥';

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => PremiumSheetContainer(
          padding: EdgeInsets.fromLTRB(
            24,
            24,
            24,
            MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.outlineVariant.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'New Group',
                style: GoogleFonts.manrope(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: colors.onSurface,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _groupTypes.map((groupType) {
                  final selected = selectedType == groupType['type'];
                  return GestureDetector(
                    onTap: () => setModalState(() {
                      selectedType = groupType['type'] as String;
                      selectedEmoji = groupType['emoji'] as String;
                    }),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: selected
                            ? const Color(0xFFE9EEFF)
                            : const Color(0xFFF6F7FB),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: selected
                              ? const Color(0xFF3751C5).withValues(alpha: 0.18)
                              : Colors.transparent,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            groupType['emoji'] as String,
                            style: const TextStyle(fontSize: 18),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            groupType['label'] as String,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: selected
                                  ? const Color(0xFF24389C)
                                  : colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: nameController,
                autofocus: true,
                style: GoogleFonts.manrope(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
                decoration: InputDecoration(
                  hintText: 'Group name',
                  filled: true,
                  fillColor: const Color(0xFFF7F8FC),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 18,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF3751C5),
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(56),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                onPressed: () async {
                  final name = nameController.text.trim();
                  if (name.isEmpty) return;
                  Navigator.pop(ctx);
                  try {
                    final repo = ref.read(splitwiseRepositoryProvider);
                    final client = ref.read(supabaseClientProvider);
                    final userId = client.auth.currentUser!.id;
                    final userPhone = normalizePhone(
                      client.auth.currentUser?.phone,
                    );
                    final profile = await ref
                        .read(profileRepositoryProvider)
                        .getCachedProfile();
                    final displayName = profile?.name ?? 'Me';
                    final group = await repo.createGroup(
                      SplitGroup(
                        name: name,
                        type: selectedType,
                        emoji: selectedEmoji,
                        createdBy: userId,
                      ),
                    );
                    await repo.addMember(
                      GroupMember(
                        groupId: group.id!,
                        name: displayName,
                        userId: userId,
                        phone: userPhone,
                      ),
                    );
                    await _load();
                  } catch (e) {
                    debugPrint('Create group failed: $e');
                    showErrorSnackBar(
                      'Could not create group. Check your connection.',
                    );
                  }
                },
                child: Text(
                  'Create Group',
                  style: GoogleFonts.manrope(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(splitwiseRealtimeBootstrapProvider);
    ref.listen<AsyncValue<SplitwiseInvalidation>>(
      splitwiseRealtimeEventsProvider,
      (_, next) {
        next.whenData((event) {
          if (!mounted) return;
          if (event.groupsChanged ||
              event.groupIds.any(
                (groupId) => _groups.any((group) => group.id == groupId),
              )) {
            _load();
          }
        });
      },
    );

    final colors = Theme.of(context).colorScheme;
    final list = _mode == _ListMode.active ? _activeList : _archivedList;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FB),
      body: SafeArea(
        bottom: false,
        child: _loading
            ? const PageSkeleton(rows: 7)
            : RefreshIndicator(
                onRefresh: _load,
                color: const Color(0xFF3751C5),
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(
                      child: SafeArea(
                        bottom: false,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildHeader(context, colors),
                              const SizedBox(height: 16),
                              _buildModeSwitcher(),
                              const SizedBox(height: 14),
                              _buildInsightCard(),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (list.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Text(
                              _mode == _ListMode.active
                                  ? 'No groups yet.'
                                  : 'No archived groups.',
                              style: GoogleFonts.inter(
                                fontSize: 15,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(18, 4, 18, 104),
                        sliver: SliverList.separated(
                          itemBuilder: (context, index) =>
                              _groupTile(list[index], colors),
                          separatorBuilder: (context, index) =>
                              const SizedBox(height: 14),
                          itemCount: list.length,
                        ),
                      ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, ColorScheme colors) {
    return Row(
      children: [
        GestureDetector(
          onTap: () => context.pop(),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF253A96).withValues(alpha: 0.08),
                  blurRadius: 16,
                  offset: const Offset(0, 7),
                ),
              ],
            ),
            child: const Icon(
              Icons.arrow_back_ios_new_rounded,
              size: 17,
              color: Color(0xFF24389C),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            'Expense Groups',
            style: GoogleFonts.manrope(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.8,
              color: const Color(0xFF24389C),
            ),
          ),
        ),
        GestureDetector(
          onTap: () => _showCreateGroup(colors),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF4860CF),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF4860CF).withValues(alpha: 0.22),
                  blurRadius: 16,
                  offset: const Offset(0, 7),
                ),
              ],
            ),
            child: const Icon(Icons.add_rounded, color: Colors.white, size: 22),
          ),
        ),
      ],
    );
  }

  Widget _buildModeSwitcher() {
    final activeCount = _activeList.length;
    final archivedCount = _archivedList.length;

    Widget pill(_ListMode mode, String label, int count) {
      final selected = _mode == mode;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _mode = mode),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: selected ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(999),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 14,
                        offset: const Offset(0, 6),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: GoogleFonts.manrope(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: selected
                        ? const Color(0xFF24389C)
                        : const Color(0xFF2E3144),
                  ),
                ),
                if (count > 0) ...[
                  const SizedBox(width: 5),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: selected
                          ? const Color(0xFFE9EEFF)
                          : const Color(0xFFECEEF5),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '$count',
                      style: GoogleFonts.inter(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: selected
                            ? const Color(0xFF24389C)
                            : const Color(0xFF6C7287),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: const Color(0xFFEDEFF6),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [
          pill(_ListMode.active, 'Active', activeCount),
          pill(_ListMode.archived, 'Archived', archivedCount),
        ],
      ),
    );
  }

  Widget _buildInsightCard() {
    final activeGroups = _activeList;
    final totalReceivable = activeGroups.fold<double>(0, (sum, group) {
      final groupId = group.id;
      final balance = groupId == null ? 0 : (_groupBalances[groupId] ?? 0);
      return balance > 0.5 ? sum + balance : sum;
    });
    final count = activeGroups.where((group) {
      final groupId = group.id;
      final balance = groupId == null ? 0 : (_groupBalances[groupId] ?? 0);
      return balance > 0.5;
    }).length;
    final amount = _fmt.format(totalReceivable.round());
    final line = count == 0
        ? 'Everything is settled across your active groups right now.'
        : 'You are owed ₹$amount across $count ${count == 1 ? 'group' : 'groups'} this month.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF283EA7), Color(0xFF435CAB)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2C43A7).withValues(alpha: 0.22),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.auto_awesome_rounded,
                color: Color(0xFF8EF0FF),
                size: 17,
              ),
              const SizedBox(width: 5),
              Text(
                'VAULT AI INSIGHT',
                style: GoogleFonts.inter(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                  color: Colors.white.withValues(alpha: 0.86),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            line,
            style: GoogleFonts.manrope(
              fontSize: 14,
              height: 1.22,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _groupTile(SplitGroup group, ColorScheme colors) {
    final groupId = group.id;
    final summary = groupId == null ? null : _groupSummaries[groupId];
    final balance = groupId == null ? 0 : (_groupBalances[groupId] ?? 0);
    final expenseCount = groupId == null ? 0 : (_expenseCounts[groupId] ?? 0);
    final memberCount = summary?.memberCount ?? 0;
    final hasExpenses = expenseCount > 0;
    final isReceivable = balance > 0.5;
    final isSettled = hasExpenses && balance.abs() <= 0.5;
    final archived = groupId != null && _archivedIds.contains(groupId);
    final showArchiveOption = !archived && _canArchive(group);
    final tint = _iconTintForType(group.type);
    final statusColor = isSettled
        ? const Color(0xFF2E3144)
        : isReceivable
        ? const Color(0xFF0E7C78)
        : const Color(0xFFC1332F);
    final metaLabel =
        _groupTypes.firstWhere(
              (item) => item['type'] == group.type,
              orElse: () => _groupTypes.last,
            )['label']
            as String;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () async {
          await context.push('/group/${group.id}');
          await _load();
        },
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF23368C).withValues(alpha: 0.05),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: tint.withValues(alpha: 0.16),
                      ),
                      child: Icon(
                        _iconForType(group.type),
                        size: 22,
                        color: tint,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    group.name,
                                    style: GoogleFonts.manrope(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                      height: 1.15,
                                      color: const Color(0xFF111318),
                                    ),
                                  ),
                                ),
                                if (_mode == _ListMode.active &&
                                    group.id != null)
                                  GestureDetector(
                                    onTap: () => _togglePin(group),
                                    child: Padding(
                                      padding: const EdgeInsets.only(left: 8),
                                      child: Icon(
                                        _pinnedGroupIds.contains(group.id)
                                            ? Icons.push_pin_rounded
                                            : Icons.push_pin_outlined,
                                        size: 17,
                                        color:
                                            _pinnedGroupIds.contains(group.id)
                                            ? const Color(0xFF24389C)
                                            : const Color(0xFF9AA0B5),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F3F8),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                metaLabel.toUpperCase(),
                                style: GoogleFonts.inter(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.2,
                                  color: const Color(0xFF72778B),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        GestureDetector(
                          onTap: () => _showGroupActionsSheet(
                            group,
                            archived,
                            showArchiveOption,
                          ),
                          child: Container(
                            width: 26,
                            height: 26,
                            alignment: Alignment.center,
                            child: const Icon(
                              Icons.more_horiz_rounded,
                              size: 17,
                              color: Color(0xFF8B90A4),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          archived ? 'Archived' : 'Settlement',
                          style: GoogleFonts.inter(
                            fontSize: 9,
                            color: const Color(0xFF696F82),
                          ),
                        ),
                        const SizedBox(height: 6),
                        _balancesLoaded
                            ? Text(
                                !hasExpenses
                                    ? 'New'
                                    : isSettled
                                    ? 'Settled Up'
                                    : '${isReceivable ? 'Owed' : 'You owe'} ₹${_fmt.format(balance.abs().round())}',
                                textAlign: TextAlign.right,
                                style: GoogleFonts.manrope(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  height: 1.2,
                                  color: !hasExpenses
                                      ? const Color(0xFF6C7287)
                                      : statusColor,
                                ),
                              )
                            : Container(
                                width: 72,
                                height: 14,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF0F2F7),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _buildMemberAvatars(memberCount),
                    const Spacer(),
                    Icon(
                      isSettled
                          ? Icons.done_all_rounded
                          : Icons.access_time_filled_rounded,
                      size: 11,
                      color: const Color(0xFF5D6173),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      _timeMeta(
                        summary?.lastActivityAt ?? group.createdAt,
                        isSettled,
                      ),
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFF3B3F51),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMemberAvatars(int memberCount) {
    if (memberCount <= 0) {
      return Text(
        'No members',
        style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF757A8F)),
      );
    }
    final visible = memberCount > 3 ? 3 : memberCount;
    final palette = [
      const Color(0xFF1F2A44),
      const Color(0xFF4357A6),
      const Color(0xFF0F7E79),
    ];
    return SizedBox(
      width: memberCount > 3 ? 74 : 42 + ((visible - 1) * 14),
      height: 22,
      child: Stack(
        children: [
          for (var index = 0; index < visible; index++)
            Positioned(
              left: index * 14,
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: palette[index % palette.length],
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: Center(
                  child: Text(
                    String.fromCharCode(65 + index),
                    style: GoogleFonts.manrope(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
          if (memberCount > 3)
            Positioned(
              left: 42,
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFE7EAF4),
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: Center(
                  child: Text(
                    '+${memberCount - 3}',
                    style: GoogleFonts.inter(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF262A3B),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _timeMeta(String? raw, bool isSettled) {
    final base = _relativeTime(raw);
    return isSettled ? 'Last settled $base' : 'Updated $base';
  }

  String _relativeTime(String? raw) {
    if (raw == null || raw.isEmpty) return 'recently';
    final parsed = DateTime.tryParse(raw)?.toLocal();
    if (parsed == null) return 'recently';
    final diff = DateTime.now().difference(parsed);
    if (diff.inMinutes < 60) {
      final mins = diff.inMinutes <= 0 ? 1 : diff.inMinutes;
      return '${mins}m ago';
    }
    if (diff.inHours < 24) {
      return '${diff.inHours}h ago';
    }
    if (diff.inDays < 7) {
      return '${diff.inDays}d ago';
    }
    return DateFormat('MMM d').format(parsed);
  }

  IconData _iconForType(String type) {
    switch (type) {
      case 'roommates':
        return Icons.home_rounded;
      case 'trip':
        return Icons.flight_takeoff_rounded;
      case 'family':
        return Icons.deck_rounded;
      case 'couple':
        return Icons.favorite_rounded;
      case 'friends':
        return Icons.work_rounded;
      default:
        return Icons.folder_copy_rounded;
    }
  }

  Color _iconTintForType(String type) {
    switch (type) {
      case 'roommates':
        return const Color(0xFF3B4EB4);
      case 'trip':
        return const Color(0xFF0C7B79);
      case 'family':
        return const Color(0xFF1D5F73);
      case 'couple':
        return const Color(0xFFB93D59);
      case 'friends':
        return const Color(0xFF3C47A4);
      default:
        return const Color(0xFF5E6480);
    }
  }

  void _showGroupActionsSheet(
    SplitGroup group,
    bool archived,
    bool showArchiveOption,
  ) {
    final colors = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => PremiumSheetContainer(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.outlineVariant.withValues(alpha: 0.28),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              group.name,
              style: GoogleFonts.manrope(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: colors.onSurface,
              ),
            ),
            const SizedBox(height: 16),
            if (showArchiveOption)
              _actionTile(
                icon: Icons.archive_outlined,
                title: 'Archive group',
                subtitle: 'Hide it from the active list.',
                onTap: () async {
                  Navigator.pop(ctx);
                  await _setArchived(group, true);
                },
              ),
            if (archived)
              _actionTile(
                icon: Icons.unarchive_outlined,
                title: 'Move back to active',
                subtitle: 'Restore this group to your main list.',
                onTap: () async {
                  Navigator.pop(ctx);
                  await _setArchived(group, false);
                },
              ),
            _actionTile(
              icon: Icons.delete_outline_rounded,
              title: 'Delete group',
              subtitle: 'Remove all expenses, splits, and settlements.',
              destructive: true,
              onTap: () async {
                Navigator.pop(ctx);
                await _confirmDelete(group);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool destructive = false,
  }) {
    final tone = destructive
        ? const Color(0xFFC33833)
        : const Color(0xFF24389C);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: destructive
                ? const Color(0xFFFFF3F1)
                : const Color(0xFFF6F7FB),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: destructive
                      ? const Color(0xFFFFE5E1)
                      : const Color(0xFFE8EDFF),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, size: 17, color: tone),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.manrope(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: destructive
                            ? const Color(0xFFB8312E)
                            : const Color(0xFF151821),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: const Color(0xFF70768A),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Color(0xFF8A90A3)),
            ],
          ),
        ),
      ),
    );
  }
}
