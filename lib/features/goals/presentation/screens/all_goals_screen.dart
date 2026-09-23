import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../../core/utils/snackbar_helper.dart';
import '../../data/goals_repository.dart';
import '../widgets/active_goal_card.dart';
import '../widgets/goal_editor_sheet.dart';
import '../widgets/goal_top_up_sheet.dart';

enum _GoalFilter { all, inProgress, completed }

enum _GoalSort {
  newestFirst,
  oldestFirst,
  nameAZ,
  nameZA,
  progressHigh,
  progressLow,
  targetHigh,
  savedHigh,
  deadlineSoonest,
}

extension on _GoalSort {
  String get title => switch (this) {
        _GoalSort.newestFirst => 'Newest first',
        _GoalSort.oldestFirst => 'Oldest first',
        _GoalSort.nameAZ => 'Name A–Z',
        _GoalSort.nameZA => 'Name Z–A',
        _GoalSort.progressHigh => 'Progress (high → low)',
        _GoalSort.progressLow => 'Progress (low → high)',
        _GoalSort.targetHigh => 'Target amount (high → low)',
        _GoalSort.savedHigh => 'Amount saved (high → low)',
        _GoalSort.deadlineSoonest => 'Deadline (soonest)',
      };
}

/// Full list of savings goals with sort and filter.
class AllGoalsScreen extends ConsumerStatefulWidget {
  const AllGoalsScreen({super.key});

  @override
  ConsumerState<AllGoalsScreen> createState() => _AllGoalsScreenState();
}

