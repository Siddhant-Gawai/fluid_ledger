import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/common_widgets/skeleton_loader.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/supabase/supabase_config.dart';
import '../../../../core/utils/snackbar_helper.dart';
import '../../data/profile_repository.dart';

// Avatar options — colors and icons for selection
const _avatarOptions = [
  {'color': Color(0xFF24389c), 'icon': Icons.person},
  {'color': Color(0xFF006a6a), 'icon': Icons.face},
  {'color': Color(0xFF7C4DFF), 'icon': Icons.mood},
  {'color': Color(0xFFFF8A65), 'icon': Icons.sentiment_very_satisfied},
  {'color': Color(0xFF313e7e), 'icon': Icons.psychology},
  {'color': Color(0xFF00897B), 'icon': Icons.emoji_emotions},
];

class ProfileSetupScreen extends ConsumerStatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  ConsumerState<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends ConsumerState<ProfileSetupScreen> {
  final _nameController = TextEditingController();
  final _ageController = TextEditingController();
  final _emailController = TextEditingController();
  final _budgetController = TextEditingController(text: '50000');
  int _selectedAvatar = 0;
  bool _isSaving = false;
  bool _isEditMode = false;
  bool _loading = true;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _loadExistingProfile();
  }

  Future<void> _loadExistingProfile() async {
    try {
      final profile = await ref.read(profileRepositoryProvider).getProfile();
      if (profile != null && mounted) {
        setState(() {
          _isEditMode = true;
          _nameController.text = profile.name;
          _ageController.text = profile.age.toString();
          _emailController.text = profile.email;
          _budgetController.text = profile.monthlyBudget.round().toString();
          _selectedAvatar = profile.avatarIndex.clamp(0, _avatarOptions.length - 1);
        });
      }
    } catch (e) { debugPrint('Error in profile_setup_screen.dart: $e');
      // No profile yet — new signup
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _ageController.dispose();
    _emailController.dispose();
    _budgetController.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final user = ref.read(supabaseClientProvider).auth.currentUser!;
      final budget = double.tryParse(_budgetController.text.trim().replaceAll(',', '')) ?? 50000;
      final profile = UserProfile(
        id: user.id,
        name: _nameController.text.trim(),
        age: int.parse(_ageController.text.trim()),
        email: _emailController.text.trim(),
        phone: user.phone ?? '',
        avatarIndex: _selectedAvatar,
        monthlyBudget: budget,
      );

      await ref.read(profileRepositoryProvider).createProfile(profile);
      setHasProfile(true);
      if (mounted) {
        if (_isEditMode) {
          showSuccessSnackBar('Profile updated');
          context.pop();
        } else {
          context.go('/');
        }
      }
    } catch (e) {
      if (mounted) {
        showErrorSnackBar('Failed to save profile: $e');
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    if (_loading) {
      return Scaffold(
        backgroundColor: colors.surface,
        body: const PageSkeleton(rows: 5),
      );
    }

    return Scaffold(
      backgroundColor: colors.surface,
      appBar: _isEditMode
          ? AppBar(
              backgroundColor: colors.surface,
              scrolledUnderElevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.pop(),
              ),
              title: Text(
                'Edit Profile',
                style: GoogleFonts.manrope(fontSize: 18, fontWeight: FontWeight.w700, color: colors.onSurface),
              ),
            )
          : null,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: 24, vertical: _isEditMode ? 8 : 32),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!_isEditMode) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Complete Your Profile',
                    style: GoogleFonts.manrope(fontSize: 28, fontWeight: FontWeight.w800, color: colors.onSurface),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Tell us a bit about yourself to personalize your experience.',
                    style: GoogleFonts.inter(fontSize: 14, color: colors.onSurfaceVariant),
                  ),
                  const SizedBox(height: 32),
                ],

                // Avatar selection
                Text(
                  'CHOOSE AVATAR',
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: colors.primary,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: List.generate(_avatarOptions.length, (index) {
                    final isSelected = _selectedAvatar == index;
                    final avatarColor = _avatarOptions[index]['color'] as Color;
                    final avatarIcon = _avatarOptions[index]['icon'] as IconData;
                    return GestureDetector(
                      onTap: () => setState(() => _selectedAvatar = index),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.only(right: 10),
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: isSelected ? avatarColor : avatarColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(16),
                          border: isSelected
                              ? Border.all(color: avatarColor, width: 2.5)
                              : null,
                          boxShadow: isSelected
                              ? [BoxShadow(color: avatarColor.withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 4))]
                              : null,
                        ),
                        child: Icon(
                          avatarIcon,
                          color: isSelected ? Colors.white : avatarColor,
                          size: 24,
                        ),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 28),

                // Form card
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.12)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Name
                      _buildLabel('FULL NAME'),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _nameController,
                        textCapitalization: TextCapitalization.words,
                        style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w600),
                        decoration: _buildInputDecoration(
                          context,
                          hint: 'Enter your name',
                          icon: Icons.person_outline,
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) return 'Name is required';
                          if (value.trim().length < 2) return 'Name too short';
                          return null;
                        },
                      ),
                      const SizedBox(height: 22),

                      // Age
                      _buildLabel('AGE'),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _ageController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(3),
                        ],
                        style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w600),
                        decoration: _buildInputDecoration(
                          context,
                          hint: 'Your age',
                          icon: Icons.cake_outlined,
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) return 'Age is required';
                          final age = int.tryParse(value.trim());
                          if (age == null || age < 13 || age > 120) return 'Enter a valid age (13-120)';
                          return null;
                        },
                      ),
                      const SizedBox(height: 22),

                      // Email
                      _buildLabel('EMAIL'),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w600),
                        decoration: _buildInputDecoration(
                          context,
                          hint: 'you@example.com',
                          icon: Icons.email_outlined,
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) return 'Email is required';
                          final emailRegex = RegExp(r'^[\w\.-]+@[\w\.-]+\.\w{2,}$');
                          if (!emailRegex.hasMatch(value.trim())) return 'Enter a valid email';
                          return null;
                        },
                      ),
                      const SizedBox(height: 22),

                      // Phone (read-only, already verified)
                      _buildLabel('PHONE (VERIFIED)'),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        decoration: BoxDecoration(
                          color: colors.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.phone_android, size: 20, color: colors.secondary),
                            const SizedBox(width: 12),
                            Text(
                              ref.read(supabaseClientProvider).auth.currentUser?.phone ?? 'Verified',
                              style: GoogleFonts.manrope(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: colors.onSurface,
                              ),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: colors.secondaryContainer.withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.check_circle, size: 14, color: colors.secondary),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Verified',
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: colors.secondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // Save button
                SizedBox(
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
                      onPressed: _isSaving ? null : _saveProfile,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        disabledBackgroundColor: Colors.transparent,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  _isEditMode ? 'Save Changes' : 'Get Started',
                                  style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white),
                                ),
                                const SizedBox(width: 8),
                                Icon(_isEditMode ? Icons.check : Icons.arrow_forward, size: 18, color: Colors.white),
                              ],
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: GoogleFonts.inter(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        color: Theme.of(context).colorScheme.primary,
        letterSpacing: 1.5,
      ),
    );
  }

  InputDecoration _buildInputDecoration(BuildContext context, {required String hint, required IconData icon}) {
    final colors = Theme.of(context).colorScheme;
    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.inter(fontSize: 15, color: colors.outlineVariant),
      prefixIcon: Icon(icon, size: 20, color: colors.onSurfaceVariant),
      filled: true,
      fillColor: colors.surfaceContainerLow,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: colors.primary.withValues(alpha: 0.3), width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: colors.error.withValues(alpha: 0.5), width: 1),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: colors.error, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
  }
}
