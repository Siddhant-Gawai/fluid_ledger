import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../../../../core/constants/categories.dart';
import '../../../../core/common_widgets/skeleton_loader.dart';
import '../../../../core/utils/snackbar_helper.dart';
import '../../data/transaction_repository.dart';
import '../../data/transaction_projection_service.dart';
import '../../../profile/data/profile_repository.dart';

class MonthlySummaryScreen extends ConsumerStatefulWidget {
  const MonthlySummaryScreen({super.key});

  @override
  ConsumerState<MonthlySummaryScreen> createState() =>
      _MonthlySummaryScreenState();
}

class _MonthlySummaryScreenState extends ConsumerState<MonthlySummaryScreen> {
  List<TransactionData> _transactions = [];
  MonthlySpendSnapshot? _snapshot;
  UserProfile? _profile;
  bool _loading = true;
  final _repaintKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final now = DateTime.now();
      final repo = ref.read(transactionRepositoryProvider);
      final results = await Future.wait([
        repo.getCachedTransactionsForMonth(now.year, now.month),
        repo.getCachedMonthlySnapshot(now.year, now.month),
        ref.read(profileRepositoryProvider).getCachedProfile(),
      ]);
      if (mounted) {
        setState(() {
          _transactions = results[0] as List<TransactionData>;
          _snapshot = results[1] as MonthlySpendSnapshot?;
          _profile = results[2] as UserProfile?;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Error in monthly_summary_screen.dart: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  List<TransactionData> get _thisMonth => _transactions;

  double get _totalSpent =>
      _snapshot?.totalSpend ??
      _thisMonth.fold(0.0, (sum, tx) => sum + tx.amount);

  Map<String, double> get _categoryMap {
    final cached = _snapshot?.categoryTotals;
    if (cached == null || cached.isEmpty) {
      final map = <String, double>{};
      for (final t in _thisMonth) {
        map[t.category] = (map[t.category] ?? 0) + t.amount;
      }
      final entries = map.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      return Map.fromEntries(entries);
    }
    final entries = cached.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Map.fromEntries(entries);
  }

  Future<void> _shareAsImage() async {
    try {
      final boundary =
          _repaintKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) return;

      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;

      final bytes = byteData.buffer.asUint8List();
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/fluid_ledger_summary.png');
      await file.writeAsBytes(bytes);

      await Share.shareXFiles([
        XFile(file.path),
      ], text: 'My spending summary from The Fluid Ledger');
    } catch (e) {
      showErrorSnackBar('Failed to share: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colors.surface,
      appBar: AppBar(
        backgroundColor: colors.surface,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Monthly Report',
          style: GoogleFonts.manrope(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: colors.onSurface,
          ),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 12),
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: Icon(Icons.share_outlined, color: colors.primary, size: 20),
              onPressed: _loading ? null : _shareAsImage,
            ),
          ),
        ],
      ),
      body: _loading
          ? const PageSkeleton(rows: 5)
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
              child: Column(
                children: [
                  RepaintBoundary(
                    key: _repaintKey,
                    child: _buildShareableCard(colors),
                  ),
                  const SizedBox(height: 24),
                  _buildShareButton(colors),
                ],
              ),
            ),
    );
  }

  Widget _buildShareableCard(ColorScheme colors) {
    final fmt = NumberFormat('#,##,###', 'en_IN');
    final budget = _profile?.monthlyBudget ?? 50000;
    final pct = budget > 0 ? ((_totalSpent / budget) * 100).round() : 0;
    final isOver = _totalSpent > budget;
    final cats = _categoryMap;

    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: colors.primary.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [colors.primary, colors.primaryContainer],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.account_balance_wallet,
                  color: Colors.white,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'The Fluid Ledger',
                style: GoogleFonts.manrope(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: colors.primary,
                ),
              ),
              const Spacer(),
              Text(
                DateFormat('MMMM yyyy').format(DateTime.now()),
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Name
          Text(
            '${_profile?.name ?? "User"}\'s Spending Report',
            style: GoogleFonts.manrope(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: colors.onSurface,
            ),
          ),
          const SizedBox(height: 20),

          // Total spent
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [colors.primary, colors.primaryContainer],
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'TOTAL SPENT',
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Colors.white.withValues(alpha: 0.7),
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '₹${fmt.format(_totalSpent.round())}',
                  style: GoogleFonts.manrope(
                    fontSize: 36,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 10),
                // Budget bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (pct / 100).clamp(0.0, 1.0),
                    backgroundColor: Colors.white.withValues(alpha: 0.2),
                    valueColor: AlwaysStoppedAnimation(
                      isOver
                          ? const Color(0xFFFF6B6B)
                          : const Color(0xFF93f2f2),
                    ),
                    minHeight: 6,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '$pct% of ₹${fmt.format(budget.round())} budget · ${_thisMonth.length} transactions',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Category breakdown
          Text(
            'BREAKDOWN',
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: colors.onSurfaceVariant,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 14),
          ...cats.entries.take(6).map((e) {
            final cat = getCategoryByName(e.key);
            final catPct = _totalSpent > 0
                ? (e.value / _totalSpent * 100).round()
                : 0;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Text(cat.emoji, style: const TextStyle(fontSize: 20)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              e.key,
                              style: GoogleFonts.manrope(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: colors.onSurface,
                              ),
                            ),
                            Text(
                              '₹${fmt.format(e.value.round())}',
                              style: GoogleFonts.manrope(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: colors.onSurface,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: (catPct / 100).clamp(0.0, 1.0),
                            backgroundColor: colors.outlineVariant.withValues(
                              alpha: 0.12,
                            ),
                            valueColor: AlwaysStoppedAnimation(cat.color),
                            minHeight: 4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '$catPct%',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 16),

          // Footer
          Center(
            child: Text(
              'Generated by The Fluid Ledger',
              style: GoogleFonts.inter(
                fontSize: 11,
                color: colors.outlineVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShareButton(ColorScheme colors) {
    return SizedBox(
      width: double.infinity,
      child: Container(
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
        child: ElevatedButton.icon(
          onPressed: _shareAsImage,
          icon: const Icon(Icons.share_outlined, color: Colors.white, size: 20),
          label: Text(
            'Share Report',
            style: GoogleFonts.manrope(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            padding: const EdgeInsets.symmetric(vertical: 18),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      ),
    );
  }
}