class _AllGoalsScreenState extends ConsumerState<AllGoalsScreen> {
  List<Goal> _goals = [];
  bool _loading = true;
  _GoalFilter _filter = _GoalFilter.all;
  _GoalSort _sort = _GoalSort.newestFirst;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final repo = ref.read(goalsRepositoryProvider);
      final list = await repo.getGoals();
      if (!mounted) return;
      setState(() {
        _goals = list;
        _loading = false;
      });
    } catch (e) {
      debugPrint('AllGoalsScreen load: $e');
      if (mounted) {
        setState(() => _loading = false);
        showErrorSnackBar('Failed to load goals: $e');
      }
    }
  }

  DateTime? _created(Goal g) => DateTime.tryParse(g.createdAt ?? '');

  DateTime _deadlineKey(Goal g) {
    if (g.deadline == null) return DateTime(2100);
    return DateTime.tryParse(g.deadline!) ?? DateTime(2100);
  }

  List<Goal> get _filteredAndSorted {
    var list = [..._goals];
    switch (_filter) {
      case _GoalFilter.all:
        break;
      case _GoalFilter.inProgress:
        list = list.where((g) => !g.isCompleted).toList();
      case _GoalFilter.completed:
        list = list.where((g) => g.isCompleted).toList();
    }

    int cmp(Goal a, Goal b) {
      switch (_sort) {
        case _GoalSort.newestFirst:
          final da = _created(a) ?? DateTime(1970);
          final db = _created(b) ?? DateTime(1970);
          return db.compareTo(da);
        case _GoalSort.oldestFirst:
          final da = _created(a) ?? DateTime.now();
          final db = _created(b) ?? DateTime.now();
          return da.compareTo(db);
        case _GoalSort.nameAZ:
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        case _GoalSort.nameZA:
          return b.name.toLowerCase().compareTo(a.name.toLowerCase());
        case _GoalSort.progressHigh:
          return b.progress.compareTo(a.progress);
        case _GoalSort.progressLow:
          return a.progress.compareTo(b.progress);
        case _GoalSort.targetHigh:
          return b.targetAmount.compareTo(a.targetAmount);
        case _GoalSort.savedHigh:
          return b.savedAmount.compareTo(a.savedAmount);
        case _GoalSort.deadlineSoonest:
          return _deadlineKey(a).compareTo(_deadlineKey(b));
      }
    }

    list.sort(cmp);
    return list;
  }

  void _showGoalSheet({Goal? existing}) {
    final userId = ref.read(goalsRepositoryProvider).userId;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => GoalEditorSheet(
        existing: existing,
        userId: userId,
        onSave: (goal) async {
          final repo = ref.read(goalsRepositoryProvider);
          try {
            if (existing == null) {
              final created = await repo.addGoal(goal);
              setState(() => _goals.insert(0, created));
              showSuccessSnackBar('Goal added!');
            } else {
              await repo.updateGoal(goal);
              setState(() {
                final idx = _goals.indexWhere((g) => g.id == goal.id);
                if (idx != -1) _goals[idx] = goal;
              });
              showSuccessSnackBar('Goal updated!');
            }
          } catch (e) {
            showErrorSnackBar('Failed to save goal: $e');
          }
        },
        onDelete: existing == null
            ? null
            : () async {
                final repo = ref.read(goalsRepositoryProvider);
                try {
                  await repo.deleteGoal(existing.id!);
                  setState(() => _goals.removeWhere((g) => g.id == existing.id));
                  showSuccessSnackBar('Goal deleted');
                } catch (e) {
                  showErrorSnackBar('Failed to delete: $e');
                }
              },
      ),
    );
  }

  void _showTopUpSheet(Goal goal) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => GoalTopUpSheet(
        goal: goal,
        onTopUp: (amount) async {
          final repo = ref.read(goalsRepositoryProvider);
          final updated = goal.copyWith(savedAmount: (goal.savedAmount + amount).clamp(0, goal.targetAmount));
          try {
            await repo.updateGoal(updated);
            setState(() {
              final idx = _goals.indexWhere((g) => g.id == goal.id);
              if (idx != -1) _goals[idx] = updated;
            });
            showSuccessSnackBar(
              '₹${NumberFormat('#,##,##0', 'en_IN').format(amount.round())} added to ${goal.name}!',
            );
          } catch (e) {
            showErrorSnackBar('Failed to add money: $e');
          }
        },
      ),
    );
  }

  Future<void> _togglePin(Goal g) async {
    final repo = ref.read(goalsRepositoryProvider);
    try {
      await repo.setGoalPinned(g, !g.pinned);
      final refreshed = await repo.getCachedGoals();
      if (!mounted) return;
      setState(() => _goals = refreshed);
    } catch (e) {
      showInfoSnackBar(e.toString().replaceFirst('StateError: ', ''));
    }
  }

  Future<void> _pickSort() async {
    final chosen = await showModalBottomSheet<_GoalSort>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final colors = Theme.of(ctx).colorScheme;
        final sortMaxH = MediaQuery.sizeOf(ctx).height * 0.55;
        return Container(
          constraints: BoxConstraints(maxHeight: sortMaxH),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SafeArea(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                    child: Row(
                      children: [
                        Text(
                          'Sort by',
                          style: GoogleFonts.manrope(fontSize: 18, fontWeight: FontWeight.w800),
                        ),
                        const Spacer(),
                        IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                      ],
                    ),
                  ),
                  ..._GoalSort.values.map((s) {
                    final sel = s == _sort;
                    return ListTile(
                      title: Text(s.title, style: GoogleFonts.inter(fontWeight: sel ? FontWeight.w700 : FontWeight.w500)),
                      trailing: sel ? Icon(Icons.check, color: colors.primary) : null,
                      onTap: () => Navigator.pop(ctx, s),
                    );
                  }),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        );
      },
    );
    if (chosen != null) setState(() => _sort = chosen);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final fmt = NumberFormat('#,##,##0', 'en_IN');
    final visible = _filteredAndSorted;

    return Scaffold(
      backgroundColor: colors.surface,
      appBar: AppBar(
        backgroundColor: colors.surface,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Your goals', style: GoogleFonts.manrope(fontSize: 18, fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            tooltip: 'Sort',
            icon: const Icon(Icons.sort_rounded),
            onPressed: _pickSort,
          ),
          IconButton(
            tooltip: 'Add goal',
            icon: const Icon(Icons.add_rounded),
            onPressed: () => _showGoalSheet(),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _FilterChip(
                  label: 'All',
                  selected: _filter == _GoalFilter.all,
                  onTap: () => setState(() => _filter = _GoalFilter.all),
                ),
                _FilterChip(
                  label: 'In progress',
                  selected: _filter == _GoalFilter.inProgress,
                  onTap: () => setState(() => _filter = _GoalFilter.inProgress),
                ),
                _FilterChip(
                  label: 'Done',
                  selected: _filter == _GoalFilter.completed,
                  onTap: () => setState(() => _filter = _GoalFilter.completed),
                ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: _loading
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      children: const [
                        GoalCardSkeleton(),
                        SizedBox(height: 12),
                        GoalCardSkeleton(),
                      ],
                    )
                  : visible.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
                          children: [
                            Icon(Icons.flag_outlined, size: 56, color: colors.outlineVariant),
                            const SizedBox(height: 16),
                            Text(
                              _goals.isEmpty ? 'No goals yet' : 'No goals match',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.manrope(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _goals.isEmpty
                                  ? 'Tap + to create your first savings goal.'
                                  : 'Try another filter or sort.',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.inter(fontSize: 14, color: colors.outline),
                            ),
                          ],
                        )
                      : ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
                          itemCount: visible.length,
                          separatorBuilder: (context, _) => const SizedBox(height: 12),
                          itemBuilder: (_, i) {
                            final g = visible[i];
                            return ActiveGoalCard(
                              goal: g,
                              fmt: fmt,
                              onTap: () => _showGoalSheet(existing: g),
                              onTopUp: () => _showTopUpSheet(g),
                              onPinToggle: () => _togglePin(g),
                            );
                          },
                        ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? colors.primary : colors.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? colors.primary : colors.outlineVariant.withValues(alpha: 0.25),
            ),
          ),
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: selected ? colors.onPrimary : colors.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}
