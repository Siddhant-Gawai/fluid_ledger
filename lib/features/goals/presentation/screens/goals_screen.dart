import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../../core/common_widgets/gradient_hero_card.dart';
import '../../../../core/common_widgets/hero_screen_themes.dart';
import '../../../../core/common_widgets/premium_surface_card.dart';
import '../../../../core/constants/categories.dart';
import '../../../../core/utils/inr_amount_input_formatter.dart';
import '../../../../core/utils/snackbar_helper.dart';
import '../../data/goals_repository.dart';
import '../widgets/active_goal_card.dart';
import '../widgets/goal_editor_sheet.dart';
import '../widgets/goal_top_up_sheet.dart';

// ---------------------------------------------------------------------------
// GoalsScreen
// ---------------------------------------------------------------------------

class GoalsScreen extends ConsumerStatefulWidget {
  const GoalsScreen({super.key});

  @override
  ConsumerState<GoalsScreen> createState() => GoalsScreenState();
}

class GoalsScreenState extends ConsumerState<GoalsScreen> {
  void showAddGoal() => _showGoalSheet();
  List<Goal> _goals = [];
  List<WeeklyTarget> _weeklyTargets = [];
  Map<String, double> _weeklySpend = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final repo = ref.read(goalsRepositoryProvider);
      // Cache-first for goals & targets, parallel fetch
      final results = await Future.wait([
        repo.getCachedGoals(),
        repo.getCachedWeeklyTargets(),
        repo.getWeeklyAttributedSpendByCategory(),
      ]);
      if (mounted) {
        setState(() {
          _goals = results[0] as List<Goal>;
          _weeklyTargets = results[1] as List<WeeklyTarget>;
          _weeklySpend = results[2] as Map<String, double>;
          _loading = false;
        });
      }
      // Then refresh from cloud in background
      final fresh = await Future.wait([
        repo.getGoals(),
        repo.getWeeklyTargets(),
        repo.getWeeklyAttributedSpendByCategory(),
      ]);
      if (mounted) {
        setState(() {
          _goals = fresh[0] as List<Goal>;
          _weeklyTargets = fresh[1] as List<WeeklyTarget>;
          _weeklySpend = fresh[2] as Map<String, double>;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
      showErrorSnackBar('Failed to load goals: $e');
    }
  }

  // ── Add / Edit Goal ────────────────────────────────────────────────────────

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
                  setState(
                    () => _goals.removeWhere((g) => g.id == existing.id),
                  );
                  showSuccessSnackBar('Goal deleted');
                } catch (e) {
                  showErrorSnackBar('Failed to delete: $e');
                }
              },
      ),
    );
  }

  // ── Add money (savings goal) ──────────────────────────────────────────────

  void _showTopUpSheet(Goal goal) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => GoalTopUpSheet(
        goal: goal,
        onTopUp: (amount) async {
          final repo = ref.read(goalsRepositoryProvider);
          final updated = goal.copyWith(
            savedAmount: (goal.savedAmount + amount).clamp(
              0,
              goal.targetAmount,
            ),
          );
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

  // ── Log spend (weekly target manual spend) ──────────────────────────────────

  void _showWeeklyBudgetTopUpSheet(WeeklyTarget target) {
    final attributed = lookupWeeklySpendForCategory(
      _weeklySpend,
      target.category,
    );
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _WeeklyBudgetTopUpSheet(
        target: target,
        attributedSpend: attributed,
        onConfirm: (addAmount) async {
          final repo = ref.read(goalsRepositoryProvider);
          try {
            final saved = await repo.addWeeklyManualSpendTopUp(
              target,
              addAmount,
            );
            final attributedMap = await repo
                .getWeeklyAttributedSpendByCategory();
            if (!mounted) return;
            setState(() {
              final i = _weeklyTargets.indexWhere((t) => t.id == saved.id);
              if (i >= 0) {
                final copy = List<WeeklyTarget>.from(_weeklyTargets);
                copy[i] = saved;
                _weeklyTargets = copy;
              } else {
                _weeklyTargets = [..._weeklyTargets, saved];
              }
              _weeklySpend = attributedMap;
            });
            final addedManual =
                saved.manualSpentTopUp - target.manualSpentTopUp;
            final fmt = NumberFormat('#,##,##0', 'en_IN');
            if (addedManual + 0.01 < addAmount) {
              showInfoSnackBar(
                'Logged ₹${fmt.format(addedManual.round())} (weekly target ₹${fmt.format(saved.limitAmount.round())} reached).',
              );
            } else {
              showSuccessSnackBar(
                'Logged spend (+₹${fmt.format(addedManual.round())})',
              );
            }
          } catch (e) {
            showErrorSnackBar('Failed to update: $e');
          }
        },
      ),
    );
  }

  // ── Add / Edit Weekly Target ────────────────────────────────────────────────

  void _showWeeklyTargetSheet({
    WeeklyTarget? existing,
    String? suggestedCategory,
  }) {
    final usedCategories = _weeklyTargets.map((t) => t.category).toSet();
    final userId = ref.read(goalsRepositoryProvider).userId;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _WeeklyTargetSheet(
        existing: existing,
        suggestedCategory: suggestedCategory,
        userId: userId,
        usedCategories: usedCategories,
        onSave: (target) async {
          final repo = ref.read(goalsRepositoryProvider);
          try {
            if (existing == null) {
              final created = await repo.addWeeklyTarget(target);
              setState(() => _weeklyTargets.add(created));
              showSuccessSnackBar('Weekly target added!');
            } else {
              final saved = await repo.updateWeeklyTarget(target);
              setState(() {
                final idx = _weeklyTargets.indexWhere((t) => t.id == saved.id);
                if (idx != -1) {
                  _weeklyTargets[idx] = saved;
                } else {
                  _weeklyTargets.add(saved);
                }
              });
              showSuccessSnackBar('Target updated!');
            }
          } catch (e) {
            showErrorSnackBar('Failed to save target: $e');
          }
        },
        onDelete: existing == null
            ? null
            : () async {
                final repo = ref.read(goalsRepositoryProvider);
                try {
                  await repo.deleteWeeklyTarget(existing.id!);
                  setState(
                    () =>
                        _weeklyTargets.removeWhere((t) => t.id == existing.id),
                  );
                  showSuccessSnackBar('Target removed');
                } catch (e) {
                  showErrorSnackBar('Failed to delete: $e');
                }
              },
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##,##0', 'en_IN');
    final colors = Theme.of(context).colorScheme;
    final hero = GoalsRepository.heroSnapshot(_goals);
    final pinnedGoals = _goals
        .where((g) => g.pinned && !g.isCompleted)
        .toList();
    final pinnedTargets = _weeklyTargets.where((t) => t.pinned).toList();
    final sysPad = MediaQuery.of(context).padding.bottom;
    final contentBottomPad = 68 + (sysPad > 0 ? sysPad : 12) + 16.0;

    final goalsHeroProgress = () {
      final hasGoals = _goals.isNotEmpty;
      if (hero.activeTarget > 0) {
        return (hero.activeSaved / hero.activeTarget).clamp(0.0, 1.0);
      }
      if (hasGoals && hero.activeCount == 0) return 1.0;
      return 0.0;
    }();

    final goalsPillText = _goals.isEmpty
        ? 'Get started'
        : (hero.activeCount == 0 && hero.completedCount > 0)
        ? 'All complete'
        : 'On Track';

    return Scaffold(
      backgroundColor: colors.surface,
      // Keep top inset outside the scroll view so the status bar / notch region
      // stays fixed (matches DashboardScreen). SafeArea inside a sliver scrolls away.
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _load,
          color: const Color(0xFF1A237E),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                  child: GradientHeroCard(
                    fmt: fmt,
                    loading: _loading,
                    topLeftLabel: 'YOUR GOALS',
                    statusPillText: goalsPillText,
                    statusPillAccentColor: const Color(0xFF93f2f2),
                    metricLabel: 'Total Saved',
                    metricHint:
                        (!_loading &&
                            _goals.isNotEmpty &&
                            hero.completedCount > 0)
                        ? '· incl. completed'
                        : null,
                    amountValue: hero.savedAll,
                    progress: goalsHeroProgress,
                    accentColor: const Color(0xFF93f2f2),
                    footerLeft: _heroFooterLeft(
                      _goals.length,
                      hero.activeCount,
                      hero.completedCount,
                    ),
                    footerRight: _heroFooterRight(
                      goalCount: _goals.length,
                      activeCount: hero.activeCount,
                      activeRemaining: hero.activeRemaining,
                      fmt: fmt,
                    ),
                    backgroundGradient: HeroScreenThemes.goalsGradient,
                    watermark: HeroScreenThemes.goalsWatermark(),
                  ),
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, contentBottomPad),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    _ActiveGoalsSection(
                      previewGoals:
                          (pinnedGoals.isNotEmpty
                                  ? pinnedGoals
                                  : _goals.where((g) => !g.isCompleted))
                              .take(2)
                              .toList(),
                      totalGoalCount: _goals.length,
                      fmt: fmt,
                      loading: _loading,
                      onAdd: () => _showGoalSheet(),
                      onTap: (g) => _showGoalSheet(existing: g),
                      onTopUp: _showTopUpSheet,
                      onPin: (g) async {
                        final repo = ref.read(goalsRepositoryProvider);
                        try {
                          await repo.setGoalPinned(g, !g.pinned);
                          final refreshed = await repo.getCachedGoals();
                          if (!mounted) return;
                          setState(() => _goals = refreshed);
                        } catch (e) {
                          showInfoSnackBar(
                            e.toString().replaceFirst('StateError: ', ''),
                          );
                        }
                      },
                      onViewAll: () async {
                        await context.push('/all-goals');
                        if (mounted) await _load();
                      },
                    ),
                    const SizedBox(height: 24),
                    _WeeklyTargetsSection(
                      targets: pinnedTargets.isNotEmpty
                          ? pinnedTargets
                          : _weeklyTargets.take(2).toList(),
                      weeklySpend: _weeklySpend,
                      fmt: fmt,
                      loading: _loading,
                      onAdd: () => _showWeeklyTargetSheet(),
                      onTap: (t) async {
                        final id = t.id;
                        if (id == null || id.isEmpty) {
                          _showWeeklyTargetSheet(existing: t);
                          return;
                        }
                        await context.push('/weekly-target/$id');
                      },
                      onTopUp: _showWeeklyBudgetTopUpSheet,
                      onPin: (t) async {
                        final repo = ref.read(goalsRepositoryProvider);
                        try {
                          await repo.setWeeklyTargetPinned(t, !t.pinned);
                          final refreshed = await repo.getCachedWeeklyTargets();
                          if (!mounted) return;
                          setState(() => _weeklyTargets = refreshed);
                        } catch (e) {
                          showInfoSnackBar(
                            e.toString().replaceFirst('StateError: ', ''),
                          );
                        }
                      },
                      onViewAll: () async {
                        await context.push('/all-weekly-targets');
                        if (mounted) await _load();
                      },
                    ),
                    const SizedBox(height: 24),
                    _SmartSuggestionCard(
                      goals: _goals,
                      weeklyTargets: _weeklyTargets,
                      weeklySpend: _weeklySpend,
                      onSetGoal: () => _showGoalSheet(),
                      onTopUpGoal: _showTopUpSheet,
                      onAddWeeklyTarget: (category) =>
                          _showWeeklyTargetSheet(suggestedCategory: category),
                    ),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Goals hero footer strings (used with [GradientHeroCard])
// =============================================================================

String _heroFooterLeft(int goalCount, int activeCount, int completedCount) {
  if (goalCount == 0) return '';
  if (activeCount == 0 && completedCount > 0) {
    return completedCount == 1
        ? '1 goal completed'
        : '$completedCount goals completed';
  }
  final parts = <String>[];
  if (activeCount > 0) {
    parts.add(activeCount == 1 ? '1 active' : '$activeCount active');
  }
  if (completedCount > 0) {
    parts.add(completedCount == 1 ? '1 done' : '$completedCount done');
  }
  return parts.join(' · ');
}

String _heroFooterRight({
  required int goalCount,
  required int activeCount,
  required double activeRemaining,
  required NumberFormat fmt,
}) {
  if (goalCount == 0) return 'Add a savings goal';
  if (activeCount == 0) return 'All targets met';
  return '₹${fmt.format(activeRemaining.round())} to go';
}

// =============================================================================
// Active Goals Section
// =============================================================================

class _ActiveGoalsSection extends StatelessWidget {
  final List<Goal> previewGoals;
  final int totalGoalCount;
  final NumberFormat fmt;
  final bool loading;
  final VoidCallback onAdd;
  final ValueChanged<Goal> onTap;
  final ValueChanged<Goal> onTopUp;
  final ValueChanged<Goal> onPin;
  final Future<void> Function()? onViewAll;

  const _ActiveGoalsSection({
    required this.previewGoals,
    required this.totalGoalCount,
    required this.fmt,
    required this.loading,
    required this.onAdd,
    required this.onTap,
    required this.onTopUp,
    required this.onPin,
    required this.onViewAll,
  });

  @override
  Widget build(BuildContext context) {
    final showViewAll = totalGoalCount > 0 && onViewAll != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Active Goals',
                style: GoogleFonts.manrope(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF1A237E),
                ),
              ),
            ),
            if (showViewAll)
              GestureDetector(
                onTap: () => onViewAll!(),
                child: Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Text(
                    'View all ($totalGoalCount)',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF3949AB),
                    ),
                  ),
                ),
              ),
            GestureDetector(
              onTap: onAdd,
              child: Text(
                '+ Add',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF1A237E),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (loading) ...[
          const GoalCardSkeleton(),
          const SizedBox(height: 12),
          const GoalCardSkeleton(),
        ] else if (previewGoals.isEmpty)
          totalGoalCount == 0
              ? _EmptyState(
                  icon: Icons.flag_outlined,
                  label: 'No goals yet',
                  sub: 'Tap + Add to set your first savings goal',
                  onTap: onAdd,
                )
              : _EmptyState(
                  icon: Icons.task_alt_outlined,
                  label: 'No active goals',
                  sub:
                      'Your remaining goals are completed. Tap here or use View all above to open the full list.',
                  onTap: () {
                    if (onViewAll != null) {
                      onViewAll!();
                    } else {
                      onAdd();
                    }
                  },
                )
        else
          ...previewGoals.map(
            (g) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: ActiveGoalCard(
                goal: g,
                fmt: fmt,
                onTap: () => onTap(g),
                onTopUp: () => onTopUp(g),
                onPinToggle: () => onPin(g),
              ),
            ),
          ),
      ],
    );
  }
}

