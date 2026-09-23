import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';
import 'core/supabase/supabase_config.dart';
import 'core/database/sqlite_platform.dart';
import 'core/database/sync_service.dart';
import 'core/notifications/notification_service.dart';
import 'core/sms/merchant_override_service.dart';

/// Global key for root ScaffoldMessenger — ensures all snackbars render consistently
final rootScaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

void main() async {
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  await configureSqlitePlatform();

  // Transparent status bar with dark icons (light theme)
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
    ),
  );
  // Keep native splash visible while initializing
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);

  // Hydrate runtime merchant mappings from local cache before UI starts parsing SMS.
  await MerchantOverrideService.instance.hydrateFromLocal();

  // Initialize notifications & schedule recurring ones
  await NotificationService().init();
  await NotificationService().scheduleDailyReminder();
  await NotificationService().scheduleWeeklySummary();

  // Kick off background sync if logged in
  if (appSupabaseClient.auth.currentSession != null) {
    // Fire-and-forget background jobs must swallow transient auth/network errors.
    unawaited(
      SyncService.instance.deltaSync().catchError((Object e, StackTrace st) {
        debugPrint('main: deltaSync background error (ignored): $e');
        return false;
      }),
    );
    unawaited(
      SyncService.instance.flushPendingWrites().catchError((
        Object e,
        StackTrace st,
      ) {
        debugPrint('main: flushPendingWrites background error (ignored): $e');
      }),
    );
  }

  // Remove splash — app is ready
  FlutterNativeSplash.remove();

  runApp(const ProviderScope(child: FluidLedgerApp()));
}

class FluidLedgerApp extends ConsumerWidget {
  const FluidLedgerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'The Fluid Ledger',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      scaffoldMessengerKey: rootScaffoldMessengerKey,
      routerConfig: router,
      builder: (context, child) {
        // Must allow bottom inset so routed screens (auth, sheets, forms) resize above the keyboard.
        return Scaffold(body: child, resizeToAvoidBottomInset: true);
      },
    );
  }
}
