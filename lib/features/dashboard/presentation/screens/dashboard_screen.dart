import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../../../../core/constants/categories.dart';
import '../../../../core/common_widgets/gradient_hero_card.dart';
import '../../../../core/common_widgets/hero_screen_themes.dart';
import '../../../../core/common_widgets/merchant_icon.dart';
import '../../../../core/common_widgets/premium_surface_card.dart';
import '../../../../core/common_widgets/skeleton_loader.dart';
import '../../../../core/database/version_sync.dart';
import '../../../../core/notifications/notification_service.dart';
import '../../../../core/sms/sms_service.dart';
import '../../../expense/data/transaction_repository.dart';
import '../../../expense/data/transaction_projection_service.dart';
import '../../../profile/data/profile_repository.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => DashboardScreenState();
}

class DashboardScreenState extends ConsumerState<DashboardScreen> {
  List<TransactionData> _monthTransactions = [];
  List<Map<String, dynamic>> _summary = [];
  MonthlySpendSnapshot? _monthSnapshot;
  bool _loading = true;
  String? _loadError;
  int _pendingSmsCount = 0;
  bool _scanningSms = false;

  _MonthSnapshot get _lastMonthSnapshot {
    final now = DateTime.now();
    final prev = DateTime(now.year, now.month - 1);
    double total = 0;
    int txCount = 0;
    final catMap = <String, double>{};
    for (final row in _summary) {
      final dt = DateTime.tryParse(row['date'] as String? ?? '');
      if (dt == null || dt.year != prev.year || dt.month != prev.month) continue;
      final amount = (row['amount'] as num?)?.toDouble() ?? 0;
      final cat = (row['category'] as String?) ?? 'Other';
      total += amount;
      txCount += 1;
      catMap[cat] = (catMap[cat] ?? 0) + amount;
    }
    String? topCategory;
    double topAmount = 0;
    if (catMap.isNotEmpty) {
      final top = catMap.entries.reduce((a, b) => a.value >= b.value ? a : b);
      topCategory = top.key;
      topAmount = top.value;
    }
    return _MonthSnapshot(
      month: prev,
      total: total,
      txCount: txCount,
      topCategory: topCategory,
      topAmount: topAmount,
    );
  }

  @override
  void initState() {
    super.initState();
    _load();
    _autoScanSms();
  }

  void reload() {
    _autoScanDone = false;
    _load();
    _autoScanSms();
  }

  // Static so it persists across widget rebuilds / tab switches
  static bool _alertShownThisSession = false;
  static bool _autoScanDone = false;
  static void resetAlertFlag() {
    _alertShownThisSession = false;
    _autoScanDone = false;
  }

  double _monthlyBudget = 50000;

