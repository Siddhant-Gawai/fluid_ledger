import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'premium_surface_card.dart';

class PremiumSheetContainer extends StatelessWidget {
  const PremiumSheetContainer({
    super.key,
    required this.child,
    this.variant = PremiumSurfaceVariant.neutral,
    this.padding = const EdgeInsets.all(24),
    this.radius = 30,
    this.maxHeight,
  });

  final Widget child;
  final PremiumSurfaceVariant variant;
  final EdgeInsetsGeometry padding;
  final double radius;
  final double? maxHeight;

  @override
  Widget build(BuildContext context) {
    final (start, end, border) = switch (variant) {
      PremiumSurfaceVariant.dashboard => (
        const Color(0xFFF4F8FF),
        const Color(0xFFE8F0FF),
        const Color(0xFFC9D7F2),
      ),
      PremiumSurfaceVariant.goals => (
        const Color(0xFFF3F4FF),
        const Color(0xFFEEF8FA),
        const Color(0xFFD5DAF6),
      ),
      PremiumSurfaceVariant.split => (
        const Color(0xFFF5F6FF),
        const Color(0xFFF0F2FC),
        const Color(0xFFD8DEF3),
      ),
      PremiumSurfaceVariant.profile => (
        const Color(0xFFF7F8FD),
        const Color(0xFFF1F4FA),
        const Color(0xFFDEE4F0),
      ),
      PremiumSurfaceVariant.positive => (
        const Color(0xFFEFFAF5),
        const Color(0xFFE6F6EF),
        const Color(0xFFCBE8D8),
      ),
      PremiumSurfaceVariant.negative => (
        const Color(0xFFFFF4EF),
        const Color(0xFFFFF0E7),
        const Color(0xFFF6D5C8),
      ),
      PremiumSurfaceVariant.neutral => (
        const Color(0xFFF8FAFC),
        const Color(0xFFF2F5F8),
        const Color(0xFFE0E6ED),
      ),
    };

    Widget content = Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [start, end],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(radius)),
        border: Border.all(color: border.withValues(alpha: 0.42)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.028),
            blurRadius: 16,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: child,
    );

    if (maxHeight != null) {
      content = ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight!),
        child: content,
      );
    }

    return content;
  }
}

class PremiumDialog extends StatelessWidget {
  const PremiumDialog({
    super.key,
    required this.title,
    required this.body,
    required this.primaryLabel,
    required this.onPrimary,
    this.secondaryLabel = 'Cancel',
    this.onSecondary,
    this.destructive = false,
  });

  final String title;
  final String body;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final String secondaryLabel;
  final VoidCallback? onSecondary;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final primaryColor = destructive ? colors.error : colors.primary;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: PremiumSurfaceCard(
        variant: destructive
            ? PremiumSurfaceVariant.negative
            : PremiumSurfaceVariant.profile,
        radius: 28,
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: GoogleFonts.manrope(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: colors.onSurface,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              body,
              style: GoogleFonts.inter(
                fontSize: 14,
                color: colors.onSurfaceVariant,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onSecondary ?? () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                        color: colors.outlineVariant.withValues(alpha: 0.18),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(
                      secondaryLabel,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: onPrimary,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(
                      primaryLabel,
                      style: GoogleFonts.manrope(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
