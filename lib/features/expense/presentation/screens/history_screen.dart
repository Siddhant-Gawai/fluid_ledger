import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../../core/common_widgets/merchant_icon.dart';
import '../../../../core/common_widgets/premium_surface_card.dart';
import '../../../../core/common_widgets/skeleton_loader.dart';
import '../../../../core/constants/categories.dart';
import '../../../../core/database/version_sync.dart';
import '../../../../core/settings/custom_category_service.dart';
import '../../../../core/settings/saved_search_service.dart';
import '../../../../core/sms/merchant_override_service.dart';
import '../../../../core/utils/snackbar_helper.dart';
import '../../../profile/data/profile_repository.dart';
import '../../data/transaction_repository.dart';
import '../../data/transaction_projection_service.dart';

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => HistoryScreenState();
}

class HistoryScreenState extends ConsumerState<HistoryScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _summary = [];
  List<TransactionData> _transactions = [];
  MonthlySpendSnapshot? _monthSnapshot;
  bool _loading = true;
  bool _loadingMonth = false;
  String _searchQuery = '';
  List<TransactionData> _searchResults = [];
  Timer? _searchDebounce;
  List<String> _savedSearches = [];
  String _activeFilter = 'All';
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  double _monthlyBudget = 50000;

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void reload() => _loadInitial();

  /// Load summary (all months) + current month's transactions
  Future<void> _loadInitial() async {
    try {
      final repo = ref.read(transactionRepositoryProvider);

      // 1. Show cached data instantly
      final cachedResults = await Future.wait([
        repo.getCachedSummary(),
        ref.read(profileRepositoryProvider).getCachedProfile(),
        repo.getCachedTransactionsForMonth(
          _selectedMonth.year,
          _selectedMonth.month,
        ),
        repo.getCachedMonthlySnapshot(
          _selectedMonth.year,
          _selectedMonth.month,
        ),
      ]);
      if (mounted) {
        setState(() {
          _summary = cachedResults[0] as List<Map<String, dynamic>>;
          _monthlyBudget =
              (cachedResults[1] as UserProfile?)?.monthlyBudget ?? 50000;
          _transactions = cachedResults[2] as List<TransactionData>;
          _monthSnapshot = cachedResults[3] as MonthlySpendSnapshot?;
          _loading = false;
        });
      }
      final saved = await SavedSearchService.instance.getSavedSearches();
      if (mounted) {
        setState(() => _savedSearches = saved);
      }

      // 2. Sync stale tables, re-read if anything changed
      final synced = await VersionSync.instance.syncStale();
      if ((synced.contains(SyncTable.transactions) ||
              synced.contains(SyncTable.profiles)) &&
          mounted) {
        final freshResults = await Future.wait([
          repo.getCachedSummary(),
          ref.read(profileRepositoryProvider).getCachedProfile(),
          repo.getCachedTransactionsForMonth(
            _selectedMonth.year,
            _selectedMonth.month,
          ),
          repo.getCachedMonthlySnapshot(
            _selectedMonth.year,
            _selectedMonth.month,
          ),
        ]);
        setState(() {
          _summary = freshResults[0] as List<Map<String, dynamic>>;
          _monthlyBudget =
              (freshResults[1] as UserProfile?)?.monthlyBudget ?? 50000;
          _transactions = freshResults[2] as List<TransactionData>;
          _monthSnapshot = freshResults[3] as MonthlySpendSnapshot?;
        });
      }
    } catch (e) {
      debugPrint('Error in history_screen.dart: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Switch to a different month — loads that month's data
  Future<void> _switchMonth(DateTime month) async {
    if (month.year == _selectedMonth.year &&
        month.month == _selectedMonth.month) {
      return;
    }
    setState(() {
      _selectedMonth = month;
      _loadingMonth = true;
      _activeFilter = 'All';
      _searchResults = [];
    });

    try {
      final repo = ref.read(transactionRepositoryProvider);
      final results = await Future.wait([
        repo.getCachedTransactionsForMonth(month.year, month.month),
        repo.getCachedMonthlySnapshot(month.year, month.month),
      ]);
      if (!mounted) return;
      setState(() {
        _transactions = results[0] as List<TransactionData>;
        _monthSnapshot = results[1] as MonthlySpendSnapshot?;
        _loadingMonth = false;
      });
      if (_searchQuery.trim().isNotEmpty) {
        await _runLocalSearch(_searchQuery);
      }
    } catch (e) {
      debugPrint('Error loading month: $e');
      if (mounted) {
        setState(() => _loadingMonth = false);
      }
    }
  }

  /// All unique months — from summary
  List<DateTime> get _availableMonths {
    final months = <DateTime>{};
    for (final s in _summary) {
      final dt = DateTime.tryParse(s['date'] as String? ?? '');
      if (dt != null) months.add(DateTime(dt.year, dt.month));
    }
    final sorted = months.toList()..sort((a, b) => b.compareTo(a));
    return sorted;
  }

  /// Month total — from summary
  double get _monthTotal {
    return _monthSnapshot?.totalSpend ?? 0.0;
  }

  /// All loaded transactions for display (no month filter — show everything)
  List<TransactionData> get _monthTransactions => _transactions;

  List<TransactionData> get _filtered {
    var list = _searchQuery.isNotEmpty ? _searchResults : _transactions;
    if (_activeFilter != 'All') {
      list = list.where((t) => t.category == _activeFilter).toList();
    }
    return list;
  }

  Future<void> _runLocalSearch(String query) async {
    _searchDebounce?.cancel();
    final trimmed = query.trim();
    setState(() => _searchQuery = query);
    if (trimmed.isEmpty) {
      if (mounted) {
        setState(() => _searchResults = []);
      }
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 220), () async {
      final intent = _parseSearchIntent(trimmed);
      final source = await _transactionsForIntent(intent);
      final found = _applyIntentFilter(source, intent);
      if (!mounted) return;
      setState(() => _searchResults = found);
    });
  }

  _SearchIntent _parseSearchIntent(String rawQuery) {
    var q = rawQuery.toLowerCase().trim();
    int? monthOffset;
    if (q.contains('last month')) {
      monthOffset = -1;
      q = q.replaceAll('last month', ' ');
    } else if (q.contains('this month')) {
      monthOffset = 0;
      q = q.replaceAll('this month', ' ');
    }

    double? minAmount;
    double? maxAmount;
    final minMatch = RegExp(
      r'\b(?:above|over|more than|greater than)\s*₹?\s*(\d+(?:\.\d+)?)\b',
    ).firstMatch(q);
    if (minMatch != null) {
      minAmount = double.tryParse(minMatch.group(1)!);
      q = q.replaceFirst(minMatch.group(0)!, ' ');
    }
    final maxMatch = RegExp(
      r'\b(?:below|under|less than)\s*₹?\s*(\d+(?:\.\d+)?)\b',
    ).firstMatch(q);
    if (maxMatch != null) {
      maxAmount = double.tryParse(maxMatch.group(1)!);
      q = q.replaceFirst(maxMatch.group(0)!, ' ');
    }

    String? category;
    for (final c in defaultCategories) {
      final lower = c.name.toLowerCase();
      if (q.contains(lower)) {
        category = c.name;
        q = q.replaceAll(lower, ' ');
        break;
      }
    }

    final merchantQuery = q
        .replaceAll(RegExp(r'[^a-z0-9\s.]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    return _SearchIntent(
      merchantQuery: merchantQuery.isEmpty ? null : merchantQuery,
      category: category,
      minAmount: minAmount,
      maxAmount: maxAmount,
      monthOffset: monthOffset,
    );
  }

  Future<List<TransactionData>> _transactionsForIntent(
    _SearchIntent intent,
  ) async {
    if (intent.monthOffset == null) return _transactions;
    final base = DateTime.now();
    final target = DateTime(base.year, base.month + intent.monthOffset!);
    final repo = ref.read(transactionRepositoryProvider);
    return repo.getCachedTransactionsForMonth(target.year, target.month);
  }

  List<TransactionData> _applyIntentFilter(
    List<TransactionData> source,
    _SearchIntent intent,
  ) {
    final merchantTokens = (intent.merchantQuery ?? '')
        .split(' ')
        .where((e) => e.isNotEmpty)
        .toList();
    return source.where((tx) {
      if (intent.category != null && tx.category != intent.category) {
        return false;
      }
      if (intent.minAmount != null && tx.amount < intent.minAmount!) {
        return false;
      }
      if (intent.maxAmount != null && tx.amount > intent.maxAmount!) {
        return false;
      }
      if (merchantTokens.isEmpty) return true;
      final hay = '${tx.notes ?? ''} ${tx.brand ?? ''} ${tx.category}'
          .toLowerCase();
      for (final token in merchantTokens) {
        if (!hay.contains(token)) return false;
      }
      return true;
    }).toList();
  }

  Future<void> _saveCurrentSearch() async {
    final query = _searchQuery.trim();
    if (query.isEmpty) {
      showInfoSnackBar('Type a search first');
      return;
    }
    await SavedSearchService.instance.saveSearch(query);
    final refreshed = await SavedSearchService.instance.getSavedSearches();
    if (!mounted) return;
    setState(() => _savedSearches = refreshed);
    showSuccessSnackBar('Saved filter');
  }

  Future<void> _removeSavedSearch(String query) async {
    await SavedSearchService.instance.removeSearch(query);
    final refreshed = await SavedSearchService.instance.getSavedSearches();
    if (!mounted) return;
    setState(() => _savedSearches = refreshed);
  }

  // Group transactions by date — with month breakers
  Map<String, List<TransactionData>> get _grouped {
    final map = <String, List<TransactionData>>{};
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    for (final tx in _filtered) {
      final dt = DateTime.tryParse(tx.date);
      String label;
      if (dt == null) {
        label = 'Other';
      } else {
        final txDay = DateTime(dt.year, dt.month, dt.day);
        if (txDay == today) {
          label = 'TODAY, ${DateFormat('d MMM').format(dt).toUpperCase()}';
        } else if (txDay == yesterday) {
          label = 'YESTERDAY, ${DateFormat('d MMM').format(dt).toUpperCase()}';
        } else {
          label = DateFormat('d MMM').format(dt).toUpperCase();
        }
      }
      map.putIfAbsent(label, () => []).add(tx);
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colors.surface,
      appBar: AppBar(
        backgroundColor: colors.surface,
        scrolledUnderElevation: 0,
        title: Row(
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
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: colors.primary,
              ),
            ),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 12),
            decoration: BoxDecoration(
              color: colors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: Icon(
                Icons.notifications_none_rounded,
                color: colors.onSurfaceVariant,
              ),
              onPressed: () {},
            ),
          ),
        ],
      ),
      body: _loading
          ? const HistorySkeleton()
          : RefreshIndicator(
              onRefresh: _loadInitial,
              child: CustomScrollView(
                slivers: [
                  // Month selector + budget health
                  SliverToBoxAdapter(child: _buildMonthSelector(colors)),
                  // Yesterday summary
                  SliverToBoxAdapter(child: _buildYesterdaySummary(colors)),

                  // Search bar
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                      child: PremiumSurfaceCard(
                        variant: PremiumSurfaceVariant.dashboard,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        radius: 20,
                        child: TextField(
                          controller: _searchController,
                          onChanged: _runLocalSearch,
                          style: GoogleFonts.inter(fontSize: 14),
                          decoration: InputDecoration(
                            icon: Icon(
                              Icons.search,
                              color: colors.onSurfaceVariant,
                              size: 20,
                            ),
                            hintText: 'Search merchant, amount, category...',
                            hintStyle: GoogleFonts.inter(
                              fontSize: 14,
                              color: colors.outlineVariant,
                            ),
                            border: InputBorder.none,
                            filled: false,
                            suffixIcon: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_searchQuery.isNotEmpty)
                                  IconButton(
                                    tooltip: 'Clear search',
                                    onPressed: () {
                                      _searchController.clear();
                                      _runLocalSearch('');
                                    },
                                    icon: Icon(
                                      Icons.close,
                                      color: colors.onSurfaceVariant,
                                      size: 20,
                                    ),
                                  ),
                                IconButton(
                                  onPressed: _saveCurrentSearch,
                                  tooltip: 'Save search',
                                  icon: Icon(
                                    Icons.bookmark_add_outlined,
                                    color: colors.onSurfaceVariant,
                                    size: 20,
                                  ),
                                ),
                              ],
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 14,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Filter chips
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 42,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        children: [
                          'All',
                          ..._monthTransactions.map((t) => t.category).toSet(),
                        ].map((f) => _buildChip(f, colors)).toList(),
                      ),
                    ),
                  ),
                  if (_savedSearches.isNotEmpty)
                    SliverToBoxAdapter(
                      child: SizedBox(
                        height: 42,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
                          children: _savedSearches.map((q) {
                            final active =
                                _searchQuery.trim().toLowerCase() ==
                                q.trim().toLowerCase();
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: GestureDetector(
                                onTap: () {
                                  _searchController.text = q;
                                  _runLocalSearch(q);
                                },
                                onLongPress: () => _removeSavedSearch(q),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: active
                                        ? colors.secondary.withValues(
                                            alpha: 0.16,
                                          )
                                        : colors.surfaceContainerLow,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: active
                                          ? colors.secondary.withValues(
                                              alpha: 0.32,
                                            )
                                          : colors.outlineVariant.withValues(
                                              alpha: 0.15,
                                            ),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.bookmark_outline_rounded,
                                        size: 14,
                                        color: active
                                            ? colors.secondary
                                            : colors.onSurfaceVariant,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        q,
                                        style: GoogleFonts.inter(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: active
                                              ? colors.secondary
                                              : colors.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),

                  const SliverToBoxAdapter(child: SizedBox(height: 12)),

                  // Empty state
                  if (_filtered.isEmpty)
                    SliverFillRemaining(
                      child: Center(
                        child: PremiumSurfaceCard(
                          variant: PremiumSurfaceVariant.neutral,
                          radius: 28,
                          padding: const EdgeInsets.all(26),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.receipt_long,
                                size: 56,
                                color: colors.outlineVariant,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No transactions yet',
                                style: GoogleFonts.manrope(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Add an expense to get started',
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  color: colors.outline,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                  // Grouped transactions
                  // Month loading indicator or transaction groups
                  if (_loadingMonth)
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 40),
                        child: Center(
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      ),
                    )
                  else
                    ..._grouped.entries.map(
                      (entry) =>
                          _buildDateGroup(entry.key, entry.value, colors),
                    ),

                  const SliverToBoxAdapter(child: SizedBox(height: 120)),
                ],
              ),
            ),
    );
  }

  Widget _buildYesterdaySummary(ColorScheme colors) {
    final now = DateTime.now();
    final yesterday = DateTime(now.year, now.month, now.day - 1);
    final yesterdayTxs = _transactions.where((t) {
      final dt = DateTime.tryParse(t.date);
      return dt != null &&
          dt.year == yesterday.year &&
          dt.month == yesterday.month &&
          dt.day == yesterday.day;
    }).toList();
    if (yesterdayTxs.isEmpty) return const SizedBox.shrink();
    final total = yesterdayTxs.fold(0.0, (s, t) => s + t.amount);
    final fmt = NumberFormat('#,##,###', 'en_IN');

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: PremiumSurfaceCard(
        variant: PremiumSurfaceVariant.dashboard,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        radius: 18,
        child: Row(
          children: [
            const Text('💡', style: TextStyle(fontSize: 16)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'You spent ₹${fmt.format(total.round())} yesterday',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colors.primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMonthSelector(ColorScheme colors) {
    final fmt = NumberFormat('#,##,###', 'en_IN');
    final months = _availableMonths;
    final isOver = _monthTotal > _monthlyBudget;
    final pct = _monthlyBudget > 0
        ? ((_monthTotal / _monthlyBudget) * 100).round()
        : 0;
    final monthName = DateFormat('MMMM yyyy').format(_selectedMonth);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Month pills
          SizedBox(
            height: 40,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: months.length,
              itemBuilder: (_, i) {
                final m = months[i];
                final isSelected =
                    m.year == _selectedMonth.year &&
                    m.month == _selectedMonth.month;
                // Check budget for this month
                final monthSpent = _summary
                    .where((s) {
                      final dt = DateTime.tryParse(s['date'] as String? ?? '');
                      return dt != null &&
                          dt.year == m.year &&
                          dt.month == m.month;
                    })
                    .fold<double>(
                      0,
                      (sum, s) =>
                          sum + ((s['amount'] as num?)?.toDouble() ?? 0),
                    );
                final exceeded = monthSpent > _monthlyBudget;

                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => _switchMonth(m),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? colors.primary
                            : colors.surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(12),
                        border: isSelected
                            ? null
                            : Border.all(
                                color: colors.outlineVariant.withValues(
                                  alpha: 0.15,
                                ),
                              ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            DateFormat('MMM yy').format(m),
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: isSelected
                                  ? Colors.white
                                  : colors.onSurfaceVariant,
                            ),
                          ),
                          if (exceeded) ...[
                            const SizedBox(width: 5),
                            Container(
                              width: 7,
                              height: 7,
                              decoration: const BoxDecoration(
                                color: Color(0xFFFF6B6B),
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),

          PremiumSurfaceCard(
            variant: isOver
                ? PremiumSurfaceVariant.negative
                : PremiumSurfaceVariant.dashboard,
            radius: 28,
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'LEDGER SNAPSHOT',
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: colors.primary,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  monthName,
                  style: GoogleFonts.manrope(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: colors.onSurface,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  isOver
                      ? 'Budget breached. You are spending above plan this month.'
                      : 'A journal view of where the month is moving.',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: colors.onSurfaceVariant,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: _buildSummaryMetric(
                        colors,
                        label: 'Spent',
                        value: '₹${fmt.format(_monthTotal.round())}',
                        accent: colors.onSurface,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildSummaryMetric(
                        colors,
                        label: isOver ? 'Over budget' : 'Budget left',
                        value: isOver
                            ? '₹${fmt.format((_monthTotal - _monthlyBudget).round())}'
                            : '₹${fmt.format((_monthlyBudget - _monthTotal).round().clamp(0, 999999999))}',
                        accent: isOver
                            ? const Color(0xFFEF6C57)
                            : colors.secondary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildSummaryMetric(
                        colors,
                        label: 'Entries',
                        value: '${_monthTransactions.length}',
                        accent: colors.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  isOver
                      ? 'Exceeded budget by ₹${fmt.format((_monthTotal - _monthlyBudget).round())} ($pct%)'
                      : '${fmt.format(_monthlyBudget.round())} planned · $pct% used',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: isOver ? const Color(0xFFEF6C57) : colors.primary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildSummaryMetric(
    ColorScheme colors, {
    required String label,
    required String value,
    required Color accent,
  }) {
    return PremiumMetricBox(
      label: label,
      value: value,
      labelColor: colors.onSurfaceVariant,
      valueColor: accent,
      backgroundColor: Colors.white.withValues(alpha: 0.64),
    );
  }

  Widget _buildChip(String label, ColorScheme colors) {
    final isActive = _activeFilter == label;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () => setState(() => _activeFilter = label),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: isActive ? colors.primary : colors.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(12),
            border: isActive
                ? null
                : Border.all(
                    color: colors.outlineVariant.withValues(alpha: 0.2),
                  ),
          ),
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isActive ? Colors.white : colors.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showQuickEdit(TransactionData tx) async {
    final id = tx.id?.trim();
    if (id == null || id.isEmpty) return;
    final merchantCtrl = TextEditingController(text: tx.notes ?? '');
    final custom = await CustomCategoryService.instance.getCategories();
    final categories = [
      ...defaultCategories.map((c) => c.name),
      ...custom.where(
        (c) => !defaultCategories.any(
          (base) => base.name.toLowerCase() == c.toLowerCase(),
        ),
      ),
    ];
    var selectedCategory = categories.contains(tx.category)
        ? tx.category
        : (categories.isNotEmpty ? categories.first : tx.category);

    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final colors = Theme.of(ctx).colorScheme;
        return StatefulBuilder(
          builder: (ctx, setInner) => Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 12,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Edit Transaction',
                  style: GoogleFonts.manrope(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: merchantCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Merchant',
                    hintText: 'Optional merchant name',
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: selectedCategory,
                  items: categories
                      .map(
                        (c) =>
                            DropdownMenuItem<String>(value: c, child: Text(c)),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setInner(() => selectedCategory = v);
                  },
                  decoration: const InputDecoration(labelText: 'Category'),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: () async {
                        final ctrl = TextEditingController();
                        await showDialog<void>(
                          context: ctx,
                          builder: (dCtx) => AlertDialog(
                            title: const Text('Add Category'),
                            content: TextField(
                              controller: ctrl,
                              decoration: const InputDecoration(
                                hintText: 'e.g. Pets',
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(dCtx),
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () async {
                                  final name = ctrl.text.trim();
                                  if (name.isEmpty) return;
                                  await CustomCategoryService.instance
                                      .addCategory(name);
                                  if (!dCtx.mounted) return;
                                  if (Navigator.of(dCtx).canPop()) {
                                    Navigator.of(dCtx).pop();
                                  }
                                },
                                child: const Text('Add'),
                              ),
                            ],
                          ),
                        );
                        final latest = await CustomCategoryService.instance
                            .getCategories();
                        final merged = [
                          ...defaultCategories.map((c) => c.name),
                          ...latest.where(
                            (c) => !defaultCategories.any(
                              (base) =>
                                  base.name.toLowerCase() == c.toLowerCase(),
                            ),
                          ),
                        ];
                        setInner(() {
                          categories
                            ..clear()
                            ..addAll(merged);
                          if (!categories.contains(selectedCategory)) {
                            selectedCategory = categories.first;
                          }
                        });
                      },
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Add category'),
                    ),
                    const Spacer(),
                    Text(
                      'Tip: long-press rows to edit',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: colors.outline,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      final merchant = merchantCtrl.text.trim();
                      final repo = ref.read(transactionRepositoryProvider);
                      final updated = TransactionData(
                        id: tx.id,
                        amount: tx.amount,
                        category: selectedCategory,
                        date: tx.date,
                        notes: merchant.isEmpty ? tx.notes : merchant,
                        userId: tx.userId,
                        brand: matchMerchant(
                          merchant.isEmpty ? (tx.notes ?? '') : merchant,
                        )?.name,
                      );
                      await repo.updateTransaction(id, updated);
                      if (merchant.isNotEmpty) {
                        await MerchantOverrideService.instance.setOverride(
                          merchant: merchant,
                          category: selectedCategory,
                        );
                      } else if ((tx.notes ?? '').isNotEmpty) {
                        await MerchantOverrideService.instance.setOverride(
                          merchant: tx.notes!,
                          category: selectedCategory,
                        );
                      }
                      if (!mounted) return;
                      Navigator.of(context).pop();
                      await _loadInitial();
                      showSuccessSnackBar('Transaction updated');
                    },
                    child: const Text('Save'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Keys must be unique in the whole list; index-only keys collide across date groups.
  Key _dismissibleKey(TransactionData tx, String groupLabel, int indexInGroup) {
    final id = tx.id?.trim();
    if (id != null && id.isNotEmpty) return ValueKey('hist_tx_$id');
    return ValueKey(
      'hist_tx_${groupLabel}_${indexInGroup}_${tx.date}_${tx.amount}_${tx.category}_${tx.notes ?? ""}',
    );
  }

  Widget _buildDateGroup(
    String label,
    List<TransactionData> txs,
    ColorScheme colors,
  ) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: colors.onSurfaceVariant,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 10),
            PremiumSurfaceCard(
              variant: PremiumSurfaceVariant.dashboard,
              radius: 26,
              padding: const EdgeInsets.all(12),
              child: Column(
                children: txs.asMap().entries.map((entry) {
                  final i = entry.key;
                  final tx = entry.value;
                  final dt = DateTime.tryParse(tx.date);
                  final timeStr = dt != null
                      ? DateFormat('h:mm a').format(dt)
                      : '';
                  return Column(
                    children: [
                      RepaintBoundary(
                        child: Dismissible(
                          key: _dismissibleKey(tx, label, i),
                          direction: DismissDirection.endToStart,
                          confirmDismiss:
                              (tx.id == null || tx.id!.trim().isEmpty)
                              ? (_) async => false
                              : null,
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 24),
                            decoration: BoxDecoration(
                              color: colors.error,
                              borderRadius: BorderRadius.circular(22),
                            ),
                            child: const Icon(
                              Icons.delete_outline,
                              color: Colors.white,
                            ),
                          ),
                          onDismissed: (_) {
                            final id = tx.id?.trim();
                            if (id == null || id.isEmpty) return;
                            final removed = tx;
                            setState(() {
                              _transactions.removeWhere((t) => t.id == id);
                            });
                            ref
                                .read(transactionRepositoryProvider)
                                .deleteTransaction(id)
                                .catchError((e) {
                                  debugPrint('deleteTransaction: $e');
                                  if (mounted) {
                                    setState(() => _transactions.add(removed));
                                    showErrorSnackBar(
                                      'Could not delete. Check your connection.',
                                    );
                                  }
                                });
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 14,
                            ),
                            child: GestureDetector(
                              onLongPress: () => _showQuickEdit(tx),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 14,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(
                                    alpha: i.isEven ? 0.5 : 0.22,
                                  ),
                                  borderRadius: BorderRadius.circular(22),
                                ),
                                child: Row(
                                  children: [
                                    MerchantIcon(
                                      brand: tx.brand,
                                      notes: tx.notes,
                                      category: tx.category,
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            tx.notes?.isNotEmpty == true
                                                ? tx.notes!
                                                : tx.category,
                                            style: GoogleFonts.manrope(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              color: colors.onSurface,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            '${tx.category} · $timeStr',
                                            style: GoogleFonts.inter(
                                              fontSize: 12,
                                              color: colors.onSurfaceVariant,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Text(
                                      '${tx.category == 'Credit' || tx.category == 'Investment' ? '+' : '-'}₹${NumberFormat('#,##,###.##').format(tx.amount)}',
                                      style: GoogleFonts.manrope(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        color:
                                            tx.category == 'Credit' ||
                                                tx.category == 'Investment'
                                            ? colors.secondary
                                            : const Color(0xFFe53935),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (i < txs.length - 1) const SizedBox(height: 8),
                    ],
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchIntent {
  final String? merchantQuery;
  final String? category;
  final double? minAmount;
  final double? maxAmount;
  final int? monthOffset;

  const _SearchIntent({
    this.merchantQuery,
    this.category,
    this.minAmount,
    this.maxAmount,
    this.monthOffset,
  });
}