// =============================================================================
// Weekly Targets Section
// =============================================================================

class _WeeklyTargetsSection extends StatelessWidget {
  final List<WeeklyTarget> targets;
  final Map<String, double> weeklySpend;
  final NumberFormat fmt;
  final bool loading;
  final VoidCallback onAdd;
  final ValueChanged<WeeklyTarget> onTap;
  final ValueChanged<WeeklyTarget> onTopUp;
  final ValueChanged<WeeklyTarget> onPin;
  final Future<void> Function()? onViewAll;
  const _WeeklyTargetsSection({
    required this.targets,
    required this.weeklySpend,
    required this.fmt,
    required this.loading,
    required this.onAdd,
    required this.onTap,
    required this.onTopUp,
    required this.onPin,
    required this.onViewAll,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Weekly Targets',
                style: GoogleFonts.manrope(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF1A237E),
                ),
              ),
            ),
            if (targets.isNotEmpty && onViewAll != null)
              GestureDetector(
                onTap: () => onViewAll!(),
                child: Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Text(
                    'View all',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF3949AB),
                    ),
                  ),
                ),
              ),
            GestureDetector(
              onTap: onAdd,
              child: Text(
                '+ Add',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF1A237E),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (loading)
          Row(
            children: [
              Expanded(child: _TargetCardSkeleton()),
              const SizedBox(width: 12),
              Expanded(child: _TargetCardSkeleton()),
            ],
          )
        else if (targets.isEmpty)
          _EmptyState(
            icon: Icons.track_changes_outlined,
            label: 'No weekly targets',
            sub: 'Tap + Add to track spending by category',
            onTap: onAdd,
          )
        else
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: targets.map((t) {
              final spent = lookupWeeklySpendForCategory(
                weeklySpend,
                t.category,
              );
              final progress = t.limitAmount > 0
                  ? (spent / t.limitAmount).clamp(0.0, 1.5)
                  : 0.0;
              final cat = getCategoryByName(t.category);
              return SizedBox(
                width: (MediaQuery.of(context).size.width - 44) / 2,
                child: _TargetCard(
                  target: t,
                  spent: spent,
                  progress: progress,
                  cat: cat,
                  fmt: fmt,
                  onTap: () => onTap(t),
                  onTopUp: () => onTopUp(t),
                  onPin: () => onPin(t),
                ),
              );
            }).toList(),
          ),
      ],
    );
  }
}

