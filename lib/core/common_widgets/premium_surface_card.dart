import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

enum PremiumSurfaceVariant {
  dashboard,
  goals,
  split,
  profile,
  positive,
  negative,
  neutral,
}

class PremiumSurfaceCard extends StatelessWidget {
  const PremiumSurfaceCard({
    super.key,
    required this.child,
    this.variant = PremiumSurfaceVariant.neutral,
    this.padding = const EdgeInsets.all(20),
    this.radius = 24,
  });

  final Widget child;
  final PremiumSurfaceVariant variant;
  final EdgeInsetsGeometry padding;
  final double radius;

  (Color, Color, Color) _palette() {
    switch (variant) {
      case PremiumSurfaceVariant.dashboard:
        return (
          const Color(0xFFF4F8FF),
          const Color(0xFFE8F0FF),
          const Color(0xFFC9D7F2),
        );
      case PremiumSurfaceVariant.goals:
        return (
          const Color(0xFFF3F4FF),
          const Color(0xFFEEF8FA),
          const Color(0xFFD5DAF6),
        );
      case PremiumSurfaceVariant.split:
        return (
          const Color(0xFFF5F6FF),
          const Color(0xFFF0F2FC),
          const Color(0xFFD8DEF3),
        );
      case PremiumSurfaceVariant.profile:
        return (
          const Color(0xFFF7F8FD),
          const Color(0xFFF1F4FA),
          const Color(0xFFDEE4F0),
        );
      case PremiumSurfaceVariant.positive:
        return (
          const Color(0xFFEFFAF5),
          const Color(0xFFE6F6EF),
          const Color(0xFFCBE8D8),
        );
      case PremiumSurfaceVariant.negative:
        return (
          const Color(0xFFFFF4EF),
          const Color(0xFFFFF0E7),
          const Color(0xFFF6D5C8),
        );
      case PremiumSurfaceVariant.neutral:
        return (
          const Color(0xFFF8FAFC),
          const Color(0xFFF2F5F8),
          const Color(0xFFE0E6ED),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final (start, end, border) = _palette();
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [start, end],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(radius),
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
  }
}

class PremiumStatCard extends StatelessWidget {
  const PremiumStatCard({
    super.key,
    required this.label,
    required this.amount,
    required this.amountColor,
    required this.labelColor,
    required this.variant,
    this.trailing,
  });

  final String label;
  final String amount;
  final Color amountColor;
  final Color labelColor;
  final PremiumSurfaceVariant variant;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return PremiumSurfaceCard(
      variant: variant,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      radius: 18,
      child: PremiumMetricBox(
        label: label,
        value: amount,
        labelColor: labelColor,
        valueColor: amountColor,
        minHeight: 86,
        trailing: trailing,
      ),
    );
  }
}

class PremiumMetricBox extends StatelessWidget {
  const PremiumMetricBox({
    super.key,
    required this.label,
    required this.value,
    required this.labelColor,
    required this.valueColor,
    this.backgroundColor,
    this.icon,
    this.trailing,
    this.minHeight = 84,
    this.valueFontSize = 18,
    this.labelFontSize = 9,
    this.labelFirst = true,
  });

  final String label;
  final String value;
  final Color labelColor;
  final Color valueColor;
  final Color? backgroundColor;
  final IconData? icon;
  final Widget? trailing;
  final double minHeight;
  final double valueFontSize;
  final double labelFontSize;
  final bool labelFirst;

  @override
  Widget build(BuildContext context) {
    final headerChildren = <Widget>[
      if (icon != null) ...[
        Icon(icon, size: 16, color: labelColor),
        const SizedBox(width: 8),
      ],
      Expanded(
        child: labelFirst
            ? Text(
                label.toUpperCase(),
                style: GoogleFonts.inter(
                  fontSize: labelFontSize,
                  fontWeight: FontWeight.w700,
                  color: labelColor,
                  letterSpacing: 0.9,
                ),
              )
            : const SizedBox.shrink(),
      ),
    ];
    if (trailing != null) {
      headerChildren.add(trailing!);
    }

    return Container(
      constraints: BoxConstraints(minHeight: minHeight),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: headerChildren,
          ),
          if (!labelFirst && icon == null && trailing == null)
            const SizedBox.shrink(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!labelFirst) ...[
                Text(
                  value,
                  style: GoogleFonts.manrope(
                    fontSize: valueFontSize,
                    fontWeight: FontWeight.w800,
                    color: valueColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  label.toUpperCase(),
                  style: GoogleFonts.inter(
                    fontSize: labelFontSize,
                    fontWeight: FontWeight.w700,
                    color: labelColor,
                    letterSpacing: 0.9,
                  ),
                ),
              ] else
                Text(
                  value,
                  style: GoogleFonts.manrope(
                    fontSize: valueFontSize,
                    fontWeight: FontWeight.w800,
                    color: valueColor,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