  Future<void> _load() async {
    if (mounted) {
      setState(() => _loadError = null);
    }
    try {
      final repo = ref.read(transactionRepositoryProvider);
      final now = DateTime.now();

      // Step 1: Load from local cache (instant)
      final cachedResults = await Future.wait([
        repo.getCachedTransactionsForMonth(now.year, now.month),
        repo.getCachedMonthlySnapshot(now.year, now.month),
        repo.getCachedSummary(),
        ref.read(profileRepositoryProvider).getCachedProfile(),
      ]);
      final cachedMonth = cachedResults[0] as List<TransactionData>;
      final cachedSnapshot = cachedResults[1] as MonthlySpendSnapshot?;
      final cachedSummary = cachedResults[2] as List<Map<String, dynamic>>;
      final cachedProfile = cachedResults[3] as UserProfile?;
      if ((cachedMonth.isNotEmpty || cachedSummary.isNotEmpty) && mounted) {
        setState(() {
          _monthTransactions = cachedMonth;
          _monthSnapshot = cachedSnapshot;
          _summary = cachedSummary;
          _monthlyBudget = cachedProfile?.monthlyBudget ?? 50000;
          _loading = false;
        });
        _checkSpendingAlert();
      }

      // Step 2: Sync only stale tables, then re-read cache if anything changed
      final synced = await VersionSync.instance.syncStale();
      final dataChanged =
          synced.contains(SyncTable.transactions) ||
          synced.contains(SyncTable.profiles);
      if (dataChanged && mounted) {
        final freshResults = await Future.wait([
          repo.getCachedTransactionsForMonth(now.year, now.month),
          repo.getCachedMonthlySnapshot(now.year, now.month),
          repo.getCachedSummary(),
          ref.read(profileRepositoryProvider).getCachedProfile(),
        ]);
        setState(() {
          _monthTransactions = freshResults[0] as List<TransactionData>;
          _monthSnapshot = freshResults[1] as MonthlySpendSnapshot?;
          _summary = freshResults[2] as List<Map<String, dynamic>>;
          _monthlyBudget =
              (freshResults[3] as UserProfile?)?.monthlyBudget ?? 50000;
          _loading = false;
        });
        _checkSpendingAlert();
      } else if (mounted) {
        setState(() => _loading = false);
      }
    } catch (e) {
      debugPrint('Error in dashboard_screen.dart: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError =
              'Could not refresh your data. Check your connection and try again.';
        });
      }
    }
  }

  /// Silent auto-scan on app open — checks for new SMS transactions
  Future<void> _autoScanSms() async {
    if (_autoScanDone) return;
    _autoScanDone = true;
    if (mounted) setState(() => _scanningSms = true);

    try {
      final smsService = SmsService();
      if (!await smsService.hasPermission()) return;

      final detected = await smsService.getRecentTransactions(days: 30);
      if (detected.isEmpty) return;

      final repo = ref.read(transactionRepositoryProvider);
      final filtered = await repo.filterSmsNotYetInLedger(detected);

      if (filtered.isNotEmpty && mounted) {
        setState(() => _pendingSmsCount = filtered.length);
      }
    } catch (e) {
      debugPrint('Error in dashboard_screen.dart: $e');
    } finally {
      if (mounted) setState(() => _scanningSms = false);
    }
  }

  void _checkSpendingAlert() {
    if (_alertShownThisSession) return;
    final spent = _totalSpent;
    if (spent > _monthlyBudget) {
      _alertShownThisSession = true;
      NotificationService().showSpendingAlert(
        totalSpent: spent,
        threshold: _monthlyBudget,
      );
    }
  }

  // This month's transactions
  List<TransactionData> get _thisMonth {
    final now = DateTime.now();
    return _monthTransactions.where((t) {
      final dt = DateTime.tryParse(t.date);
      return dt != null && dt.month == now.month && dt.year == now.year;
    }).toList();
  }

  double get _totalSpent =>
      _monthSnapshot?.totalSpend ??
      _thisMonth.fold(0.0, (sum, t) => sum + t.amount);
  bool get _isMonthEmpty => _thisMonth.isEmpty && _totalSpent <= 0.01;

  // Top categories sorted by total amount
  List<MapEntry<String, double>> get _topCategories {
    final categoryMap = _monthSnapshot?.categoryTotals;
    if (categoryMap == null || categoryMap.isEmpty) {
      final map = <String, double>{};
      for (final t in _thisMonth) {
        map[t.category] = (map[t.category] ?? 0) + t.amount;
      }
      final sorted = map.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      return sorted.take(4).toList();
    }
    final sorted = categoryMap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(4).toList();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colors.surface,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_loadError != null)
              Material(
                color: colors.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
                  child: Row(
                    children: [
                      Icon(
                        Icons.cloud_off_outlined,
                        size: 20,
                        color: colors.onErrorContainer,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _loadError!,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: colors.onErrorContainer,
                            height: 1.3,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _load,
                        child: Text(
                          'Retry',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w700,
                            color: colors.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: _loading
                  ? const DashboardSkeleton()
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildHeroCard(colors),
                            const SizedBox(height: 12),
                            _buildPrimaryActionsRow(colors),
                            const SizedBox(height: 10),
                            _buildAllExpensesEntry(colors),
                            if (_isMonthEmpty) ...[
                              const SizedBox(height: 14),
                              _buildRolloverInsights(colors),
                            ] else ...[
                              const SizedBox(height: 16),
                              _buildInsightCard(colors),
                              const SizedBox(height: 20),
                              _buildSpendingChart(colors),
                              const SizedBox(height: 20),
                              _buildTopMerchants(colors),
                              const SizedBox(height: 24),
                              _buildTopCategories(colors),
                            ],
                          ],
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPrimaryActionsRow(ColorScheme colors) {
    final hasPending = _pendingSmsCount > 0;
    final scanTitle = _scanningSms
        ? 'Scanning...'
        : hasPending
        ? 'Import $_pendingSmsCount'
        : 'Scan Messages';
    final scanSubtitle = _scanningSms
        ? 'Checking SMS'
        : hasPending
        ? 'Review now'
        : 'Auto import';

    return Row(
      children: [
        Expanded(
          child: _compactActionCard(
            colors: colors,
            title: scanTitle,
            subtitle: scanSubtitle,
            icon: Icons.email_rounded,
            accent: colors.primary,
            onTap: () async {
              await context.push('/auto-detect');
              DashboardScreenState._autoScanDone = false;
              reload();
              _autoScanSms();
            },
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _compactActionCard(
            colors: colors,
            title: 'Manual Entry',
            subtitle: 'Add expense',
            icon: Icons.edit_note_rounded,
            accent: colors.secondary,
            onTap: () => context.push('/add-expense'),
          ),
        ),
      ],
    );
  }

  Widget _compactActionCard({
    required ColorScheme colors,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accent,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: PremiumSurfaceCard(
        variant: PremiumSurfaceVariant.dashboard,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        radius: 16,
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: accent),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.manrope(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: colors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
    );
  }

  Widget _buildAllExpensesEntry(ColorScheme colors) {
    return GestureDetector(
      onTap: () => context.push('/history'),
      child: PremiumSurfaceCard(
        variant: PremiumSurfaceVariant.neutral,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        radius: 18,
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.receipt_long_rounded,
                size: 20,
                color: colors.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'All Expenses',
                    style: GoogleFonts.manrope(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: colors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Open full history, search and filters',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: colors.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroCard(ColorScheme colors) {
    if (_isMonthEmpty) {
      return _buildRolloverHero(colors);
    }
    final fmt = NumberFormat('#,##,###', 'en_IN');
    final progress = _monthlyBudget > 0
        ? (_totalSpent / _monthlyBudget).clamp(0.0, 1.5)
        : 0.0;
    final isOver = _totalSpent > _monthlyBudget;
    final remaining = _monthlyBudget - _totalSpent;
    final now = DateTime.now();
    final accent = isOver ? const Color(0xFFFF6B6B) : const Color(0xFF93f2f2);
    return GradientHeroCard(
      fmt: fmt,
      topLeftLabel: DateFormat('MMMM yyyy').format(now).toUpperCase(),
      statusPillText: isOver ? 'Over Budget' : 'On Track',
      statusPillAccentColor: accent,
      metricLabel: 'Total Spent',
      amountValue: _totalSpent,
      progress: progress,
      accentColor: accent,
      footerLeft: '${_thisMonth.length} transactions',
      footerRight: isOver
          ? '₹${fmt.format((-remaining).round())} over'
          : '₹${fmt.format(remaining.round())} remaining',
      backgroundGradient: HeroScreenThemes.dashboardGradient,
      watermark: HeroScreenThemes.dashboardWatermark(),
    );
  }

  Widget _buildRolloverHero(ColorScheme colors) {
    final fmt = NumberFormat('#,##,###', 'en_IN');
    final last = _lastMonthSnapshot;
    final progress = _monthlyBudget > 0
        ? (last.total / _monthlyBudget).clamp(0.0, 1.5)
        : 0.0;
    return GradientHeroCard(
      fmt: fmt,
      topLeftLabel: DateFormat('MMMM yyyy').format(DateTime.now()).toUpperCase(),
      statusPillText: 'Fresh Month',
      statusPillAccentColor: const Color(0xFF93f2f2),
      metricLabel: 'Last Month Spent',
      amountValue: last.total,
      progress: progress,
      accentColor: const Color(0xFF93f2f2),
      footerLeft: '${DateFormat('MMM').format(last.month)}: ${last.txCount} transactions',
      footerRight: 'Budget ₹${fmt.format(_monthlyBudget.round())} ready',
      backgroundGradient: HeroScreenThemes.dashboardGradient,
      watermark: HeroScreenThemes.dashboardWatermark(),
    );
  }

  Widget _buildRolloverInsights(ColorScheme colors) {
    final fmt = NumberFormat('#,##,###', 'en_IN');
    final last = _lastMonthSnapshot;
    final topCatText = last.topCategory == null
        ? 'No category trend from last month yet'
        : 'Top category in ${DateFormat('MMM').format(last.month)}: ${last.topCategory} (₹${fmt.format(last.topAmount.round())})';
    return PremiumSurfaceCard(
      variant: PremiumSurfaceVariant.dashboard,
      radius: 26,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: const Color(0xFF142A6E).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(
                  Icons.auto_awesome,
                  size: 18,
                  color: Color(0xFF142A6E),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Fluid Insights',
                style: GoogleFonts.manrope(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF142A6E),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Fresh month has started. In ${DateFormat('MMMM').format(last.month)}, you spent ₹${fmt.format(last.total.round())} across ${last.txCount} transactions.',
            style: GoogleFonts.inter(
              fontSize: 13,
              color: colors.onSurface,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            topCatText,
            style: GoogleFonts.inter(
              fontSize: 13,
              color: colors.onSurfaceVariant,
              height: 1.35,
            ),
          ),
          if (_pendingSmsCount > 0) ...[
            const SizedBox(height: 6),
            Text(
              'You also have $_pendingSmsCount new SMS transaction${_pendingSmsCount == 1 ? '' : 's'} ready to import.',
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: colors.primary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // Insight card — compares this month vs last month
  Widget _buildInsightCard(ColorScheme colors) {
    if (_monthTransactions.isEmpty && _summary.isEmpty) {
      return const SizedBox.shrink();
    }

    final now = DateTime.now();

    // Find top category this month
    final catMap = <String, double>{};
    for (final t in _thisMonth) {
      catMap[t.category] = (catMap[t.category] ?? 0) + t.amount;
    }
    if (catMap.isEmpty) return const SizedBox.shrink();
    final topCat = catMap.entries.reduce((a, b) => a.value > b.value ? a : b);

    final cat = getCategoryByName(topCat.key);
    // Compare with last month if data is available
    final lastMonth = DateTime(now.year, now.month - 1);
    final lastMonthSame = _summary
        .where((row) {
          final dt = DateTime.tryParse(row['date'] as String? ?? '');
          return dt != null &&
              dt.year == lastMonth.year &&
              dt.month == lastMonth.month &&
              row['category'] == topCat.key;
        })
        .fold<double>(
          0.0,
          (sum, row) => sum + ((row['amount'] as num?)?.toDouble() ?? 0),
        );
    // Only show comparison if we have meaningful last month data
    final diff = lastMonthSame > 100
        ? ((topCat.value - lastMonthSame) / lastMonthSame * 100).round()
        : 0;
    final fmt = NumberFormat('#,##,###', 'en_IN');

    return PremiumSurfaceCard(
      variant: PremiumSurfaceVariant.dashboard,
      padding: const EdgeInsets.all(16),
      radius: 20,
      child: Row(
        children: [
          Text('💡', style: const TextStyle(fontSize: 24)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'You spent ₹${fmt.format(topCat.value.round())} on ${topCat.key}',
                  style: GoogleFonts.manrope(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: colors.onSurface,
                  ),
                ),
                if (diff != 0)
                  Text(
                    '→ ${diff.abs()}% ${diff > 0 ? "higher" : "lower"} than last month',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: diff > 0
                          ? const Color(0xFFe53935)
                          : colors.secondary,
                    ),
                  ),
              ],
            ),
          ),
          Text(cat.emoji, style: const TextStyle(fontSize: 28)),
        ],
      ),
    );
  }

  // Top merchants
  Widget _buildTopMerchants(ColorScheme colors) {
    // Group by notes/merchant
    final merchantMap = <String, double>{};
    for (final t in _thisMonth) {
      final name = t.notes?.isNotEmpty == true ? t.notes! : t.category;
      merchantMap[name] = (merchantMap[name] ?? 0) + t.amount;
    }
    if (merchantMap.isEmpty) return const SizedBox.shrink();

    final sorted = merchantMap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = sorted.take(3).toList();
    final fmt = NumberFormat('#,##,###', 'en_IN');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Top Merchants',
          style: GoogleFonts.manrope(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        ...top.map(
          (e) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: PremiumSurfaceCard(
              variant: PremiumSurfaceVariant.dashboard,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              radius: 18,
              child: Row(
                children: [
                  MerchantIcon(notes: e.key, category: '', size: 36),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      e.key,
                      style: GoogleFonts.manrope(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '₹${fmt.format(e.value.round())}',
                    style: GoogleFonts.manrope(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: colors.onSurface,
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

  Widget _buildSpendingChart(ColorScheme colors) {
    final catMap = <String, double>{};
    for (final t in _thisMonth) {
      catMap[t.category] = (catMap[t.category] ?? 0) + t.amount;
    }
    final sorted = catMap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    if (sorted.isEmpty) {
      return PremiumSurfaceCard(
        variant: PremiumSurfaceVariant.dashboard,
        padding: const EdgeInsets.all(32),
        radius: 24,
        child: Center(
          child: Text(
            'No spending data yet',
            style: GoogleFonts.inter(fontSize: 14, color: colors.outline),
          ),
        ),
      );
    }

    // Build pie sections
    final sections = sorted.take(6).toList();
    final pieSections = sections.map((e) {
      final cat = getCategoryByName(e.key);
      return PieChartSectionData(
        value: e.value,
        color: cat.color,
        radius: 28,
        showTitle: false,
      );
    }).toList();

    return PremiumSurfaceCard(
      variant: PremiumSurfaceVariant.dashboard,
      padding: const EdgeInsets.all(24),
      radius: 24,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.donut_large_rounded,
                size: 18,
                color: colors.secondary,
              ),
              const SizedBox(width: 8),
              Text(
                'Where Your Money Goes',
                style: GoogleFonts.manrope(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Donut chart + center total
          Row(
            children: [
              SizedBox(
                width: 130,
                height: 130,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    PieChart(
                      PieChartData(
                        sections: pieSections,
                        centerSpaceRadius: 42,
                        sectionsSpace: 3,
                        startDegreeOffset: -90,
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '₹${_compactFormat(_totalSpent)}',
                          style: GoogleFonts.manrope(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: colors.onSurface,
                          ),
                        ),
                        Text(
                          'total',
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
              const SizedBox(width: 20),

              // Legend
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: sections.map((e) {
                    final cat = getCategoryByName(e.key);
                    final pct = _totalSpent > 0
                        ? (e.value / _totalSpent * 100).round()
                        : 0;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: cat.color,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${cat.emoji} ${e.key}',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: colors.onSurface,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            '$pct%',
                            style: GoogleFonts.manrope(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _compactFormat(double value) {
    if (value >= 10000000) return '${(value / 10000000).toStringAsFixed(1)}Cr';
    if (value >= 100000) return '${(value / 100000).toStringAsFixed(1)}L';
    if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}K';
    return value.round().toString();
  }

  Widget _buildTopCategories(ColorScheme colors) {
    final cats = _topCategories;
    final fmt = NumberFormat('#,##,###', 'en_IN');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Top Categories',
              style: GoogleFonts.manrope(
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            GestureDetector(
              onTap: () => context.push('/categories'),
              child: Text(
                'View All',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colors.primary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (cats.isEmpty)
          PremiumSurfaceCard(
            variant: PremiumSurfaceVariant.dashboard,
            padding: const EdgeInsets.all(32),
            radius: 20,
            child: Center(
              child: Text(
                'Add expenses to see categories',
                style: GoogleFonts.inter(fontSize: 14, color: colors.outline),
              ),
            ),
          ),
        PremiumSurfaceCard(
          variant: PremiumSurfaceVariant.dashboard,
          padding: EdgeInsets.zero,
          radius: 20,
          child: Column(
            children: cats.asMap().entries.map((mapEntry) {
              final i = mapEntry.key;
              final entry = mapEntry.value;
              final pct = _totalSpent > 0
                  ? (entry.value / _totalSpent * 100).round()
                  : 0;
              final cat = getCategoryByName(entry.key);
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 14,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: cat.color.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Center(
                            child: Text(
                              cat.emoji,
                              style: const TextStyle(fontSize: 20),
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                entry.key,
                                style: GoogleFonts.manrope(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: colors.onSurface,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '$pct% of budget',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '₹${fmt.format(entry.value.round())}',
                          style: GoogleFonts.manrope(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: colors.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (i < cats.length - 1)
                    Divider(
                      height: 1,
                      indent: 72,
                      endIndent: 18,
                      color: colors.outlineVariant.withValues(alpha: 0.1),
                    ),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

class _MonthSnapshot {
  final DateTime month;
  final double total;
  final int txCount;
  final String? topCategory;
  final double topAmount;

  const _MonthSnapshot({
    required this.month,
    required this.total,
    required this.txCount,
    required this.topCategory,
    required this.topAmount,
  });
}
