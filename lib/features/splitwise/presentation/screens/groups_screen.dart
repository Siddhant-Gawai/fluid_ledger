import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../../core/common_widgets/gradient_hero_card.dart';
import '../../../../core/common_widgets/hero_screen_themes.dart';
import '../../../../core/common_widgets/premium_modal.dart';
import '../../../../core/common_widgets/premium_surface_card.dart';
import '../../../../core/common_widgets/skeleton_loader.dart';
import '../../../../core/supabase/supabase_config.dart';
import '../../../../core/database/local_db.dart';
import '../../../../core/database/version_sync.dart';
import '../../../../core/utils/phone_utils.dart';
import '../../../../core/utils/snackbar_helper.dart';
import '../../../profile/data/profile_repository.dart';
import '../../data/splitwise_models.dart';
import '../../data/splitwise_projection_service.dart';
import '../../data/splitwise_realtime_service.dart';
import '../../data/splitwise_repository.dart';

const _groupTypes = [
  {
    'type': 'trip',
    'emoji': '✈️',
    'label': 'Trip',
    'icon': Icons.flight_takeoff_rounded,
  },
  {
    'type': 'roommates',
    'emoji': '🏠',
    'label': 'Roommates',
    'icon': Icons.home_rounded,
  },
  {
    'type': 'couple',
    'emoji': '❤️',
    'label': 'Couple',
    'icon': Icons.favorite_rounded,
  },
  {
    'type': 'friends',
    'emoji': '👥',
    'label': 'Friends',
    'icon': Icons.people_rounded,
  },
  {
    'type': 'family',
    'emoji': '👨‍👩‍👧‍👦',
    'label': 'Family',
    'icon': Icons.family_restroom_rounded,
  },
  {
    'type': 'other',
    'emoji': '📋',
    'label': 'Other',
    'icon': Icons.receipt_long_rounded,
  },
];

class GroupsScreen extends ConsumerStatefulWidget {
  const GroupsScreen({super.key});

  @override
  ConsumerState<GroupsScreen> createState() => GroupsScreenState();
}

class GroupsScreenState extends ConsumerState<GroupsScreen> {
  List<SplitGroup> _groups = [];
  Set<String> _archivedIds = {};
  Set<String> _pinnedGroupIds = {};
  bool _loading = true;
  bool _balancesLoaded = false;
  double _totalYouOwe = 0;
  double _totalOwedToYou = 0;
  final Map<String, double> _groupBalances = {};
  final Map<String, SplitwiseGroupSummary> _groupSummaries = {};

  List<SplitGroup> get _activeGroups => _groups
      .where((g) => g.id != null && !_archivedIds.contains(g.id!))
      .toList();

