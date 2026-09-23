import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

/// Shared gradient stat hero — matches [DashboardScreen] “Total Spent” card sizing and styling.
class GradientHeroCard extends StatelessWidget {
  const GradientHeroCard({
    super.key,
    required this.fmt,
    required this.topLeftLabel,
    required this.statusPillText,
    required this.statusPillAccentColor,
    required this.metricLabel,
    required this.amountValue,
    required this.progress,
    required this.accentColor,
    required this.footerLeft,
    required this.footerRight,
    this.metricHint,
    this.backgroundGradient,
    this.watermark,
    this.loading = false,
  });

  final NumberFormat fmt;
  final String topLeftLabel;
  final String statusPillText;
  final Color statusPillAccentColor;
  final String metricLabel;
  final double amountValue;
  final double progress;
  /// Progress bar fill and default footer-right amount color (e.g. teal vs over-budget red).
  final Color accentColor;
  final String footerLeft;
  final String footerRight;
  final String? metricHint;
  final LinearGradient? backgroundGradient;
  /// A subtle decorative overlay rendered behind content (e.g. icon / pattern).
  ///
  /// Intended to be small and low-opacity so it doesn't compete with the number.
  final Widget? watermark;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final gradient = backgroundGradient ??
        const LinearGradient(
          colors: [Color(0xFF1a2d8a), Color(0xFF24389c), Color(0xFF3b4fb0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );

    if (loading) return _GradientHeroSkeleton(gradient: gradient);

    final barValue = progress.clamp(0.0, 1.0);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 22),
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF24389c).withValues(alpha: 0.28),
            blurRadius: 36,
            offset: const Offset(0, 18),
            spreadRadius: -6,
          ),
        ],
      ),
      child: Stack(
        children: [
          if (watermark != null) Positioned.fill(child: IgnorePointer(child: watermark!)),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                topLeftLabel,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.5),
                  letterSpacing: 2,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  statusPillText,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: statusPillAccentColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                metricLabel,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  color: Colors.white.withValues(alpha: 0.5),
                ),
              ),
              if (metricHint != null && metricHint!.isNotEmpty) ...[
                const SizedBox(width: 6),
                Text(
                  metricHint!,
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withValues(alpha: 0.42),
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '₹',
                  style: GoogleFonts.manrope(
                    fontSize: 28,
                    fontWeight: FontWeight.w400,
                    color: Colors.white.withValues(alpha: 0.55),
                    height: 1.1,
                  ),
                ),
                TextSpan(
                  text: fmt.format(amountValue.round()),
                  style: GoogleFonts.manrope(
                    fontSize: 52,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 4,
              child: LinearProgressIndicator(
                value: barValue,
                backgroundColor: Colors.white.withValues(alpha: 0.12),
                valueColor: AlwaysStoppedAnimation<Color>(accentColor),
                minHeight: 4,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  footerLeft,
                  style: GoogleFonts.inter(fontSize: 12, color: Colors.white.withValues(alpha: 0.4)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                footerRight,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: accentColor,
                ),
                textAlign: TextAlign.end,
              ),
            ],
          ),
        ],
          ),
        ],
      ),
    );
  }
}

/// Layout mirrors [GradientHeroCard] so loading state matches final height.
class _GradientHeroSkeleton extends StatelessWidget {
  const _GradientHeroSkeleton({required this.gradient});

  final LinearGradient gradient;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 22),
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF24389c).withValues(alpha: 0.28),
            blurRadius: 36,
            offset: const Offset(0, 18),
            spreadRadius: -6,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                height: 12,
                width: 88,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              Container(
                height: 24,
                width: 80,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            height: 14,
            width: 88,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 6),
          Container(
            height: 52,
            width: 220,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          const SizedBox(height: 24),
          Container(
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                height: 12,
                width: 120,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const Spacer(),
              Container(
                height: 12,
                width: 96,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
