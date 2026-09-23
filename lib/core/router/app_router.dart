import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../supabase/supabase_config.dart';
import 'route_extras.dart';
import '../../features/auth/presentation/screens/auth_screen.dart';
import '../../features/dashboard/presentation/screens/main_screen.dart';
import '../../features/expense/presentation/screens/add_expense_screen.dart';
import '../../features/expense/presentation/screens/auto_detect_screen.dart';
import '../../features/expense/presentation/screens/categories_screen.dart';
import '../../features/expense/presentation/screens/history_screen.dart';
import '../../features/expense/presentation/screens/monthly_summary_screen.dart';
import '../../features/goals/presentation/screens/all_goals_screen.dart';
import '../../features/goals/presentation/screens/all_weekly_targets_screen.dart';
import '../../features/goals/presentation/screens/weekly_target_history_screen.dart';
import '../../features/onboarding/presentation/screens/onboarding_screen.dart';
import '../../features/onboarding/presentation/screens/splash_screen.dart';
import '../../features/profile/presentation/screens/profile_setup_screen.dart';
import '../../features/splitwise/presentation/screens/all_groups_screen.dart';
import '../../features/splitwise/presentation/screens/group_detail_screen.dart';

/// Root stack — split detail routes use this so pushes from [MainScreen] resolve correctly.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'root',
);

// Simple session-level flags for profile check (read imperatively in redirect)
bool _profileChecked = false;
bool _hasProfile = true;

void setHasProfile(bool value) {
  _hasProfile = value;
}

void resetProfileCheck() {
  _profileChecked = false;
  _hasProfile = true;
}

final routerProvider = Provider<GoRouter>((ref) {
  final supabase = ref.read(supabaseClientProvider);
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/splash',
    redirect: (context, state) async {
      final isLoggedIn = supabase.auth.currentSession != null;
      final location = state.matchedLocation;
      final isOnAuth = location == '/auth';
      final isOnSetup = location == '/profile-setup';
      final isOnSplash = location == '/splash';
      final isOnOnboarding = location == '/onboarding';

      // Skip redirect for splash and onboarding
      if (isOnSplash || isOnOnboarding) return null;

      // Not logged in → go to auth
      if (!isLoggedIn && !isOnAuth) return '/auth';

      // Logged in but on auth page → check profile
      if (isLoggedIn && isOnAuth) {
        return '/';
      }

      // Logged in, not on setup, check if profile exists
      if (isLoggedIn && !isOnSetup && !isOnAuth) {
        if (!_profileChecked) {
          try {
            final data = await supabase
                .from('profiles')
                .select('id')
                .eq('id', supabase.auth.currentUser?.id ?? '')
                .maybeSingle();
            _hasProfile = data != null;
            _profileChecked = true;
            if (!_hasProfile) return '/profile-setup';
          } catch (e) {
            debugPrint('Error in app_router.dart: $e');
            // If profiles table doesn't exist yet, skip check
            _profileChecked = true;
          }
        } else {
          if (!_hasProfile) return '/profile-setup';
        }
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(path: '/auth', builder: (context, state) => const AuthScreen()),
      GoRoute(
        path: '/profile-setup',
        builder: (context, state) => const ProfileSetupScreen(),
      ),
      GoRoute(
        path: '/',
        builder: (context, state) => const MainScreen(),
        routes: [
          GoRoute(
            parentNavigatorKey: rootNavigatorKey,
            path: 'all-groups',
            builder: (context, state) => const AllGroupsScreen(),
          ),
          GoRoute(
            parentNavigatorKey: rootNavigatorKey,
            path: 'group/:id',
            builder: (context, state) => GroupDetailScreen(
              groupId: state.pathParameters['id']!,
              autoOpenAddExpense: state.uri.queryParameters['add'] == '1',
            ),
          ),
        ],
      ),
      GoRoute(
        path: '/add-expense',
        builder: (context, state) {
          String? initial;
          final extra = state.extra;
          if (extra is AddExpenseRouteExtra) {
            initial = extra.initialCategoryName;
          }
          initial ??= state.uri.queryParameters['category'];
          return AddExpenseScreen(initialCategoryName: initial);
        },
      ),
      GoRoute(
        path: '/auto-detect',
        builder: (context, state) => const AutoDetectScreen(),
      ),
      GoRoute(
        path: '/history',
        builder: (context, state) => const HistoryScreen(),
      ),
      GoRoute(
        path: '/categories',
        builder: (context, state) => const CategoriesScreen(),
      ),
      GoRoute(
        path: '/monthly-summary',
        builder: (context, state) => const MonthlySummaryScreen(),
      ),
      GoRoute(
        path: '/all-goals',
        builder: (context, state) => const AllGoalsScreen(),
      ),
      GoRoute(
        path: '/all-weekly-targets',
        builder: (context, state) => const AllWeeklyTargetsScreen(),
      ),
      GoRoute(
        path: '/weekly-target/:id',
        builder: (context, state) =>
            WeeklyTargetHistoryScreen(targetId: state.pathParameters['id']!),
      ),
    ],
  );
});
