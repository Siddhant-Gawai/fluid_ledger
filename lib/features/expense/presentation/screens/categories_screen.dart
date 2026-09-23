import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../../core/constants/categories.dart';
import '../../../../core/common_widgets/skeleton_loader.dart';
import '../../../../core/common_widgets/merchant_icon.dart';
import '../../data/transaction_repository.dart';
import '../../data/transaction_projection_service.dart';

class CategoriesScreen extends ConsumerStatefulWidget {
  const CategoriesScreen({super.key});

  @override
  ConsumerState<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends ConsumerState<CategoriesScreen> {
  List<TransactionData> _transactions = [];
  MonthlySpendSnapshot? _snapshot;
  bool _loading = true;
  String? _expandedCategory;

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
      ]);
      if (mounted) {
        setState(() {
          _transactions = results[0] as List<TransactionData>;
          _snapshot = results[1] as MonthlySpendSnapshot?;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Error in categories_screen.dart: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  // All transactions (already filtered by current month from query)
  List<TransactionData> get _thisMonth => _transactions;

  double get _totalSpent =>
      _snapshot?.totalSpend ??
      _transactions.fold(0.0, (sum, tx) => sum + tx.amount);

  // All categories sorted by amount
  List<MapEntry<String, double>> get _categoryTotals {
    final cached = _snapshot?.categoryTotals;
    if (cached == null || cached.isEmpty) {
      final map = <String, double>{};
      for (final t in _thisMonth) {
        map[t.category] = (map[t.category] ?? 0) + t.amount;
      }
      final sorted = map.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      return sorted;
    }
    final sorted = cached.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted;
  }

  // Transactions for a specific category
  List<TransactionData> _txForCategory(String category) {
    return _thisMonth.where((t) => t.category == category).toList();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final fmt = NumberFormat('#,##,###', 'en_IN');

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
          'Category Insights',
          style: GoogleFonts.manrope(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: colors.onSurface,
          ),
        ),
      ),
      body: _loading
          ? const PageSkeleton(rows: 6)
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header description
                  Text(
                    "Your spending footprint across life's essentials. We've analyzed your transactions for the last 30 days.",
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: colors.onSurfaceVariant,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Total monthly outflow
                  Center(
                    child: Column(
                      children: [
                        Text(
                          '₹ ${fmt.format(_totalSpent.round())}',
                          style: GoogleFonts.manrope(
                            fontSize: 36,
                            fontWeight: FontWeight.w800,
                            color: colors.onSurface,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'TOTAL MONTHLY OUTFLOW',
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: colors.onSurfaceVariant,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Category cards
                  ..._categoryTotals.map(
                    (entry) =>
                        _buildCategoryCard(entry.key, entry.value, colors, fmt),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildCategoryCard(
    String categoryName,
    double amount,
    ColorScheme colors,
    NumberFormat fmt,
  ) {
    final cat = getCategoryByName(categoryName);
    final pct = _totalSpent > 0 ? (amount / _totalSpent * 100).round() : 0;
    final isExpanded = _expandedCategory == categoryName;
    final txList = isExpanded
        ? _txForCategory(categoryName)
        : <TransactionData>[];

    // Status label
    String status;
    Color statusColor;
    if (pct >= 30) {
      status = 'High Spend';
      statusColor = const Color(0xFFFF6B6B);
    } else if (pct >= 15) {
      status = 'On Track';
      statusColor = colors.secondary;
    } else {
      status = 'Optimized';
      statusColor = colors.secondary;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: () => setState(
          () => _expandedCategory = isExpanded ? null : categoryName,
        ),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isExpanded
                ? cat.color.withValues(alpha: 0.04)
                : colors.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: isExpanded
                  ? cat.color.withValues(alpha: 0.2)
                  : colors.outlineVariant.withValues(alpha: 0.1),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Category header
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: cat.color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Center(
                      child: Text(
                        cat.emoji,
                        style: const TextStyle(fontSize: 24),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          categoryName,
                          style: GoogleFonts.manrope(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: colors.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$pct% of total',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '₹${fmt.format(amount.round())}',
                        style: GoogleFonts.manrope(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: colors.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          status,
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: statusColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              // Progress bar
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (pct / 100).clamp(0.0, 1.0),
                  backgroundColor: colors.outlineVariant.withValues(
                    alpha: 0.12,
                  ),
                  valueColor: AlwaysStoppedAnimation(cat.color),
                  minHeight: 5,
                ),
              ),

              // Expanded transaction list
              if (isExpanded && txList.isNotEmpty) ...[
                const SizedBox(height: 16),
                Divider(
                  height: 1,
                  color: colors.outlineVariant.withValues(alpha: 0.12),
                ),
                const SizedBox(height: 12),
                Text(
                  '${txList.length} TRANSACTIONS',
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: colors.onSurfaceVariant,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 10),
                ...txList.take(10).map((tx) {
                  final dt = DateTime.tryParse(tx.date);
                  final timeStr = dt != null
                      ? DateFormat('d MMM · h:mm a').format(dt)
                      : '';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        MerchantIcon(
                          brand: tx.brand,
                          notes: tx.notes,
                          category: tx.category,
                          size: 36,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                tx.notes?.isNotEmpty == true
                                    ? tx.notes!
                                    : categoryName,
                                style: GoogleFonts.manrope(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: colors.onSurface,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                timeStr,
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '₹${fmt.format(tx.amount.round())}',
                          style: GoogleFonts.manrope(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: colors.onSurface,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
                if (txList.length > 10)
                  Center(
                    child: Text(
                      '+${txList.length - 10} more',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: colors.primary,
                      ),
                    ),
                  ),
              ],

              // Expand hint
              if (!isExpanded) ...[
                const SizedBox(height: 8),
                Center(
                  child: Icon(
                    Icons.keyboard_arrow_down,
                    size: 18,
                    color: colors.outlineVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
