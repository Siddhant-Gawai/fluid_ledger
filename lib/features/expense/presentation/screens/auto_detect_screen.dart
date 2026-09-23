import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../../core/common_widgets/hero_screen_themes.dart';
import '../../../../core/common_widgets/merchant_icon.dart';
import '../../../../core/common_widgets/premium_surface_card.dart';
import '../../../../core/common_widgets/skeleton_loader.dart';
import '../../../../core/constants/categories.dart';
import '../../../../core/notifications/notification_service.dart';
import '../../../../core/sms/sms_parser.dart';
import '../../../../core/sms/sms_service.dart';
import '../../../../core/utils/snackbar_helper.dart';
import '../../data/transaction_repository.dart';

class AutoDetectScreen extends ConsumerStatefulWidget {
  const AutoDetectScreen({super.key, this.forcePermissionIntro = false});

  final bool forcePermissionIntro;

  @override
  ConsumerState<AutoDetectScreen> createState() => _AutoDetectScreenState();
}

const _savingCaptions = [
  '🔍 Scanning for duplicates...',
  '🧠 Categorizing your spends...',
  '🚀 Uploading to your ledger...',
  '✨ Almost there, organizing data...',
  '🔐 Securing your transactions...',
];

class _AutoDetectScreenState extends ConsumerState<AutoDetectScreen> {
  final _smsService = SmsService();
  static const int _recentScanDays = 120;
  static const int _deepScanDays = 3650;
  List<ParsedSmsTransaction> _detected = [];
  final Set<int> _selected = {};
  bool _loading = true;
  bool _saving = false;
  bool _permissionDenied = false;
  bool _showPermissionIntro = false;
  bool _deepMode = false;
  int _captionIndex = 0;

