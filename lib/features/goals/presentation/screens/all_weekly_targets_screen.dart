import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/categories.dart';
import '../../../../core/common_widgets/skeleton_loader.dart';
import '../../../../core/utils/snackbar_helper.dart';
import '../../data/goals_repository.dart';

class AllWeeklyTargetsScreen extends ConsumerStatefulWidget {
  const AllWeeklyTargetsScreen({super.key});

  @override
  ConsumerState<AllWeeklyTargetsScreen> createState() => _AllWeeklyTargetsScreenState();
}

class _AllWeeklyTargetsScreenState extends ConsumerState<AllWeeklyTargetsScreen> {
  List<WeeklyTarget> _targets = [];
  Map<String, double> _weeklySpend = {};
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
      final results = await Future.wait([
        repo.getWeeklyTargets(),
        repo.getWeeklyAttributedSpendByCategory(),
      ]);
      if (!mounted) return;
      setState(() {
        _targets = results[0] as List<WeeklyTarget>;
        _weeklySpend = results[1] as Map<String, double>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showErrorSnackBar('Failed to load weekly targets: $e');
    }
  }

  Future<void> _togglePin(WeeklyTarget t) async {
    final repo = ref.read(goalsRepositoryProvider);
    try {
      await repo.setWeeklyTargetPinned(t, !t.pinned);
      final refreshed = await repo.getCachedWeeklyTargets();
      if (!mounted) return;
      setState(() => _targets = refreshed);
    } catch (e) {
      showInfoSnackBar(e.toString().replaceFirst('StateError: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    final pinned = _targets.where((t) => t.pinned).toList();
    final rest = _targets.where((t) => !t.pinned).toList();
    final ordered = [...pinned, ...rest];

    return Scaffold(
      backgroundColor: colors.surface,
      appBar: AppBar(
        title: Text('Weekly Targets', style: GoogleFonts.manrope(fontWeight: FontWeight.w800)),
        backgroundColor: colors.surface,
      ),
      body: _loading
          ? const GridPageSkeleton()
          : RefreshIndicator(
              onRefresh: _load,
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                physics: const AlwaysScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.06,
                ),
                itemCount: ordered.length,
                itemBuilder: (_, i) {
                  final t = ordered[i];
                  final spent = lookupWeeklySpendForCategory(_weeklySpend, t.category);
                  final progress = t.limitAmount > 0 ? (spent / t.limitAmount).clamp(0.0, 1.5) : 0.0;
                  final cat = getCategoryByName(t.category);
                  return GestureDetector(
                    onTap: () async {
                      final id = t.id;
                      if (id == null || id.isEmpty) return;
                      await context.push('/weekly-target/$id');
                    },
                    child: _WeeklyTargetCard(
                      target: t,
                      spent: spent,
                      progress: progress,
                      cat: cat,
                      fmt: _fmt,
                      onPin: () => _togglePin(t),
                    ),
                  );
                },
              ),
            ),
    );
  }
}

class _WeeklyTargetCard extends StatelessWidget {
  final WeeklyTarget target;
  final double spent;
  final double progress;
  final ExpenseCategory cat;
  final NumberFormat fmt;
  final VoidCallback onPin;

  const _WeeklyTargetCard({
    required this.target,
    required this.spent,
    required this.progress,
    required this.cat,
    required this.fmt,
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
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 3))],
      ),
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
                        target.pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                        size: 16,
                        color: target.pinned ? const Color(0xFF1A237E) : Colors.grey.shade500,
                      ),
                    ),
                  ),
                  Text('$pct%', style: GoogleFonts.manrope(fontSize: 12, fontWeight: FontWeight.w800, color: _barColor)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            target.category,
            style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700),
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
              Text('₹${fmt.format(spent.round())} spent', style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade500)),
              Text(
                '₹${fmt.format(target.limitAmount.round())} target',
                style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade700),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
