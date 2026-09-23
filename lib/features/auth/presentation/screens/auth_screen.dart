import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/common_widgets/hero_screen_themes.dart';
import '../../../../core/common_widgets/premium_surface_card.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/supabase/supabase_config.dart';
import '../../../../core/utils/snackbar_helper.dart';
import '../../providers/auth_provider.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _phoneController = TextEditingController();
  final _otpControllers = List.generate(6, (_) => TextEditingController());
  final _otpFocusNodes = List.generate(6, (_) => FocusNode());
  bool _isSignUp = false;

  /// Avoids chaining focus when we programmatically clear a digit (empty-cell backspace).
  bool _suppressOtpChanged = false;

  @override
  void dispose() {
    _phoneController.dispose();
    for (final c in _otpControllers) {
      c.dispose();
    }
    for (final f in _otpFocusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  String get _fullPhone =>
      '+91${_phoneController.text.replaceAll(' ', '').trim()}';
  String get _otpCode => _otpControllers.map((c) => c.text).join();

  void _clearOtp() {
    for (final c in _otpControllers) {
      c.clear();
    }
  }

  Future<void> _handleAuthenticated() async {
    try {
      final client = ref.read(supabaseClientProvider);
      final userId = client.auth.currentUser!.id;
      final data = await client
          .from('profiles')
          .select('id')
          .eq('id', userId)
          .maybeSingle();

      if (data != null) {
        // Profile exists → go to dashboard
        setHasProfile(true);
        if (mounted) context.go('/');
      } else {
        // No profile → go to setup
        setHasProfile(false);
        if (mounted) context.go('/profile-setup');
      }
    } catch (e) {
      debugPrint('Error in auth_screen.dart: $e');
      // Fallback: go to profile setup for new signups, dashboard for logins
      if (_isSignUp) {
        setHasProfile(false);
        if (mounted) context.go('/profile-setup');
      } else {
        if (mounted) context.go('/');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final colors = Theme.of(context).colorScheme;

    ref.listen<AuthState>(authProvider, (previous, next) {
      if (next == AuthState.authenticated) {
        _handleAuthenticated();
      }
      if (next == AuthState.existingUser) {
        final notifier = ref.read(authProvider.notifier);
        setState(() => _isSignUp = false);
        showInfoSnackBar(
          notifier.errorMessage,
          duration: const Duration(seconds: 4),
        );
        notifier.reset();
      }
      if (next == AuthState.error) {
        final notifier = ref.read(authProvider.notifier);
        showErrorSnackBar(notifier.errorMessage);
        notifier.clearError();
      }
    });

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: colors.surface,
        resizeToAvoidBottomInset: true,
        body: Stack(
          children: [
            SafeArea(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  24,
                  20,
                  24,
                  MediaQuery.of(context).viewInsets.bottom + 32,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
                      decoration: BoxDecoration(
                        gradient: HeroScreenThemes.dashboardGradient,
                        borderRadius: BorderRadius.circular(32),
                        boxShadow: [
                          BoxShadow(
                            color: colors.primary.withValues(alpha: 0.22),
                            blurRadius: 28,
                            offset: const Offset(0, 16),
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
                              Container(
                                width: 56,
                                height: 56,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                child: const Icon(
                                  Icons.account_balance_wallet,
                                  size: 30,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 18),
                              Text(
                                'The Fluid Ledger',
                                style: GoogleFonts.manrope(
                                  fontSize: 30,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  letterSpacing: -0.6,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'A finance workspace for clear budgets, trusted sync, and fast daily decisions.',
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.white.withValues(alpha: 0.76),
                                  height: 1.45,
                                ),
                              ),
                              const SizedBox(height: 18),
                              Row(
                                children: const [
                                  _HeroChip(
                                    icon: Icons.verified_user_outlined,
                                    label: 'Bank-grade',
                                  ),
                                  SizedBox(width: 10),
                                  _HeroChip(
                                    icon: Icons.flash_on_rounded,
                                    label: 'Instant sync',
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    PremiumSurfaceCard(
                      variant: PremiumSurfaceVariant.profile,
                      radius: 28,
                      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'ACCESS',
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: colors.primary,
                              letterSpacing: 1.5,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Secure sign in',
                            style: GoogleFonts.manrope(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: colors.onSurface,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Use your mobile number once. OTP access keeps the flow fast without weakening trust.',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: colors.onSurfaceVariant,
                              height: 1.45,
                            ),
                          ),
                          const SizedBox(height: 18),
                          _buildAuthToggle(colors),
                          const SizedBox(height: 18),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(22),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.58),
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 300),
                              switchInCurve: Curves.easeOut,
                              child: _buildAuthState(context, authState),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildBadge(
                          context,
                          Icons.verified_user_outlined,
                          'BANK-GRADE SECURITY',
                        ),
                        const SizedBox(width: 24),
                        _buildBadge(
                          context,
                          Icons.fingerprint,
                          'RBI COMPLIANT',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAuthToggle(ColorScheme colors) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.52),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () {
                if (_isSignUp) {
                  setState(() => _isSignUp = false);
                  ref.read(authProvider.notifier).reset();
                  _clearOtp();
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: !_isSignUp
                      ? colors.surfaceContainerLowest
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(11),
                  boxShadow: !_isSignUp
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Center(
                  child: Text(
                    'Login',
                    style: GoogleFonts.manrope(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: !_isSignUp
                          ? colors.primary
                          : colors.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () {
                if (!_isSignUp) {
                  setState(() => _isSignUp = true);
                  ref.read(authProvider.notifier).reset();
                  _clearOtp();
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: _isSignUp
                      ? colors.surfaceContainerLowest
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(11),
                  boxShadow: _isSignUp
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Center(
                  child: Text(
                    'Sign Up',
                    style: GoogleFonts.manrope(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _isSignUp
                          ? colors.secondary
                          : colors.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBadge(BuildContext context, IconData icon, String label) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: colors.outline),
        const SizedBox(width: 6),
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: colors.outline,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }

  Widget _buildAuthState(BuildContext context, AuthState state) {
    if (state == AuthState.processing || state == AuthState.authenticated) {
      return SizedBox(
        key: const ValueKey('loading'),
        height: 200,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 40,
                height: 40,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                state == AuthState.authenticated
                    ? 'Setting up...'
                    : 'Please wait...',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (state == AuthState.otpEntry) {
      return _buildOtpEntry(context);
    }

    return _buildPhoneEntry(context);
  }

  Widget _buildPhoneEntry(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      key: ValueKey('phone_$_isSignUp'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _isSignUp ? 'Create Account' : 'Welcome back',
          style: GoogleFonts.manrope(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: colors.onSurface,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _isSignUp
              ? 'Enter your mobile number to get started.'
              : 'Enter your mobile number to securely access your ledger.',
          style: GoogleFonts.inter(
            fontSize: 14,
            color: colors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 28),

        // Label
        Text(
          'MOBILE NUMBER',
          style: GoogleFonts.inter(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: colors.primary,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 10),

        // Phone input
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            color: colors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.only(right: 14),
                decoration: BoxDecoration(
                  border: Border(
                    right: BorderSide(
                      color: colors.outlineVariant.withValues(alpha: 0.3),
                    ),
                  ),
                ),
                child: Text(
                  '+91',
                  style: GoogleFonts.manrope(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: colors.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  maxLength: 11,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[\d ]')),
                    _PhoneSpaceFormatter(),
                  ],
                  style: GoogleFonts.manrope(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 3,
                  ),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: '00000 00000',
                    counterText: '',
                    filled: false,
                    contentPadding: EdgeInsets.zero,
                    hintStyle: GoogleFonts.manrope(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 3,
                      color: colors.outlineVariant,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),

        // CTA
        _buildGradientButton(
          context,
          label: _isSignUp ? 'Verify Number' : 'Get Verification Code',
          icon: Icons.arrow_forward,
          onPressed: () {
            final phone = _phoneController.text.replaceAll(' ', '').trim();
            if (phone.length == 10) {
              if (_isSignUp) {
                ref.read(authProvider.notifier).sendSignUpOtp(_fullPhone);
              } else {
                ref.read(authProvider.notifier).sendOtp(_fullPhone);
              }
            }
          },
        ),
        const SizedBox(height: 20),

        // Terms
        Center(
          child: Text.rich(
            TextSpan(
              text: 'By continuing, you agree to our ',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: colors.onSurfaceVariant,
              ),
              children: [
                TextSpan(
                  text: 'Terms of Service',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: colors.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const TextSpan(text: ' and '),
                TextSpan(
                  text: 'Privacy Policy',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: colors.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const TextSpan(text: '.'),
              ],
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  Widget _buildOtpEntry(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      key: const ValueKey('otp'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () {
            _clearOtp();
            ref.read(authProvider.notifier).reset();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.arrow_back, size: 14, color: colors.primary),
                const SizedBox(width: 6),
                Text(
                  'CHANGE NUMBER',
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: colors.primary,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Verify Identity',
          style: GoogleFonts.manrope(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: colors.onSurface,
          ),
        ),
        const SizedBox(height: 6),
        Text.rich(
          TextSpan(
            text: "We've sent a 6-digit code to ",
            style: GoogleFonts.inter(
              fontSize: 14,
              color: colors.onSurfaceVariant,
            ),
            children: [
              TextSpan(
                text: '+91 ${_phoneController.text}',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: colors.onSurface,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),

        // OTP boxes
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(6, (index) {
            return Container(
              width: 46,
              height: 56,
              decoration: BoxDecoration(
                color: colors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _otpControllers[index].text.isNotEmpty
                      ? colors.primary.withValues(alpha: 0.3)
                      : Colors.transparent,
                  width: 1.5,
                ),
              ),
              child: Focus(
                onKeyEvent: (node, event) {
                  if (event is! KeyDownEvent) return KeyEventResult.ignored;
                  final key = event.logicalKey;
                  final isDelete =
                      key == LogicalKeyboardKey.backspace ||
                      key == LogicalKeyboardKey.delete;
                  if (!isDelete) return KeyEventResult.ignored;

                  // Digit still present — let TextField delete it; onChanged handles focus.
                  if (_otpControllers[index].text.isNotEmpty) {
                    return KeyEventResult.ignored;
                  }

                  // Empty cell + backspace: `onChanged` does not run — go back and clear previous digit.
                  if (index > 0) {
                    final prev = index - 1;
                    _suppressOtpChanged = true;
                    _otpControllers[prev].clear();
                    _suppressOtpChanged = false;
                    _otpFocusNodes[prev].requestFocus();
                    setState(() {});
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: TextField(
                  controller: _otpControllers[index],
                  focusNode: _otpFocusNodes[index],
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  maxLength: 1,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: GoogleFonts.manrope(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: colors.onSurface,
                  ),
                  decoration: const InputDecoration(
                    counterText: '',
                    border: InputBorder.none,
                    filled: false,
                    contentPadding: EdgeInsets.zero,
                  ),
                  onChanged: (value) {
                    if (_suppressOtpChanged) {
                      setState(() {});
                      return;
                    }
                    setState(() {});
                    if (value.isNotEmpty && index < 5) {
                      _otpFocusNodes[index + 1].requestFocus();
                    }
                    if (value.isEmpty && index > 0) {
                      _otpFocusNodes[index - 1].requestFocus();
                    }
                  },
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 28),

        _buildGradientButton(
          context,
          label: 'Verify & Continue',
          onPressed: () {
            final otp = _otpCode;
            if (otp.length == 6) {
              ref.read(authProvider.notifier).verifyOtp(otp);
            }
          },
        ),
        const SizedBox(height: 20),

        // Resend
        Center(
          child: Column(
            children: [
              Text(
                "Didn't receive the code?",
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              GestureDetector(
                onTap: () =>
                    ref.read(authProvider.notifier).sendOtp(_fullPhone),
                child: Text(
                  'Resend Code',
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
      ],
    );
  }

  Widget _buildGradientButton(
    BuildContext context, {
    required String label,
    IconData? icon,
    required VoidCallback onPressed,
  }) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      width: double.infinity,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [colors.primary, colors.primaryContainer],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
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
          onPressed: onPressed,
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
              Text(
                label,
                style: GoogleFonts.manrope(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              if (icon != null) ...[
                const SizedBox(width: 8),
                Icon(icon, size: 18, color: Colors.white),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Formats phone input as "XXXXX XXXXX" — inserts space after 5th digit.
class _PhoneSpaceFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(' ', '');
    if (digits.length > 10) return oldValue;

    final buf = StringBuffer();
    for (int i = 0; i < digits.length; i++) {
      if (i == 5) buf.write(' ');
      buf.write(digits[i]);
    }

    final formatted = buf.toString();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class _HeroChip extends StatelessWidget {
  const _HeroChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white.withValues(alpha: 0.9)),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.white.withValues(alpha: 0.9),
            ),
          ),
        ],
      ),
    );
  }
}