  List<SplitGroup> get _previewGroups {
    final active = _activeGroups;
    final pinned = active.where((g) => _pinnedGroupIds.contains(g.id)).toList();
    if (pinned.isNotEmpty) return pinned.take(2).toList();
    return active.take(2).toList();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> openAddSplitExpenseFlow() async {
    if (_loading) {
      await _load();
      if (!mounted) return;
    }
    final groups = _activeGroups;
    if (groups.isEmpty) {
      showInfoSnackBar('Create a group first');
      final colors = Theme.of(context).colorScheme;
      _showCreateGroup(colors);
      return;
    }

    final selected = await showModalBottomSheet<SplitGroup>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final colors = Theme.of(ctx).colorScheme;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: Text(
                    'Choose a group',
                    style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
                  ),
                  subtitle: const Text('Add split expense to selected group'),
                ),
                const SizedBox(height: 4),
                ...groups.take(8).map((g) {
                  final id = g.id!;
                  final net = _groupBalances[id] ?? 0;
                  final subtitle = net.abs() <= 0.5
                      ? 'No pending balance'
                      : net > 0
                      ? 'You are owed ₹${net.round()}'
                      : 'You owe ₹${net.abs().round()}';
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: colors.primary.withValues(alpha: 0.12),
                      child: Text(
                        (g.name.isNotEmpty ? g.name[0] : '?').toUpperCase(),
                        style: GoogleFonts.manrope(
                          fontWeight: FontWeight.w700,
                          color: colors.primary,
                        ),
                      ),
                    ),
                    title: Text(g.name),
                    subtitle: Text(subtitle),
                    onTap: () => Navigator.of(ctx).pop(g),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
    if (!mounted || selected?.id == null) return;
    context.push('/group/${selected!.id}?add=1');
  }

  bool _forceCloud = false;

  Future<void> _load() async {
    try {
      final repo = ref.read(splitwiseRepositoryProvider);
      final projection = ref.read(splitwiseProjectionServiceProvider);
      final uid = ref.read(supabaseClientProvider).auth.currentUser?.id;

      Future<({Set<String> archived, Set<String> pinned})>
      loadLocalPrefs() async {
        if (uid == null) return (archived: <String>{}, pinned: <String>{});
        final archived = await LocalDB.instance.getArchivedSplitGroupIds(uid);
        final pinned = await LocalDB.instance.getPinnedItemIds(
          userId: uid,
          itemType: 'split_group',
        );
        return (archived: archived, pinned: pinned);
      }

      var nextGroups = _groups;

      if (!_forceCloud) {
        final cached = await repo.getCachedGroups();
        if (cached.isNotEmpty) nextGroups = cached;
      }

      final synced = await VersionSync.instance.syncStale();
      final groupsChanged =
          _forceCloud ||
          synced.contains(SyncTable.splitGroups) ||
          synced.contains(SyncTable.groupMembers);

      if (groupsChanged || nextGroups.isEmpty) {
        nextGroups = await repo.getGroups();
      }

      final prefs = await loadLocalPrefs();
      if (!mounted) return;
      setState(() {
        _groups = nextGroups;
        _archivedIds = prefs.archived;
        _pinnedGroupIds = prefs.pinned;
        _loading = false;
        _balancesLoaded = false;
      });
      _forceCloud = false;

      await _loadBalances(_activeGroups, projection);
    } catch (e) {
      debugPrint('Failed to load groups: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _togglePinGroup(SplitGroup g) async {
    final id = g.id;
    if (id == null) return;
    final uid = ref.read(supabaseClientProvider).auth.currentUser?.id;
    if (uid == null) return;
    try {
      await LocalDB.instance.setPinnedItem(
        userId: uid,
        itemType: 'split_group',
        itemId: id,
        pinned: !_pinnedGroupIds.contains(id),
      );
      final next = await LocalDB.instance.getPinnedItemIds(
        userId: uid,
        itemType: 'split_group',
      );
      if (!mounted) return;
      setState(() => _pinnedGroupIds = next);
    } catch (e) {
      showInfoSnackBar(e.toString().replaceFirst('StateError: ', ''));
    }
  }

  Future<void> _loadBalances(
    List<SplitGroup> groups,
    SplitwiseProjectionService projection,
  ) async {
    try {
      final cached = await projection.getCachedSummaries();
      if (cached.isNotEmpty) {
        double youOwe = 0, owedToYou = 0;
        final balances = <String, double>{};
        for (final g in groups) {
          final b = cached[g.id];
          if (b != null) {
            youOwe += b.youOwe;
            owedToYou += b.owedToYou;
            balances[g.id!] = b.net;
          }
        }
        if (mounted) {
          setState(() {
            _totalYouOwe = youOwe;
            _totalOwedToYou = owedToYou;
            _groupBalances
              ..clear()
              ..addAll(balances);
            _groupSummaries
              ..clear()
              ..addAll(cached);
            _balancesLoaded = true;
          });
        }
      }
    } catch (e) {
      debugPrint('Cached balances read failed: $e');
    }

    () async {
      try {
        await projection.refreshDirtyGroups();
        await projection.refreshGroupsFromRemote(
          groups.map((g) => g.id).whereType<String>(),
        );
        final refreshed = await projection.getCachedSummaries();

        double youOwe = 0, owedToYou = 0;
        final balances = <String, double>{};
        for (final g in groups) {
          final summary = refreshed[g.id];
          if (summary == null) continue;
          youOwe += summary.youOwe;
          owedToYou += summary.owedToYou;
          balances[g.id!] = summary.net;
        }

        if (!mounted) return;
        setState(() {
          _totalYouOwe = youOwe;
          _totalOwedToYou = owedToYou;
          _groupBalances
            ..clear()
            ..addAll(balances);
          _balancesLoaded = true;
        });
      } catch (e) {
        debugPrint('Projection refresh failed: $e');
      }
    }();
  }

  void _showCreateGroup(ColorScheme colors) {
    final nameController = TextEditingController();
    String selectedType = 'friends';
    String selectedEmoji = '👥';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => PremiumSheetContainer(
          variant: PremiumSurfaceVariant.split,
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
                'New Group',
                style: GoogleFonts.manrope(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 20),

              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _groupTypes.map((gt) {
                  final isSelected = selectedType == gt['type'];
                  return GestureDetector(
                    onTap: () => setModalState(() {
                      selectedType = gt['type'] as String;
                      selectedEmoji = gt['emoji'] as String;
                    }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? colors.primary.withValues(alpha: 0.1)
                            : colors.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            gt['emoji'] as String,
                            style: const TextStyle(fontSize: 18),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            gt['label'] as String,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: isSelected
                                  ? colors.primary
                                  : colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),

              TextField(
                controller: nameController,
                autofocus: true,
                style: GoogleFonts.manrope(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                decoration: InputDecoration(
                  hintText: 'Group name (e.g. Goa Trip)',
                  hintStyle: GoogleFonts.inter(
                    fontSize: 15,
                    color: colors.outlineVariant,
                  ),
                  filled: true,
                  fillColor: colors.surfaceContainerLow,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 16,
                  ),
                ),
              ),
              const SizedBox(height: 24),

              GestureDetector(
                onTap: () async {
                  final name = nameController.text.trim();
                  if (name.isEmpty) return;
                  Navigator.pop(ctx);
                  try {
                    final repo = ref.read(splitwiseRepositoryProvider);
                    final client = ref.read(supabaseClientProvider);
                    final userId = client.auth.currentUser!.id;
                    final userPhone = normalizePhone(
                      client.auth.currentUser?.phone,
                    );
                    final profile = await ref
                        .read(profileRepositoryProvider)
                        .getCachedProfile();
                    final displayName = profile?.name ?? 'Me';
                    final group = await repo.createGroup(
                      SplitGroup(
                        name: name,
                        type: selectedType,
                        emoji: selectedEmoji,
                        createdBy: userId,
                      ),
                    );
                    await repo.addMember(
                      GroupMember(
                        groupId: group.id!,
                        name: displayName,
                        userId: userId,
                        phone: userPhone,
                      ),
                    );
                    await _load();
                  } catch (e) {
                    debugPrint('Create group failed: $e');
                    showErrorSnackBar(
                      'Could not create group. Check your connection.',
                    );
                  }
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 18),
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
                  child: Center(
                    child: Text(
                      'Create Group',
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
      ),
    );
  }

  void _confirmDeleteGroup(SplitGroup group, ColorScheme colors) {
    showDialog(
      context: context,
      builder: (ctx) => PremiumDialog(
        title: 'Delete Group',
        body:
            'Delete "${group.name}"? All expenses, splits, and settlements will be permanently removed.',
        primaryLabel: 'Delete',
        destructive: true,
        onPrimary: () async {
          Navigator.pop(ctx);
          try {
            await ref.read(splitwiseRepositoryProvider).deleteGroup(group.id!);
            showSuccessSnackBar('"${group.name}" deleted');
            _load();
          } catch (e) {
            debugPrint('Delete group failed: $e');
            showErrorSnackBar('Could not delete group. Try again.');
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(splitwiseRealtimeBootstrapProvider);
    ref.listen<AsyncValue<SplitwiseInvalidation>>(
      splitwiseRealtimeEventsProvider,
      (_, next) {
        next.whenData((event) {
          if (!mounted) return;
          if (event.groupsChanged ||
              event.groupIds.any(
                (groupId) => _groups.any((group) => group.id == groupId),
              )) {
            _load();
          }
        });
      },
    );
    final colors = Theme.of(context).colorScheme;
    final fmt = NumberFormat('#,##,###', 'en_IN');

    return Scaffold(
      backgroundColor: colors.surface,
      body: SafeArea(
        bottom: false,
        child: _loading
            ? _buildLoadingShell(fmt)
            : RefreshIndicator(
                onRefresh: _load,
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                        child: _buildSplitHero(fmt),
                      ),
                    ),
                    if (_groups.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: _buildEmptyBody(colors),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
                        sliver: SliverList(
                          delegate: SliverChildListDelegate([
                            _buildOverviewBoard(colors, fmt),
                            const SizedBox(height: 24),
                            _buildGroupsBoard(colors, fmt),
                          ]),
                        ),
                      ),
                  ],
                ),
              ),
      ),
    );
  }

  /// Same gradient hero card as Dashboard / Goals — headline is net balance across groups.
  Widget _buildSplitHero(NumberFormat fmt) {
    final owed = _totalOwedToYou;
    final owe = _totalYouOwe;
    final net = owed - owe;
    final netAbs = net.abs();
    final flow = owed + owe;
    final progress = flow > 0.001 ? (owed / flow).clamp(0.0, 1.0) : 0.0;

    final settled =
        _balancesLoaded && netAbs < 0.5 && (flow < 0.5 || _groups.isEmpty);
    final favorable = net >= 0;
    final accent = favorable
        ? const Color(0xFF93f2f2)
        : const Color(0xFFFF6B6B);

    final String pill;
    if (!_balancesLoaded && _groups.isNotEmpty) {
      pill = 'Syncing';
    } else if (_groups.isEmpty) {
      pill = 'Get started';
    } else if (settled) {
      pill = 'All square';
    } else if (favorable) {
      pill = 'In your favor';
    } else {
      pill = 'Settle up';
    }

    final footerLeft = _groups.isEmpty
        ? 'No groups yet'
        : (_archivedIds.isNotEmpty
              ? '${_activeGroups.length} active · ${_archivedIds.length} archived'
              : '${_groups.length} ${_groups.length == 1 ? 'group' : 'groups'}');

    final String footerRight;
    if (!_balancesLoaded && _groups.isNotEmpty) {
      footerRight = 'Updating balances…';
    } else if (_groups.isEmpty) {
      footerRight = 'Tap below to create';
    } else {
      footerRight =
          'Owed ₹${fmt.format(owed.round())} · Owe ₹${fmt.format(owe.round())}';
    }

    return GradientHeroCard(
      fmt: fmt,
      loading: !_balancesLoaded && _groups.isNotEmpty,
      backgroundGradient: HeroScreenThemes.splitGradient,
      watermark: HeroScreenThemes.splitWatermark(),
      topLeftLabel: 'SPLIT',
      statusPillText: pill,
      statusPillAccentColor: accent,
      metricLabel: 'Net balance',
      metricHint: (!_balancesLoaded || settled || _groups.isEmpty)
          ? null
          : '· simplified debts',
      amountValue: netAbs,
      progress: progress,
      accentColor: accent,
      footerLeft: footerLeft,
      footerRight: footerRight,
    );
  }

  Widget _buildLoadingShell(NumberFormat fmt) {
    const dummyAccent = Color(0xFF93f2f2);
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GradientHeroCard(
            fmt: fmt,
            loading: true,
            backgroundGradient: HeroScreenThemes.splitGradient,
            watermark: HeroScreenThemes.splitWatermark(),
            topLeftLabel: '',
            statusPillText: '',
            statusPillAccentColor: dummyAccent,
            metricLabel: '',
            amountValue: 0,
            progress: 0,
            accentColor: dummyAccent,
            footerLeft: '',
            footerRight: '',
          ),
          const SizedBox(height: 20),
          ShimmerWrap(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _balanceStatCardSkeleton(context)),
                const SizedBox(width: 12),
                Expanded(child: _balanceStatCardSkeleton(context)),
              ],
            ),
          ),
          const SizedBox(height: 20),
          ShimmerWrap(
            child: Column(
              children: List.generate(
                4,
                (i) => Padding(
                  padding: EdgeInsets.only(bottom: i == 3 ? 0 : 10),
                  child: SkeletonBox(
                    width: double.infinity,
                    height: 60,
                    radius: 14,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Balance stats (paired white cards — shadow only, same feel as Goals list cards) ──
  Widget _balanceStatCardSkeleton(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return PremiumSurfaceCard(
      variant: PremiumSurfaceVariant.split,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      radius: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 10,
            width: 84,
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 10),
          Container(
            height: 26,
            width: 96,
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBalancePills(ColorScheme colors, NumberFormat fmt) {
    final oweRounded = _totalYouOwe.round();
    final owedRounded = _totalOwedToYou.round();

    if (!_balancesLoaded) {
      return ShimmerWrap(
        child: Container(
          height: 74,
          decoration: BoxDecoration(
            color: colors.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(22),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFFFFF), Color(0xFFF7F8FD)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: colors.outlineVariant.withValues(alpha: 0.16),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: _inlineBalanceMetric(
              label: 'You are owed',
              value: '₹${fmt.format(owedRounded)}',
              accent: colors.secondary,
              align: CrossAxisAlignment.center,
            ),
          ),
          Container(
            width: 1,
            height: 34,
            color: colors.outlineVariant.withValues(alpha: 0.2),
          ),
          Expanded(
            child: _inlineBalanceMetric(
              label: 'You owe',
              value: '₹${fmt.format(oweRounded)}',
              accent: colors.error,
              align: CrossAxisAlignment.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewBoard(ColorScheme colors, NumberFormat fmt) {
    final activeCount = _activeGroups.length;
    final settledCount = _activeGroups.where((g) {
      final summary = g.id == null ? null : _groupSummaries[g.id];
      final hasExpenses = (summary?.expenseCount ?? 0) > 0;
      final balance = _groupBalances[g.id] ?? 0;
      return hasExpenses && balance.abs() <= 0.5;
    }).length;
    final pendingCount = _activeGroups.where((g) {
      final summary = g.id == null ? null : _groupSummaries[g.id];
      final hasExpenses = (summary?.expenseCount ?? 0) > 0;
      final balance = _groupBalances[g.id] ?? 0;
      return hasExpenses && balance.abs() > 0.5;
    }).length;

    return PremiumSurfaceCard(
      variant: PremiumSurfaceVariant.split,
      radius: 26,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'BALANCE BOARD',
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: colors.primary,
                        letterSpacing: 1.4,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _groups.isEmpty
                          ? 'Shared balances will show up here.'
                          : 'Quick view of your split position.',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: colors.onSurfaceVariant,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              if (_balancesLoaded && _totalYouOwe > 0)
                _buildSettleUpButton(colors, compact: true),
            ],
          ),
          const SizedBox(height: 12),
          _buildBalancePills(colors, fmt),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.64),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: colors.outlineVariant.withValues(alpha: 0.14),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _compactStatusMetric(
                    colors,
                    label: 'Active',
                    value: '$activeCount',
                    accent: colors.primary,
                  ),
                ),
                _statusDivider(colors),
                Expanded(
                  child: _compactStatusMetric(
                    colors,
                    label: 'Pending',
                    value: '$pendingCount',
                    accent: const Color(0xFFEF6C57),
                  ),
                ),
                _statusDivider(colors),
                Expanded(
                  child: _compactStatusMetric(
                    colors,
                    label: 'Settled',
                    value: '$settledCount',
                    accent: const Color(0xFF0F766E),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _compactStatusMetric(
    ColorScheme colors, {
    required String label,
    required String value,
    required Color accent,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: GoogleFonts.manrope(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: accent,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: colors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _statusDivider(ColorScheme colors) {
    return Container(
      width: 1,
      height: 28,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: colors.outlineVariant.withValues(alpha: 0.2),
    );
  }

  Widget _buildGroupsBoard(ColorScheme colors, NumberFormat fmt) {
    return PremiumSurfaceCard(
      variant: PremiumSurfaceVariant.split,
      radius: 30,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'WORKSPACES',
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: colors.primary,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Active Groups',
                      style: GoogleFonts.manrope(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: colors.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
              if (_activeGroups.isNotEmpty)
                GestureDetector(
                  onTap: () async {
                    await context.push('/all-groups');
                    if (mounted) {
                      await _load();
                    }
                  },
                  child: Text(
                    'View all',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: colors.primary,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _activeGroups.isEmpty
                ? 'Nothing is live right now.'
                : 'Open a group to review debts, expenses, and settlements.',
            style: GoogleFonts.inter(
              fontSize: 13,
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          if (!_balancesLoaded && _activeGroups.isNotEmpty) ...[
            ShimmerWrap(
              child: SkeletonBox(
                width: double.infinity,
                height: 112,
                radius: 24,
              ),
            ),
            const SizedBox(height: 12),
            ShimmerWrap(
              child: SkeletonBox(
                width: double.infinity,
                height: 112,
                radius: 24,
              ),
            ),
          ] else if (_activeGroups.isEmpty && _groups.isNotEmpty)
            _NoActiveGroupsCard(
              archivedCount: _archivedIds.length,
              onViewAll: () async {
                await context.push('/all-groups');
                if (mounted) {
                  await _load();
                }
              },
            )
          else
            ..._previewGroups.asMap().entries.map((entry) {
              final i = entry.key;
              final g = entry.value;
              return Padding(
                padding: EdgeInsets.only(
                  bottom: i == _previewGroups.length - 1 ? 0 : 12,
                ),
                child: _buildGroupRow(
                  g,
                  colors,
                  fmt,
                  showPin: true,
                  pinned: g.id != null && _pinnedGroupIds.contains(g.id),
                  onPinToggle: () => _togglePinGroup(g),
                ),
              );
            }),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: () => _showCreateGroup(colors),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E2F7A),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Row(
                children: [
                  const Icon(Icons.add_circle_outline, color: Colors.white),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Create a new group workspace',
                      style: GoogleFonts.manrope(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_rounded,
                    color: Colors.white.withValues(alpha: 0.84),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _inlineBalanceMetric({
    required String label,
    required String value,
    required Color accent,
    CrossAxisAlignment align = CrossAxisAlignment.start,
  }) {
    return Column(
      crossAxisAlignment: align,
      children: [
        Text(
          label.toUpperCase(),
          style: GoogleFonts.inter(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.0,
            color: accent.withValues(alpha: 0.82),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: GoogleFonts.manrope(
            fontSize: 19,
            fontWeight: FontWeight.w800,
            color: accent,
          ),
        ),
      ],
    );
  }

  // ── Settle Up CTA ──
  Widget _buildSettleUpButton(ColorScheme colors, {bool compact = false}) {
    final button = GestureDetector(
      onTap: () {
        SplitGroup? target = _activeGroups
            .where((g) => (_groupBalances[g.id] ?? 0) < -0.5)
            .firstOrNull;
        target ??= _activeGroups.firstOrNull;
        final id = target?.id;
        if (id != null) context.push('/group/$id');
      },
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 14 : 32,
          vertical: compact ? 10 : 14,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [colors.primary, colors.primaryContainer],
          ),
          borderRadius: BorderRadius.circular(compact ? 18 : 28),
          boxShadow: [
            BoxShadow(
              color: colors.primary.withValues(alpha: 0.2),
              blurRadius: compact ? 12 : 16,
              offset: Offset(0, compact ? 4 : 6),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.account_balance_wallet_rounded,
              size: compact ? 16 : 18,
              color: Colors.white,
            ),
            SizedBox(width: compact ? 6 : 8),
            Text(
              'Settle Up',
              style: GoogleFonts.manrope(
                fontSize: compact ? 13 : 15,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
    return compact ? button : Center(child: button);
  }

  // ── Group row (flat, no card background) ──
  Widget _buildGroupRow(
    SplitGroup group,
    ColorScheme colors,
    NumberFormat fmt, {
    bool showPin = false,
    bool pinned = false,
    VoidCallback? onPinToggle,
  }) {
    final groupId = group.id;
    final summary = groupId == null ? null : _groupSummaries[groupId];
    final bal = _groupBalances[groupId] ?? 0;
    final expenseCount = summary?.expenseCount ?? 0;
    final memberCount = summary?.memberCount ?? 0;
    final hasExpenses = expenseCount > 0;
    final isPos = bal > 0.5;
    final isSettled = hasExpenses && bal.abs() <= 0.5;
    final tint = _iconTintForType(group.type);
    final statusColor = isSettled
        ? const Color(0xFF2E3144)
        : isPos
        ? const Color(0xFF0E7C78)
        : const Color(0xFFC1332F);
    final gt = _groupTypes.firstWhere(
      (t) => t['type'] == group.type,
      orElse: () => _groupTypes.last,
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () async {
          await context.push('/group/${group.id}');
          _load();
        },
        onLongPress: () => _confirmDeleteGroup(group, colors),
        borderRadius: BorderRadius.circular(24),
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF23368C).withValues(alpha: 0.05),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: tint.withValues(alpha: 0.16),
                      ),
                      child: Icon(
                        _iconForType(group.type),
                        size: 22,
                        color: tint,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    group.name,
                                    style: GoogleFonts.manrope(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                      height: 1.15,
                                      color: const Color(0xFF111318),
                                    ),
                                  ),
                                ),
                                if (showPin && group.id != null)
                                  GestureDetector(
                                    onTap: onPinToggle,
                                    child: Padding(
                                      padding: const EdgeInsets.only(left: 8),
                                      child: Icon(
                                        pinned
                                            ? Icons.push_pin_rounded
                                            : Icons.push_pin_outlined,
                                        size: 16,
                                        color: pinned
                                            ? const Color(0xFF24389C)
                                            : const Color(0xFF9AA0B5),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F3F8),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                (gt['label'] as String).toUpperCase(),
                                style: GoogleFonts.inter(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.2,
                                  color: const Color(0xFF72778B),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'Settlement',
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            color: const Color(0xFF696F82),
                          ),
                        ),
                        const SizedBox(height: 4),
                        _balancesLoaded
                            ? Text(
                                !hasExpenses
                                    ? 'New'
                                    : isSettled
                                    ? 'Settled Up'
                                    : '${isPos ? 'Owed' : 'You owe'} ₹${fmt.format(bal.abs().round())}',
                                textAlign: TextAlign.right,
                                style: GoogleFonts.manrope(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  height: 1.2,
                                  color: !hasExpenses
                                      ? const Color(0xFF6C7287)
                                      : statusColor,
                                ),
                              )
                            : Container(
                                width: 72,
                                height: 14,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF0F2F7),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _buildMemberAvatars(memberCount),
                    const Spacer(),
                    Icon(
                      isSettled
                          ? Icons.done_all_rounded
                          : Icons.access_time_filled_rounded,
                      size: 11,
                      color: const Color(0xFF5D6173),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      _timeMeta(
                        summary?.lastActivityAt ?? group.createdAt,
                        isSettled,
                      ),
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFF3B3F51),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMemberAvatars(int memberCount) {
    if (memberCount <= 0) {
      return Text(
        'No members',
        style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF757A8F)),
      );
    }
    final visible = memberCount > 3 ? 3 : memberCount;
    final palette = [
      const Color(0xFF1F2A44),
      const Color(0xFF4357A6),
      const Color(0xFF0F7E79),
    ];
    return SizedBox(
      width: memberCount > 3 ? 74 : 42 + ((visible - 1) * 14),
      height: 22,
      child: Stack(
        children: [
          for (var index = 0; index < visible; index++)
            Positioned(
              left: index * 14,
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: palette[index % palette.length],
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: Center(
                  child: Text(
                    String.fromCharCode(65 + index),
                    style: GoogleFonts.manrope(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
          if (memberCount > 3)
            Positioned(
              left: 42,
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFE7EAF4),
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: Center(
                  child: Text(
                    '+${memberCount - 3}',
                    style: GoogleFonts.inter(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF262A3B),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _timeMeta(String? raw, bool isSettled) {
    final base = _relativeTime(raw);
    return isSettled ? 'Last settled $base' : 'Updated $base';
  }

  String _relativeTime(String? raw) {
    if (raw == null || raw.isEmpty) return 'recently';
    final parsed = DateTime.tryParse(raw)?.toLocal();
    if (parsed == null) return 'recently';
    final diff = DateTime.now().difference(parsed);
    if (diff.inMinutes < 60) {
      final mins = diff.inMinutes <= 0 ? 1 : diff.inMinutes;
      return '${mins}m ago';
    }
    if (diff.inHours < 24) {
      return '${diff.inHours}h ago';
    }
    if (diff.inDays < 7) {
      return '${diff.inDays}d ago';
    }
    return DateFormat('MMM d').format(parsed);
  }

  IconData _iconForType(String type) {
    switch (type) {
      case 'roommates':
        return Icons.home_rounded;
      case 'trip':
        return Icons.flight_takeoff_rounded;
      case 'family':
        return Icons.deck_rounded;
      case 'couple':
        return Icons.favorite_rounded;
      case 'friends':
        return Icons.work_rounded;
      default:
        return Icons.folder_copy_rounded;
    }
  }

  Color _iconTintForType(String type) {
    switch (type) {
      case 'roommates':
        return const Color(0xFF3B4EB4);
      case 'trip':
        return const Color(0xFF0C7B79);
      case 'family':
        return const Color(0xFF1D5F73);
      case 'couple':
        return const Color(0xFFB93D59);
      case 'friends':
        return const Color(0xFF3C47A4);
      default:
        return const Color(0xFF5E6480);
    }
  }

  // ── Empty state (hero is above in sliver; this fills the viewport) ──
  Widget _buildEmptyBody(ColorScheme colors) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 48),
        child: PremiumSurfaceCard(
          variant: PremiumSurfaceVariant.split,
          radius: 32,
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  gradient: LinearGradient(
                    colors: [
                      colors.primary.withValues(alpha: 0.18),
                      colors.primary.withValues(alpha: 0.08),
                    ],
                  ),
                ),
                child: Icon(
                  Icons.group_add_outlined,
                  size: 42,
                  color: colors.primary,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Build Your First Split Workspace',
                style: GoogleFonts.manrope(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Trips, roommates, dinners, or family budgets. Start one space and keep every shared payment visible.',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: colors.onSurfaceVariant,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              GestureDetector(
                onTap: () => _showCreateGroup(colors),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    color: const Color(0xFF1E2F7A),
                  ),
                  child: Center(
                    child: Text(
                      'Create Group',
                      style: GoogleFonts.manrope(
                        fontSize: 15,
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
      ),
    );
  }
}

/// Shown when every group is archived — still links to the full list.
class _NoActiveGroupsCard extends StatelessWidget {
  final int archivedCount;
  final VoidCallback onViewAll;

  const _NoActiveGroupsCard({
    required this.archivedCount,
    required this.onViewAll,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onViewAll,
      child: PremiumSurfaceCard(
        variant: PremiumSurfaceVariant.split,
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
        radius: 18,
        child: Column(
          children: [
            Icon(
              Icons.inventory_2_outlined,
              size: 36,
              color: const Color(0xFF1A237E).withValues(alpha: 0.35),
            ),
            const SizedBox(height: 10),
            Text(
              'No active groups',
              style: GoogleFonts.manrope(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              archivedCount == 1
                  ? '1 group is archived. View all to restore or manage.'
                  : '$archivedCount groups are archived. View all to restore or manage.',
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
