import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../../core/common_widgets/skeleton_loader.dart';
import '../../../../core/constants/categories.dart';
import '../../../../core/utils/snackbar_helper.dart';
import '../../data/goals_repository.dart';

class WeeklyTargetHistoryScreen extends ConsumerStatefulWidget {
  final String targetId;
  const WeeklyTargetHistoryScreen({super.key, required this.targetId});

  @override
  ConsumerState<WeeklyTargetHistoryScreen> createState() => _WeeklyTargetHistoryScreenState();
}

class _WeeklyTargetHistoryScreenState extends ConsumerState<WeeklyTargetHistoryScreen> {
  WeeklyTarget? _target;
  List<WeeklyTargetHistoryEntry> _history = [];
  bool _loading = true;
  final _fmt = NumberFormat('#,##,##0', 'en_IN');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final repo = ref.read(goalsRepositoryProvider);
      final targets = await repo.getCachedWeeklyTargets();
      final t = targets.firstWhere((x) => x.id == widget.targetId);
      final hist = await repo.getWeeklyTargetHistory(target: t, weeksBack: 16);
      if (!mounted) return;
      setState(() {
        _target = t;
        _history = hist;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showErrorSnackBar('Failed to load history: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final t = _target;
    final cat = t == null ? null : getCategoryByName(t.category);

    return Scaffold(
      backgroundColor: colors.surface,
      appBar: AppBar(
        title: Text('Weekly history', style: GoogleFonts.manrope(fontWeight: FontWeight.w800)),
        backgroundColor: colors.surface,
      ),
      body: _loading
          ? const PageSkeleton(rows: 6)
          : t == null
              ? Center(child: Text('Target not found', style: GoogleFonts.inter(color: colors.onSurfaceVariant)))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                    itemCount: _history.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (_, i) {
                      final w = _history[i];
                      final start = DateFormat('d MMM').format(w.weekStart);
                      final end = DateFormat('d MMM').format(w.weekEnd);
                      final total = w.total;
                      final pct = w.limit > 0 ? (total / w.limit).clamp(0.0, 2.0) : 0.0;
                      final isOver = total > w.limit + 0.01;

                      return Container(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                        decoration: BoxDecoration(
                          color: colors.surfaceContainerLowest,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.2)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(cat?.emoji ?? '🎯', style: const TextStyle(fontSize: 18)),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    '${cat?.name ?? t.category} · $start — $end',
                                    style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w700, color: colors.onSurface),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Text(
                                  isOver ? 'Over' : 'OK',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: isOver ? colors.error : colors.secondary,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: LinearProgressIndicator(
                                value: pct.clamp(0.0, 1.0),
                                minHeight: 8,
                                backgroundColor: colors.surfaceContainerHigh,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  isOver ? colors.error : colors.secondary,
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Total ₹${_fmt.format(total.round())} / ₹${_fmt.format(w.limit.round())}',
                                    style: GoogleFonts.inter(fontSize: 12, color: colors.onSurfaceVariant),
                                  ),
                                ),
                                Text(
                                  '${(pct * 100).round()}%',
                                  style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: colors.onSurface),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Tx ₹${_fmt.format(w.txnSpend.round())}',
                                    style: GoogleFonts.inter(fontSize: 12, color: colors.onSurfaceVariant),
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    'Manual ₹${_fmt.format(w.manualSpend.round())}',
                                    style: GoogleFonts.inter(fontSize: 12, color: colors.onSurfaceVariant),
                                    textAlign: TextAlign.end,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
