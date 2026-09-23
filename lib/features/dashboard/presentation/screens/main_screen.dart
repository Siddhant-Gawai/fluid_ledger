import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../splitwise/presentation/screens/groups_screen.dart';
import '../../../profile/presentation/screens/profile_screen.dart';
import '../../../goals/presentation/screens/goals_screen.dart';
import 'dashboard_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  final _dashboardKey = GlobalKey<DashboardScreenState>();
  final _groupsKey = GlobalKey<GroupsScreenState>();
  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _screens = [
      DashboardScreen(key: _dashboardKey),
      GroupsScreen(key: _groupsKey),
      const GoalsScreen(),
      const ProfileScreen(),
    ];
  }

  void _switchTab(int index) {
    if (index == _currentIndex) return;
    HapticFeedback.selectionClick();
    setState(() => _currentIndex = index);
  }

  double _bottomNavReserve(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    return 68 + (bottomPad > 0 ? bottomPad : 12) + 12;
  }

  @override
  Widget build(BuildContext context) {
    final bottomReserve = _bottomNavReserve(context);
    return Scaffold(
      extendBody: true,
      body: Padding(
        padding: EdgeInsets.only(bottom: bottomReserve),
        child: _screens[_currentIndex],
      ),
      floatingActionButton: _currentIndex == 1 ? _buildSplitFab() : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      bottomNavigationBar: _AppNavBar(
        currentIndex: _currentIndex,
        onTap: _switchTab,
      ),
    );
  }

  Widget _buildSplitFab() {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: _bottomNavReserve(context) - 4),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            colors: [colors.primary, colors.tertiary],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: colors.primary.withValues(alpha: 0.32),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              HapticFeedback.mediumImpact();
              _groupsKey.currentState?.openAddSplitExpenseFlow();
            },
            borderRadius: BorderRadius.circular(18),
            child: const SizedBox(
              width: 60,
              height: 60,
              child: Icon(
                Icons.add_rounded,
                color: Colors.white,
                size: 30,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Bottom nav — 4 tabs: Expenses, History, Split, Profile
// =============================================================================

class _AppNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _AppNavBar({required this.currentIndex, required this.onTap});

  static const _items = [
    _NavItemData(
      Icons.receipt_long_outlined,
      Icons.receipt_long_rounded,
      'Expenses',
    ),
    _NavItemData(Icons.call_split_outlined, Icons.call_split_rounded, 'Split'),
    _NavItemData(Icons.flag_outlined, Icons.flag_rounded, 'Goals'),
    _NavItemData(Icons.person_outline_rounded, Icons.person_rounded, 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, bottomPad > 0 ? bottomPad : 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Container(
          height: 68,
          decoration: BoxDecoration(
            color: colors.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: colors.outlineVariant.withValues(alpha: 0.16),
            ),
            boxShadow: [
              BoxShadow(
                color: colors.shadow.withValues(alpha: 0.08),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: List.generate(_items.length, (i) {
              final item = _items[i];
              final isSelected = currentIndex == i;
              return Expanded(
                child: GestureDetector(
                  onTap: () => onTap(i),
                  behavior: HitTestBehavior.opaque,
                  child: SizedBox(
                    height: 68,
                    child: Center(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        width: 84,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? colors.primary.withValues(alpha: 0.11)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 220),
                              child: Icon(
                                isSelected ? item.activeIcon : item.icon,
                                key: ValueKey('${item.label}_$isSelected'),
                                size: 21,
                                color: isSelected
                                    ? colors.primary
                                    : colors.onSurfaceVariant.withValues(
                                        alpha: 0.72,
                                      ),
                              ),
                            ),
                            const SizedBox(height: 3),
                            AnimatedDefaultTextStyle(
                              duration: const Duration(milliseconds: 220),
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: isSelected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: isSelected
                                    ? colors.primary
                                    : colors.onSurfaceVariant.withValues(
                                        alpha: 0.78,
                                      ),
                              ),
                              child: Text(
                                item.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _NavItemData {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  const _NavItemData(this.icon, this.activeIcon, this.label);
}