  @override
  void initState() {
    super.initState();
    if (widget.forcePermissionIntro) {
      _loading = false;
      _showPermissionIntro = true;
      return;
    }
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      final hasPermission = await _smsService.hasPermission();
      if (!mounted) return;
      if (hasPermission) {
        _scanSms();
        return;
      }
    } catch (_) {
      if (!mounted) return;
    }
    setState(() {
      _loading = false;
      _showPermissionIntro = true;
    });
  }

  Future<void> _scanSms({
    bool deep = false,
    bool includeExisting = false,
    int? deepDays,
  }) async {
    setState(() {
      _loading = true;
      _showPermissionIntro = false;
      _permissionDenied = false;
      _deepMode = deep;
    });
    PermissionStatus status;
    try {
      status = await Permission.sms.request();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _permissionDenied = true;
      });
      return;
    }
    if (!status.isGranted) {
      if (mounted) {
        setState(() {
          _permissionDenied = true;
          _loading = false;
        });
      }
      return;
    }

    final txs = deep
        ? await _smsService.fullRescan(days: deepDays ?? _deepScanDays)
        : await _smsService.getRecentTransactions(days: _recentScanDays);
    if (!mounted) return;
    final repo = ref.read(transactionRepositoryProvider);
    final filtered = includeExisting
        ? txs
        : await repo.filterSmsNotYetInLedger(txs);
    if (!mounted) return;
    if (mounted) {
      setState(() {
        _detected = filtered;
        _selected
          ..clear()
          ..addAll(List.generate(filtered.length, (i) => i));
        _loading = false;
      });
    }
  }

  Future<void> _openDeepScanPicker() async {
    if (_loading || _saving || !mounted) return;
    final choice = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.history_rounded),
              title: const Text('Last 6 months'),
              onTap: () => Navigator.of(ctx).pop(180),
            ),
            ListTile(
              leading: const Icon(Icons.calendar_month_rounded),
              title: const Text('Last 1 year'),
              onTap: () => Navigator.of(ctx).pop(365),
            ),
            ListTile(
              leading: const Icon(Icons.all_inclusive_rounded),
              title: const Text('All history'),
              subtitle: const Text('May take longer'),
              onTap: () => Navigator.of(ctx).pop(_deepScanDays),
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
    if (choice == null) return;
    await _scanSms(deep: true, includeExisting: true, deepDays: choice);
  }

  void _startCaptionRotation() {
    _captionIndex = 0;
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 2));
      if (!_saving || !mounted) return false;
      setState(
        () => _captionIndex = (_captionIndex + 1) % _savingCaptions.length,
      );
      return true;
    });
  }

  Future<void> _confirmSelected() async {
    if (_selected.isEmpty) return;
    setState(() => _saving = true);
    _startCaptionRotation();

    try {
      final repo = ref.read(transactionRepositoryProvider);

      // Build all transactions and check for duplicates (DB + within this batch)
      final toInsert = <TransactionData>[];
      final batchFingerprints = <String>{};
      int skipped = 0;

      for (final i in _selected) {
        if (i < 0 || i >= _detected.length) continue;
        final sms = _detected[i];
        final fp = SmsParser.fingerprint(sms);
        if (batchFingerprints.contains(fp)) {
          skipped++;
          continue;
        }

        final merchantName = sms.merchant.isNotEmpty
            ? sms.merchant
            : 'SMS Transaction';
        final matched = matchMerchant(merchantName);
        final tx = TransactionData(
          amount: sms.amount,
          category: sms.category,
          date: sms.date.toIso8601String(),
          notes: merchantName,
          brand: matched?.name,
        );
        if (toInsert.any((p) => TransactionRepository.likelySameSpend(tx, p))) {
          skipped++;
          continue;
        }
        final duplicate = await repo.isDuplicate(tx);
        if (!duplicate) {
          batchFingerprints.add(fp);
          toInsert.add(tx);
        } else {
          skipped++;
        }
      }

      // Bulk insert all non-duplicate transactions in one call
      if (toInsert.isNotEmpty) {
        await repo.insertMany(toInsert);
      }
      final added = toInsert.length;
      final totalAmount = toInsert.fold<double>(0, (sum, t) => sum + t.amount);

      // Send notification
      if (added > 0) {
        NotificationService().showSyncComplete(
          added: added,
          skipped: skipped,
          totalAmount: totalAmount,
        );
      }

      if (mounted) {
        final msg = skipped > 0
            ? '$added added, $skipped duplicates skipped'
            : '$added transactions added';
        context.pop();
        showSuccessSnackBar(msg);
      }
    } catch (e) {
      if (mounted) {
        showErrorSnackBar('Failed to save: $e');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final fmt = NumberFormat('#,##,###.##', 'en_IN');
    final totalDetected = _selected.fold<double>(
      0,
      (sum, i) => i < _detected.length ? sum + _detected[i].amount : sum,
    );

    return Scaffold(
      backgroundColor: colors.surface,
      appBar: AppBar(
        backgroundColor: colors.surface,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Auto Import',
          style: GoogleFonts.manrope(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: colors.primary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: _loading ? null : _openDeepScanPicker,
            child: Text(
              'Deep Scan',
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: colors.primary,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _saving
          ? _buildSavingOverlay(colors)
          : _loading
          ? const PageSkeleton(rows: 7)
          : _showPermissionIntro
          ? _buildPermissionIntro(colors)
          : _permissionDenied
          ? _buildPermissionDenied(colors)
          : _detected.isEmpty
          ? _buildEmpty(colors)
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
                        decoration: BoxDecoration(
                          gradient: HeroScreenThemes.dashboardGradient,
                          borderRadius: BorderRadius.circular(30),
                          boxShadow: [
                            BoxShadow(
                              color: colors.primary.withValues(alpha: 0.2),
                              blurRadius: 24,
                              offset: const Offset(0, 14),
                            ),
                          ],
                        ),
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: IgnorePointer(
                                child: HeroScreenThemes.dashboardWatermark(),
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'AUTO IMPORT',
                                  style: GoogleFonts.inter(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white.withValues(alpha: 0.68),
                                    letterSpacing: 1.5,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Review detected transactions before they hit the ledger.',
                                  style: GoogleFonts.manrope(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                    height: 1.18,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _deepMode
                                      ? 'Deep scan mode is showing a much wider SMS history, including transactions that may already exist in your ledger.'
                                      : 'We found likely bank spends from your recent messages. Approve what matters and ignore the noise.',
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    color: Colors.white.withValues(alpha: 0.74),
                                    height: 1.45,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _heroStat(
                                        'Selected',
                                        '${_selected.length}',
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: _heroStat(
                                        'Detected',
                                        '${_detected.length}',
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: _heroStat(
                                        'Value',
                                        '₹${fmt.format(totalDetected.round())}',
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      PremiumSurfaceCard(
                        variant: PremiumSurfaceVariant.dashboard,
                        radius: 24,
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  _selectionChip(
                                    colors,
                                    label: 'Select All',
                                    active: true,
                                    onTap: () => setState(() {
                                      _selected.addAll(
                                        List.generate(_detected.length, (i) => i),
                                      );
                                    }),
                                  ),
                                  const SizedBox(width: 10),
                                  _selectionChip(
                                    colors,
                                    label: 'Deselect All',
                                    onTap: () => setState(() => _selected.clear()),
                                  ),
                                  const SizedBox(width: 10),
                                  _selectionChip(
                                    colors,
                                    label: 'Deep Scan',
                                    onTap: _openDeepScanPicker,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),
                            Align(
                              alignment: Alignment.centerRight,
                              child: Text(
                                '${_selected.length}/${_detected.length} selected',
                                style: GoogleFonts.manrope(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: colors.onSurface,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
                // Transaction list
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    itemCount: _detected.length,
                    itemBuilder: (context, index) =>
                        _buildTxCard(index, colors, fmt),
                  ),
                ),
                // Bottom action bar
                _buildBottomBar(colors),
              ],
            ),
    );
  }

  Widget _buildSavingOverlay(ColorScheme colors) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Animated loader
            SizedBox(
              width: 80,
              height: 80,
              child: CircularProgressIndicator(
                strokeWidth: 4,
                color: colors.primary,
                backgroundColor: colors.primaryContainer.withValues(alpha: 0.2),
              ),
            ),
            const SizedBox(height: 36),
            Text(
              'Syncing Transactions',
              style: GoogleFonts.manrope(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: colors.onSurface,
              ),
            ),
            const SizedBox(height: 16),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              child: Text(
                _savingCaptions[_captionIndex],
                key: ValueKey(_captionIndex),
                style: GoogleFonts.inter(
                  fontSize: 15,
                  color: colors.onSurfaceVariant,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 32),
            Text(
              '${_selected.length} transactions',
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: colors.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _heroStat(String label, String value) {
    return PremiumMetricBox(
      label: label,
      value: value,
      labelColor: Colors.white.withValues(alpha: 0.7),
      valueColor: Colors.white,
      backgroundColor: Colors.white.withValues(alpha: 0.12),
      valueFontSize: 17,
    );
  }

  Widget _selectionChip(
    ColorScheme colors, {
    required String label,
    required VoidCallback onTap,
    bool active = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: active
              ? colors.primary.withValues(alpha: 0.1)
              : Colors.white.withValues(alpha: 0.58),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: active ? colors.primary : colors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget _buildTxCard(int index, ColorScheme colors, NumberFormat fmt) {
    final tx = _detected[index];
    final isSelected = _selected.contains(index);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: () {
          setState(() {
            if (isSelected) {
              _selected.remove(index);
            } else {
              _selected.add(index);
            }
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFFF3F5FF)
                : Colors.white.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected
                  ? colors.primary.withValues(alpha: 0.3)
                  : colors.outlineVariant.withValues(alpha: 0.1),
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              // Checkbox
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: isSelected ? colors.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(7),
                  border: isSelected
                      ? null
                      : Border.all(color: colors.outlineVariant, width: 1.5),
                ),
                child: isSelected
                    ? const Icon(Icons.check, color: Colors.white, size: 16)
                    : null,
              ),
              const SizedBox(width: 14),
              // Icon — uses SVG logo if brand matches
              MerchantIcon(
                notes: tx.merchant,
                category: tx.category,
                brand: matchMerchant(tx.merchant)?.name,
              ),
              const SizedBox(width: 14),
              // Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tx.merchant.isEmpty ? 'Transaction' : tx.merchant,
                      style: GoogleFonts.manrope(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: colors.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: getCategoryByName(
                              tx.category,
                            ).color.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            tx.category,
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: getCategoryByName(tx.category).color,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          DateFormat('h:mm a').format(tx.date),
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
              Text(
                '\u20B9${fmt.format(tx.amount)}',
                style: GoogleFonts.manrope(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: colors.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar(ColorScheme colors) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        MediaQuery.of(context).padding.bottom + 16,
      ),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.96),
        border: Border(
          top: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.1)),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: double.infinity,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  colors: [colors.secondary, const Color(0xFF00897B)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: colors.secondary.withValues(alpha: 0.3),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: ElevatedButton(
                onPressed: _saving || _selected.isEmpty
                    ? null
                    : _confirmSelected,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  disabledBackgroundColor: Colors.transparent,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: _saving
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.check_circle_outline,
                            color: Colors.white,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              'Confirm ${_selected.length} Transactions',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.manrope(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () => context.pop(),
            child: Text(
              'IGNORE & GO BACK',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: colors.onSurfaceVariant,
                letterSpacing: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionDenied(ColorScheme colors) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Icon container
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(28),
              ),
              child: Icon(
                Icons.mark_chat_read_outlined,
                size: 44,
                color: colors.primary,
              ),
            ),
            const SizedBox(height: 28),

            Text(
              'SMS Permission Required',
              style: GoogleFonts.manrope(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: colors.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'We need SMS access to auto-detect your bank transactions. Your messages are processed on-device and never leave your phone.',
              style: GoogleFonts.inter(
                fontSize: 14,
                color: colors.onSurfaceVariant,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),

            // Trust badges
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: colors.secondary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock_outline, size: 16, color: colors.secondary),
                  const SizedBox(width: 8),
                  Text(
                    '100% Private · On-Device Only',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colors.secondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // Grant permission button
            SizedBox(
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
                child: ElevatedButton(
                  onPressed: () async {
                    setState(() => _permissionDenied = false);
                    _scanSms();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.shield_outlined,
                        size: 20,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Grant SMS Access',
                        style: GoogleFonts.manrope(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Open settings fallback
            TextButton(
              onPressed: () => openAppSettings(),
              child: Text(
                'Open Settings Instead',
                style: GoogleFonts.inter(
                  fontSize: 14,
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

  Widget _buildPermissionIntro(ColorScheme colors) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
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
                Icons.auto_awesome_outlined,
                size: 44,
                color: colors.primary,
              ),
            ),
            const SizedBox(height: 28),
            Text(
              'Review SMS Before Import',
              style: GoogleFonts.manrope(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: colors.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Smart Sync scans recent bank messages on this device, suggests likely expenses, and lets you approve each one before it touches your ledger.',
              style: GoogleFonts.inter(
                fontSize: 14,
                color: colors.onSurfaceVariant,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: colors.secondary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                'Private by default: parsing happens on-device and only confirmed transactions are saved.',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colors.secondary,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
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
                child: ElevatedButton(
                  onPressed: _scanSms,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.lock_open_outlined,
                        size: 20,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Continue to SMS Permission',
                        style: GoogleFonts.manrope(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () => context.pop(),
              child: Text(
                'Not now',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty(ColorScheme colors) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline, size: 64, color: colors.secondary),
            const SizedBox(height: 20),
            Text(
              'All caught up!',
              style: GoogleFonts.manrope(
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _deepMode
                  ? 'No transactions found in deep scan history.'
                  : 'No new bank transactions found in your recent SMS messages.',
              style: GoogleFonts.inter(
                fontSize: 14,
                color: colors.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: _openDeepScanPicker,
              icon: const Icon(Icons.manage_search_rounded, size: 18),
              label: Text(
                'Run Deep Scan',
                style: GoogleFonts.manrope(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
