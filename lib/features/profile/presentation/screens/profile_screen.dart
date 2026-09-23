import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../../core/common_widgets/hero_screen_themes.dart';
import '../../../../core/common_widgets/premium_modal.dart';
import '../../../../core/common_widgets/premium_surface_card.dart';
import '../../../../core/common_widgets/skeleton_loader.dart';
import '../../../../core/notifications/notification_service.dart';
import '../../../../core/settings/notification_preferences.dart';
import '../../../../core/utils/snackbar_helper.dart';
import '../../../auth/providers/auth_provider.dart';
import '../../../expense/data/transaction_repository.dart';
import '../../data/profile_repository.dart';

const _avatarOptions = [
  {'color': Color(0xFF24389c), 'icon': Icons.person},
  {'color': Color(0xFF006a6a), 'icon': Icons.face},
  {'color': Color(0xFF1D6B7A), 'icon': Icons.mood},
  {'color': Color(0xFFFF8A65), 'icon': Icons.sentiment_very_satisfied},
  {'color': Color(0xFF313e7e), 'icon': Icons.psychology},
  {'color': Color(0xFF00897B), 'icon': Icons.emoji_emotions},
];

/// Accent line & pills on the blue hero (same as expense card progress).
const _kHeroTealAccent = Color(0xFF93f2f2);

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  UserProfile? _profile;
  bool _loading = true;
  double _thisMonthSpend = 0;
  double _lastMonthSpend = 0;
  int _thisMonthTxCount = 0;
  String? _topCategory;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final repo = ref.read(profileRepositoryProvider);
      final txRepo = ref.read(transactionRepositoryProvider);

      final cached = await repo.getCachedProfile();
      if (mounted) {
        setState(() {
          if (cached != null) _profile = cached;
        });
      }
      final results = await Future.wait([
        repo.getProfile(),
        txRepo.getAllTransactions(),
      ]);
      if (!mounted) return;
      final fresh = results[0] as UserProfile?;
      final allTx = results[1] as List<TransactionData>;
      final insight = _buildInsightStats(allTx);
      setState(() {
        if (fresh != null) _profile = fresh;
        _thisMonthSpend = insight.thisMonthSpend;
        _lastMonthSpend = insight.lastMonthSpend;
        _thisMonthTxCount = insight.thisMonthTxCount;
        _topCategory = insight.topCategory;
        _loading = false;
      });
    } catch (e) {
      debugPrint('Error in profile_screen.dart: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  _ProfileInsightStats _buildInsightStats(List<TransactionData> txs) {
    final now = DateTime.now();
    final thisStart = DateTime(now.year, now.month, 1);
    final nextStart = DateTime(now.year, now.month + 1, 1);
    final lastStart = DateTime(now.year, now.month - 1, 1);

    var thisSpend = 0.0;
    var lastSpend = 0.0;
    var thisCount = 0;
    final catTotals = <String, double>{};

    for (final t in txs) {
      final dt = DateTime.tryParse(t.date);
      if (dt == null) continue;
      if (!dt.isBefore(thisStart) && dt.isBefore(nextStart)) {
        thisSpend += t.amount;
        thisCount += 1;
        catTotals[t.category] = (catTotals[t.category] ?? 0) + t.amount;
      } else if (!dt.isBefore(lastStart) && dt.isBefore(thisStart)) {
        lastSpend += t.amount;
      }
    }

    String? topCategory;
    if (catTotals.isNotEmpty) {
      topCategory = catTotals.entries
          .reduce((a, b) => a.value >= b.value ? a : b)
          .key;
    }

    return _ProfileInsightStats(
      thisMonthSpend: thisSpend,
      lastMonthSpend: lastSpend,
      thisMonthTxCount: thisCount,
      topCategory: topCategory,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    ref.listen<AuthState>(authProvider, (previous, next) {
      if (next == AuthState.phoneEntry) {
        context.go('/auth');
      }
    });

    return Scaffold(
      backgroundColor: colors.surface,
      body: SafeArea(
        bottom: false,
        child: _loading
            ? const ProfileSkeleton()
            : SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildProfileHeader(colors),
                    const SizedBox(height: 14),
                    _buildBudgetStrip(colors),
                    const SizedBox(height: 14),
                    _buildControlsBoard(colors),
                    const SizedBox(height: 14),
                    _buildCuratorInsightCard(colors),
                    const SizedBox(height: 14),
                    _buildDangerZone(colors),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _heroStat({required String label, required String value}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: PremiumMetricBox(
        label: label,
        value: value,
        labelColor: Colors.white.withValues(alpha: 0.58),
        valueColor: Colors.white,
        valueFontSize: 15,
        labelFontSize: 10,
        minHeight: 72,
      ),
    );
  }

  String _maskedPhone(String? phone) {
    final raw = (phone ?? '').trim();
    if (raw.length < 4) return 'Add phone';
    final visible = raw.substring(raw.length - 4);
    return '${'•' * (raw.length - 4)}$visible';
  }

  Widget _buildControlsBoard(ColorScheme colors) {
    return PremiumSurfaceCard(
      variant: PremiumSurfaceVariant.profile,
      radius: 26,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
      child: _buildSettingsSection(colors),
    );
  }

  Widget _buildProfileHeader(ColorScheme colors) {
    final p = _profile;
    final avatarIdx = (p?.avatarIndex ?? 0).clamp(0, _avatarOptions.length - 1);
    final avatarColor = _avatarOptions[avatarIdx]['color'] as Color;
    final avatarIcon = _avatarOptions[avatarIdx]['icon'] as IconData;
    final name = p?.name ?? 'User';
    final phoneOk = (p?.phone ?? '').trim().length >= 10;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: avatarColor.withValues(alpha: 0.18),
              child: Icon(avatarIcon, color: avatarColor, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'The Fluid Ledger',
                style: GoogleFonts.manrope(
                  fontSize: 34 / 2,
                  fontWeight: FontWeight.w800,
                  color: colors.primary,
                ),
              ),
            ),
            IconButton(
              onPressed: _showNotificationSettings,
              icon: Icon(
                Icons.settings_outlined,
                color: colors.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Center(
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 108,
                height: 108,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      Color.lerp(avatarColor, Colors.white, 0.25)!,
                      avatarColor,
                      Color.lerp(avatarColor, Colors.black, 0.2)!,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border.all(color: colors.primary, width: 2),
                ),
                child: Icon(avatarIcon, size: 52, color: Colors.white),
              ),
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: const Color(0xFFB2EBF2),
                    shape: BoxShape.circle,
                    border: Border.all(color: colors.surface, width: 2),
                  ),
                  child: Icon(Icons.verified_rounded, size: 16, color: colors.primary),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          name,
          textAlign: TextAlign.center,
          style: GoogleFonts.manrope(
            fontSize: 38 / 2,
            fontWeight: FontWeight.w800,
            color: colors.onSurface,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          phoneOk ? 'VERIFIED DIGITAL IDENTITY' : 'SETUP YOUR PROFILE',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            fontSize: 13,
            letterSpacing: 1.4,
            fontWeight: FontWeight.w500,
            color: colors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildContactCard(ColorScheme colors) {
    final p = _profile;
    final accent = colors.primary;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.56),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _contactRow(
            colors,
            accent,
            Icons.person_outline_rounded,
            'Name',
            p?.name ?? '—',
          ),
          Divider(
            height: 1,
            thickness: 1,
            indent: 54,
            endIndent: 16,
            color: colors.outlineVariant.withValues(alpha: 0.12),
          ),
          _contactRow(
            colors,
            accent,
            Icons.mail_outline_rounded,
            'Email',
            p?.email ?? '—',
          ),
          Divider(
            height: 1,
            thickness: 1,
            indent: 54,
            endIndent: 16,
            color: colors.outlineVariant.withValues(alpha: 0.12),
          ),
          _contactRow(
            colors,
            accent,
            Icons.phone_android_rounded,
            'Phone',
            p?.phone ?? '—',
            isLast: true,
          ),
        ],
      ),
    );
  }

  Widget _contactRow(
    ColorScheme colors,
    Color accent,
    IconData icon,
    String label,
    String value, {
    bool isLast = false,
  }) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, isLast ? 16 : 14, 16, isLast ? 18 : 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 22, color: accent),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  value,
                  style: GoogleFonts.manrope(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: colors.onSurface,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBudgetStrip(ColorScheme colors) {
    final budget = _profile?.monthlyBudget ?? 50000;
    final fmt = NumberFormat('#,##,###', 'en_IN');

    return Container(
      decoration: BoxDecoration(
        gradient: HeroScreenThemes.profileGradient,
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: colors.primary.withValues(alpha: 0.2),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _showBudgetEditor(colors, budget),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: const Icon(
                        Icons.account_balance_wallet_outlined,
                        size: 24,
                        color: Colors.white,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      'MONTHLY BUDGET',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.4,
                        color: Colors.white.withValues(alpha: 0.82),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  '₹${fmt.format(budget.round())}',
                  style: GoogleFonts.manrope(
                    fontSize: 44 / 2,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Auto-optimized by AI',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.68),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showBudgetEditor(ColorScheme colors, double currentBudget) {
    final controller = TextEditingController(
      text: currentBudget.round().toString(),
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => PremiumSurfaceCard(
        variant: PremiumSurfaceVariant.profile,
        radius: 30,
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
            // Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.outlineVariant.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Set Monthly Budget',
              style: GoogleFonts.manrope(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: colors.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Get notified when your spending crosses this amount.',
              style: GoogleFonts.inter(
                fontSize: 14,
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.62),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                children: [
                  Text(
                    '₹',
                    style: GoogleFonts.manrope(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: colors.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      style: GoogleFonts.manrope(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                      ),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        hintText: '50000',
                        hintStyle: GoogleFonts.manrope(
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          color: colors.outlineVariant,
                        ),
                        filled: false,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Quick presets
            Row(
              children: [25000, 50000, 100000, 200000].map((amt) {
                final fmt = NumberFormat.compact();
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => controller.text = amt.toString(),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.62),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '₹${fmt.format(amt)}',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: LinearGradient(
                    colors: [colors.primary, colors.primaryContainer],
                  ),
                ),
                child: ElevatedButton(
                  onPressed: () async {
                    final newBudget =
                        double.tryParse(controller.text.trim()) ?? 50000;
                    if (newBudget < 1000) return;
                    Navigator.pop(ctx);
                    try {
                      if (_profile != null) {
                        final updated = UserProfile(
                          id: _profile!.id,
                          name: _profile!.name,
                          age: _profile!.age,
                          email: _profile!.email,
                          phone: _profile!.phone,
                          avatarIndex: _profile!.avatarIndex,
                          monthlyBudget: newBudget,
                        );
                        await ref
                            .read(profileRepositoryProvider)
                            .createProfile(updated);
                        showSuccessSnackBar(
                          'Budget updated to ₹${NumberFormat('#,##,###', 'en_IN').format(newBudget.round())}',
                        );
                        _loadProfile();
                      }
                    } catch (e) {
                      showErrorSnackBar('Failed to update budget');
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Text(
                    'Save Budget',
                    style: GoogleFonts.manrope(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsSection(ColorScheme colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 2, 6, 10),
          child: Text(
            'ACCOUNT ECOSYSTEM',
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.6,
              color: colors.onSurfaceVariant,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.56),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
          _buildSettingsTile(
            colors,
            Icons.edit_outlined,
            'Edit Profile',
            () async {
              await context.push('/profile-setup');
              _loadProfile();
            },
          ),
          _buildSettingsTile(
            colors,
            Icons.summarize_outlined,
            'Monthly Report',
            () {
              context.push('/monthly-summary');
            },
          ),
          _buildSettingsTile(colors, Icons.notifications_none_rounded, 'Notifications', _showNotificationSettings),
          _buildSettingsTile(
            colors,
            Icons.lock_outline_rounded,
            'Privacy & Security',
            () {},
          ),
          _buildSettingsTile(
            colors,
            Icons.help_outline_rounded,
            'Help & Support',
            () {},
          ),
          _buildSettingsTile(
            colors,
            Icons.info_outline_rounded,
            'About',
            () {},
          ),
          _buildSettingsTile(
            colors,
            Icons.delete_sweep_outlined,
            'Clear All Transactions',
            () => _confirmClearTransactions(colors),
            showDivider: false,
            isDestructive: true,
          ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _showNotificationSettings() async {
    var reminders = await NotificationPreferences.instance.remindersEnabled();
    var insights = await NotificationPreferences.instance.insightsEnabled();
    var syncAlerts = await NotificationPreferences.instance.syncAlertsEnabled();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: const Text('Reminders'),
                  subtitle: const Text('Daily check-ins and pending payments'),
                  trailing: Switch(
                    value: reminders,
                    onChanged: (v) => setInner(() => reminders = v),
                  ),
                ),
                ListTile(
                  title: const Text('Insights Alerts'),
                  subtitle: const Text('Overspending and trend alerts'),
                  trailing: Switch(
                    value: insights,
                    onChanged: (v) => setInner(() => insights = v),
                  ),
                ),
                ListTile(
                  title: const Text('Sync Alerts'),
                  subtitle: const Text('Import and scan completion updates'),
                  trailing: Switch(
                    value: syncAlerts,
                    onChanged: (v) => setInner(() => syncAlerts = v),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      await NotificationPreferences.instance
                          .setRemindersEnabled(reminders);
                      await NotificationPreferences.instance.setInsightsEnabled(
                        insights,
                      );
                      await NotificationPreferences.instance
                          .setSyncAlertsEnabled(syncAlerts);
                      await NotificationService().scheduleDailyReminder();
                      await NotificationService().scheduleWeeklySummary();
                      if (!mounted) return;
                      Navigator.of(context).pop();
                      showSuccessSnackBar('Notification settings updated');
                    },
                    child: const Text('Save'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _confirmClearTransactions(ColorScheme colors) {
    showDialog(
      context: context,
      builder: (ctx) => PremiumDialog(
        title: 'Clear All Transactions',
        body:
            'This will permanently delete all your transactions. This action cannot be undone.',
        primaryLabel: 'Delete All',
        destructive: true,
        onPrimary: () async {
          Navigator.pop(ctx);
          try {
            await ref
                .read(transactionRepositoryProvider)
                .deleteAllTransactions();
            showSuccessSnackBar('All transactions cleared');
          } catch (e) {
            showErrorSnackBar('Failed: $e');
          }
        },
      ),
    );
  }

  Widget _buildSettingsTile(
    ColorScheme colors,
    IconData icon,
    String title,
    VoidCallback onTap, {
    bool showDivider = true,
    bool isDestructive = false,
  }) {
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: isDestructive ? colors.error : const Color(0xFF0F6F77),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    title,
                    style: GoogleFonts.manrope(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: isDestructive ? colors.error : colors.onSurface,
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: colors.outlineVariant.withValues(alpha: 0.8),
                ),
              ],
            ),
          ),
        ),
        if (showDivider)
          Padding(
            padding: const EdgeInsets.only(left: 58),
            child: Divider(
              height: 1,
              color: colors.outlineVariant.withValues(alpha: 0.1),
            ),
          ),
      ],
    );
  }

  Widget _buildDangerZone(ColorScheme colors) {
    return PremiumSurfaceCard(
      variant: PremiumSurfaceVariant.negative,
      radius: 22,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'SIGN OUT',
          style: GoogleFonts.inter(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: colors.error,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          _buildSignOutButton(colors),
        ],
      ),
    );
  }

  Widget _buildCuratorInsightCard(ColorScheme colors) {
    final fmt = NumberFormat('#,##,##0', 'en_IN');
    final monthName = DateFormat('MMMM').format(DateTime.now());
    final delta = _thisMonthSpend - _lastMonthSpend;
    final deltaAbs = delta.abs();
    final trendText = _lastMonthSpend <= 0
        ? 'You have spent ₹${fmt.format(_thisMonthSpend.round())} in $monthName across $_thisMonthTxCount transactions.'
        : delta < 0
            ? 'You are down by ₹${fmt.format(deltaAbs.round())} vs last month.'
            : delta > 0
                ? 'You are up by ₹${fmt.format(deltaAbs.round())} vs last month.'
                : 'Your spending is flat vs last month.';
    final topCategoryText = _topCategory == null
        ? 'Top category will appear once more expenses are added.'
        : 'Top category this month: $_topCategory.';

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
            '$trendText $topCategoryText',
            style: GoogleFonts.inter(
              fontSize: 13,
              height: 1.45,
              color: colors.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSignOutButton(ColorScheme colors) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () {
          showDialog(
            context: context,
            builder: (ctx) => PremiumDialog(
              title: 'Sign Out',
              body: 'Are you sure you want to sign out?',
              primaryLabel: 'Sign Out',
              destructive: true,
              onPrimary: () {
                Navigator.pop(ctx);
                ref.read(authProvider.notifier).signOut();
              },
            ),
          );
        },
        icon: Icon(Icons.logout_rounded, size: 18, color: colors.error),
        label: Text(
          'Sign Out',
          style: GoogleFonts.manrope(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: colors.error,
          ),
        ),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: colors.error.withValues(alpha: 0.2)),
          backgroundColor: Colors.white.withValues(alpha: 0.52),
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }

  String _formatDate(String isoDate) {
    try {
      final date = DateTime.parse(isoDate);
      const months = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      return '${months[date.month - 1]} ${date.year}';
    } catch (e) {
      debugPrint('Error in profile_screen.dart: $e');
      return '';
    }
  }
}

class _ProfileInsightStats {
  final double thisMonthSpend;
  final double lastMonthSpend;
  final int thisMonthTxCount;
  final String? topCategory;

  const _ProfileInsightStats({
    required this.thisMonthSpend,
    required this.lastMonthSpend,
    required this.thisMonthTxCount,
    required this.topCategory,
  });
}