class _TargetCard extends StatelessWidget {
  final WeeklyTarget target;
  final double spent;
  final double progress;
  final ExpenseCategory cat;
  final NumberFormat fmt;
  final VoidCallback onTap;
  final VoidCallback onTopUp;
  final VoidCallback onPin;
  const _TargetCard({
    required this.target,
    required this.spent,
    required this.progress,
    required this.cat,
    required this.fmt,
    required this.onTap,
    required this.onTopUp,
    required this.onPin,
  });

  Color get _barColor {
    if (progress >= 1.0) return const Color(0xFFE53935);
    if (progress >= 0.8) return const Color(0xFFFB8C00);
    return const Color(0xFF43A047);
  }

  @override
  Widget build(BuildContext context) {
    final pct = (progress * 100).round().clamp(0, 999);
    return PremiumSurfaceCard(
      variant: progress >= 1.0
          ? PremiumSurfaceVariant.negative
          : PremiumSurfaceVariant.goals,
      padding: const EdgeInsets.all(14),
      radius: 16,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: onTap,
            behavior: HitTestBehavior.opaque,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(cat.emoji, style: const TextStyle(fontSize: 18)),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GestureDetector(
                          onTap: onPin,
                          behavior: HitTestBehavior.opaque,
                          child: Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Icon(
                              target.pinned
                                  ? Icons.push_pin_rounded
                                  : Icons.push_pin_outlined,
                              size: 16,
                              color: target.pinned
                                  ? const Color(0xFF1A237E)
                                  : Colors.grey.shade500,
                            ),
                          ),
                        ),
                        Text(
                          '$pct%',
                          style: GoogleFonts.manrope(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: _barColor,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  target.category,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress.clamp(0.0, 1.0),
                    backgroundColor: Colors.grey.shade100,
                    valueColor: AlwaysStoppedAnimation<Color>(_barColor),
                    minHeight: 5,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '₹${fmt.format(spent.round())} spent',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: Colors.grey.shade500,
                      ),
                    ),
                    Text(
                      '₹${fmt.format(target.limitAmount.round())} target',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: onTopUp,
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 7),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF00897B), Color(0xFF00695C)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF00897B).withValues(alpha: 0.25),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.add_rounded, size: 14, color: Colors.white),
                  const SizedBox(width: 4),
                  Text(
                    'Log spend',
                    style: GoogleFonts.manrope(
                      fontSize: 11,
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
    );
  }
}

