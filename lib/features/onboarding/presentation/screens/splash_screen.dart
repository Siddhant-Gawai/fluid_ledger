import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/supabase/supabase_config.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeIn;
  late Animation<double> _slideUp;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));
    _fadeIn = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.6, curve: Curves.easeOut)));
    _slideUp = Tween<double>(begin: 30, end: 0).animate(CurvedAnimation(parent: _controller, curve: const Interval(0.2, 0.8, curve: Curves.easeOut)));
    _controller.forward();

    // Navigate after animation
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (!mounted) return;
      final isLoggedIn = appSupabaseClient.auth.currentSession != null;
      if (isLoggedIn) {
        context.go('/');
      } else {
        context.go('/onboarding');
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colors.surface,
      body: Stack(
        children: [
          // Background orbs
          Positioned(
            top: -100, right: -60,
            child: Container(
              width: 300, height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [colors.secondaryFixed.withValues(alpha: 0.1), Colors.transparent]),
              ),
            ),
          ),
          Positioned(
            bottom: -80, left: -60,
            child: Container(
              width: 250, height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [colors.primary.withValues(alpha: 0.06), Colors.transparent]),
              ),
            ),
          ),

          // Content
          Center(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) => Opacity(
                opacity: _fadeIn.value,
                child: Transform.translate(
                  offset: Offset(0, _slideUp.value),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Logo
                      Container(
                        width: 80, height: 80,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [colors.primary, colors.primaryContainer]),
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [BoxShadow(color: colors.primary.withValues(alpha: 0.2), blurRadius: 20, offset: const Offset(0, 8))],
                        ),
                        child: const Icon(Icons.account_balance_wallet, color: Colors.white, size: 40),
                      ),
                      const SizedBox(height: 24),

                      // App name
                      Text(
                        'The Fluid\nLedger',
                        style: GoogleFonts.manrope(fontSize: 36, fontWeight: FontWeight.w800, color: colors.primary, height: 1.1),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 10),

                      // Tagline
                      Text(
                        'Track Smarter, Save Better',
                        style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w500, color: colors.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Bottom trust
          Positioned(
            bottom: 48,
            left: 0, right: 0,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) => Opacity(
                opacity: _fadeIn.value,
                child: Center(
                  child: Text(
                    'TRUSTED BY 50,000+ INDIANS',
                    style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: colors.outlineVariant, letterSpacing: 1.5),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