class _TargetCardSkeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 150,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8),
        ],
      ),
    );
  }
}

// =============================================================================
// Smart Suggestion Card
// =============================================================================

enum _SmartSuggestionCTA { addWeeklyBudget, topUpGoal, setGoal }

class _ResolvedSmartSuggestion {
  final String text;
  final _SmartSuggestionCTA cta;
  final Goal? goalForTopUp;
  final String? weeklyCategoryHint;

  _ResolvedSmartSuggestion({
    required this.text,
    required this.cta,
    this.goalForTopUp,
    this.weeklyCategoryHint,
  });
}

class _SmartSuggestionCard extends StatelessWidget {
  final List<Goal> goals;
  final List<WeeklyTarget> weeklyTargets;
  final Map<String, double> weeklySpend;
  final VoidCallback onSetGoal;
  final ValueChanged<Goal> onTopUpGoal;
  final ValueChanged<String?> onAddWeeklyTarget;
  const _SmartSuggestionCard({
    required this.goals,
    required this.weeklyTargets,
    required this.weeklySpend,
    required this.onSetGoal,
    required this.onTopUpGoal,
    required this.onAddWeeklyTarget,
  });

  _ResolvedSmartSuggestion _resolve() {
    final fmt = NumberFormat('#,##,##0', 'en_IN');

    final uncovered =
        weeklySpend.entries
            .where(
              (e) => !weeklyTargets.any(
                (t) =>
                    getCategoryByName(t.category).name ==
                    getCategoryByName(e.key).name,
              ),
            )
            .toList()
          ..sort((a, b) => b.value.compareTo(a.value));

    if (uncovered.isNotEmpty) {
      final top = uncovered.first;
      final cat = getCategoryByName(top.key);
      return _ResolvedSmartSuggestion(
        text:
            'You spent ₹${fmt.format(top.value.round())} on ${cat.name} this week with no budget set. '
            'Consider setting a weekly target to stay on track.',
        cta: _SmartSuggestionCTA.addWeeklyBudget,
        weeklyCategoryHint: top.key,
      );
    }

    final incomplete = goals.where((g) => !g.isCompleted).toList();
    if (incomplete.isNotEmpty) {
      final slowest = incomplete.reduce(
        (a, b) => a.progress < b.progress ? a : b,
      );
      final remaining = (slowest.targetAmount - slowest.savedAmount).clamp(
        0,
        double.infinity,
      );
      return _ResolvedSmartSuggestion(
        text:
            'Your "${slowest.name}" goal is at ${(slowest.progress * 100).round()}%. '
            'Add ₹${fmt.format(remaining.round())} more to complete it.',
        cta: _SmartSuggestionCTA.topUpGoal,
        goalForTopUp: slowest,
      );
    }

    if (goals.isNotEmpty) {
      return _ResolvedSmartSuggestion(
        text:
            'You have reached every savings goal—nice work. Add another goal when you are ready.',
        cta: _SmartSuggestionCTA.setGoal,
      );
    }

    return _ResolvedSmartSuggestion(
      text:
          'Set a savings goal to start tracking your financial progress and build healthy money habits.',
      cta: _SmartSuggestionCTA.setGoal,
    );
  }

  String _ctaLabel(_SmartSuggestionCTA cta) {
    switch (cta) {
      case _SmartSuggestionCTA.addWeeklyBudget:
        return 'Add weekly budget';
      case _SmartSuggestionCTA.topUpGoal:
        return 'Add money';
      case _SmartSuggestionCTA.setGoal:
        return 'Set Goal';
    }
  }

  void _onCta(_ResolvedSmartSuggestion r) {
    switch (r.cta) {
      case _SmartSuggestionCTA.addWeeklyBudget:
        onAddWeeklyTarget(r.weeklyCategoryHint);
        break;
      case _SmartSuggestionCTA.topUpGoal:
        final g = r.goalForTopUp;
        if (g != null) onTopUpGoal(g);
        break;
      case _SmartSuggestionCTA.setGoal:
        onSetGoal();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final resolved = _resolve();
    return PremiumSurfaceCard(
      variant: PremiumSurfaceVariant.goals,
      padding: EdgeInsets.zero,
      radius: 20,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Column(
          children: [
            // Teal accent bar at top
            Container(
              height: 4,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF26C6DA), Color(0xFF1A237E)],
                ),
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF26C6DA), Color(0xFF00ACC1)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.auto_awesome_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Smart Savings Suggestion',
                          style: GoogleFonts.manrope(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    resolved.text,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: Colors.grey.shade600,
                      height: 1.55,
                    ),
                  ),
                  const SizedBox(height: 16),
                  GestureDetector(
                    onTap: () => _onCta(resolved),
                    child: Container(
                      width: double.infinity,
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A237E),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        _ctaLabel(resolved.cta),
                        style: GoogleFonts.manrope(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Empty State
// =============================================================================

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String label;
  final String sub;
  final VoidCallback onTap;
  const _EmptyState({
    required this.icon,
    required this.label,
    required this.sub,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: PremiumSurfaceCard(
        variant: PremiumSurfaceVariant.goals,
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
        radius: 18,
        child: Column(
          children: [
            Icon(
              icon,
              size: 36,
              color: const Color(0xFF1A237E).withValues(alpha: 0.35),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              style: GoogleFonts.manrope(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              sub,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: Colors.grey.shade500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Log spend sheet (weekly target)
// =============================================================================

class _WeeklyBudgetTopUpSheet extends StatefulWidget {
  final WeeklyTarget target;

  /// Transactions + existing manually logged spend (shown as “spent”).
  final double attributedSpend;
  final Future<void> Function(double amount) onConfirm;
  const _WeeklyBudgetTopUpSheet({
    required this.target,
    required this.attributedSpend,
    required this.onConfirm,
  });

  @override
  State<_WeeklyBudgetTopUpSheet> createState() =>
      _WeeklyBudgetTopUpSheetState();
}

class _WeeklyBudgetTopUpSheetState extends State<_WeeklyBudgetTopUpSheet> {
  final _ctrl = TextEditingController();
  bool _saving = false;
  final _fmt = NumberFormat('#,##,##0', 'en_IN');

  void _onAmountChanged() => setState(() {});

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_onAmountChanged);
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onAmountChanged);
    _ctrl.dispose();
    super.dispose();
  }

  double? _parseRupeeInput(String raw) {
    final cleaned = raw.replaceAll(',', '').trim();
    if (cleaned.isEmpty) return null;
    return double.tryParse(cleaned);
  }

  Future<void> _submit() async {
    final amount = _parseRupeeInput(_ctrl.text);
    if (amount == null || amount <= 0) {
      showErrorSnackBar('Enter a valid amount');
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.onConfirm(amount);
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cat = getCategoryByName(widget.target.category);
    final limit = widget.target.limitAmount;
    final attributed = widget.attributedSpend;
    final roomLeft = (limit - attributed).clamp(0.0, double.infinity);
    final parsedAdd = _parseRupeeInput(_ctrl.text);
    final maxH = MediaQuery.of(context).size.height * 0.92;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        constraints: BoxConstraints(maxHeight: maxH),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                '${cat.emoji} Log spend',
                textAlign: TextAlign.center,
                style: GoogleFonts.manrope(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Text(
                  cat.name,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: Colors.grey.shade600,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Text(
                  'Records spend for this category that isn’t already in your transactions (e.g. cash). '
                  'Your weekly target stays the same — counted spend moves toward it, up to that amount.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: Colors.grey.shade500,
                    height: 1.35,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '₹${_fmt.format(attributed.round())} spent',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    Text(
                      'Target ₹${_fmt.format(limit.round())}',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF1A237E),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  children: [500, 1000, 2000, 5000].map((amt) {
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: OutlinedButton(
                          onPressed: () {
                            final text = _fmt.format(amt);
                            _ctrl.value = TextEditingValue(
                              text: text,
                              selection: TextSelection.collapsed(
                                offset: text.length,
                              ),
                            );
                          },
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: Colors.grey.shade300),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                          ),
                          child: Text(
                            '₹${_fmt.format(amt)}',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: TextField(
                  controller: _ctrl,
                  keyboardType: TextInputType.number,
                  autofocus: true,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    InrAmountInputFormatter(),
                  ],
                  decoration: InputDecoration(
                    labelText: 'Amount to log (₹)',
                    helperText: 'Commas auto-added (e.g. 12,34,567).',
                    helperMaxLines: 2,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    prefixText: '₹ ',
                  ),
                ),
              ),
              if (parsedAdd != null && parsedAdd > 0) ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    roomLeft <= 0
                        ? 'Already at your ₹${_fmt.format(limit.round())} weekly target.'
                        : 'Logs up to ₹${_fmt.format(parsedAdd > roomLeft ? roomLeft.round() : parsedAdd.round())} '
                              '(₹${_fmt.format(roomLeft.round())} room left before target).',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF00695C),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF00897B),
                    disabledBackgroundColor: Colors.grey.shade300,
                    minimumSize: const Size(double.infinity, 52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: _saving ? null : () => _submit(),
                  child: _saving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          'Log spend',
                          style: GoogleFonts.manrope(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Weekly Target Sheet (Add / Edit)
// =============================================================================

class _WeeklyTargetSheet extends StatefulWidget {
  final WeeklyTarget? existing;

  /// Pre-select category when adding (e.g. from smart suggestion).
  final String? suggestedCategory;
  final String userId;
  final Set<String> usedCategories;
  final Future<void> Function(WeeklyTarget) onSave;
  final VoidCallback? onDelete;
  const _WeeklyTargetSheet({
    this.existing,
    this.suggestedCategory,
    required this.userId,
    required this.usedCategories,
    required this.onSave,
    this.onDelete,
  });

  @override
  State<_WeeklyTargetSheet> createState() => _WeeklyTargetSheetState();
}

class _WeeklyTargetSheetState extends State<_WeeklyTargetSheet> {
  String? _selectedCategory;
  final _limitCtrl = TextEditingController();
  bool _saving = false;

  List<ExpenseCategory> get _availableCategories {
    final used = widget.usedCategories;
    // When editing, allow current category
    if (widget.existing != null) {
      return defaultCategories
          .where(
            (c) =>
                !used.contains(c.name) || c.name == widget.existing!.category,
          )
          .toList();
    }
    return defaultCategories.where((c) => !used.contains(c.name)).toList();
  }

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      _selectedCategory = widget.existing!.category;
      _limitCtrl.text = widget.existing!.limitAmount.toStringAsFixed(0);
    } else if (widget.suggestedCategory != null) {
      final hint = widget.suggestedCategory!;
      final validName = defaultCategories.any((c) => c.name == hint);
      if (validName && !widget.usedCategories.contains(hint)) {
        _selectedCategory = hint;
      }
    }
  }

  @override
  void dispose() {
    _limitCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_selectedCategory == null) {
      showErrorSnackBar('Pick a category');
      return;
    }
    final limit = double.tryParse(_limitCtrl.text);
    if (limit == null || limit <= 0) {
      showErrorSnackBar('Enter a valid limit');
      return;
    }

    setState(() => _saving = true);
    try {
      final target = WeeklyTarget(
        id: widget.existing?.id,
        userId: widget.userId,
        category: _selectedCategory!,
        limitAmount: limit,
        manualSpentTopUp: widget.existing?.manualSpentTopUp ?? 0,
        createdAt: widget.existing?.createdAt,
      );
      await widget.onSave(target);
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    final cats = _availableCategories;
    final maxH = MediaQuery.sizeOf(context).height * 0.92;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        constraints: BoxConstraints(maxHeight: maxH),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Text(
                      isEdit ? 'Edit Target' : 'Weekly Target',
                      style: GoogleFonts.manrope(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    if (isEdit && widget.onDelete != null)
                      IconButton(
                        icon: const Icon(
                          Icons.delete_outline,
                          color: Color(0xFFE53935),
                        ),
                        onPressed: () {
                          Navigator.pop(context);
                          widget.onDelete!();
                        },
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Category grid
              SizedBox(
                height: 110,
                child: GridView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 0.7,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 10,
                  ),
                  itemCount: cats.length,
                  itemBuilder: (_, i) {
                    final cat = cats[i];
                    final selected = cat.name == _selectedCategory;
                    return GestureDetector(
                      onTap: () => setState(() => _selectedCategory = cat.name),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        decoration: BoxDecoration(
                          color: selected
                              ? cat.color.withValues(alpha: 0.15)
                              : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(12),
                          border: selected
                              ? Border.all(color: cat.color, width: 2)
                              : null,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              cat.emoji,
                              style: const TextStyle(fontSize: 20),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              cat.name,
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: selected
                                    ? cat.color
                                    : Colors.grey.shade600,
                              ),
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    TextField(
                      controller: _limitCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Weekly Limit (₹)',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: Colors.grey.shade50,
                        prefixText: '₹ ',
                      ),
                    ),
                    const SizedBox(height: 16),
                    GestureDetector(
                      onTap: _saving ? null : _submit,
                      child: Container(
                        width: double.infinity,
                        height: 52,
                        decoration: BoxDecoration(
                          color: _saving
                              ? Colors.grey.shade300
                              : const Color(0xFF1A237E),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        alignment: Alignment.center,
                        child: _saving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                isEdit ? 'Save Changes' : 'Add Target',
                                style: GoogleFonts.manrope(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
