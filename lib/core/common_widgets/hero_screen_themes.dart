import 'package:flutter/material.dart';

/// Per-main-tab hero styling: same blue family + shape, distinct gradient + watermark.
abstract final class HeroScreenThemes {
  /// Expenses overview — cooler analytic blues.
  static const LinearGradient dashboardGradient = LinearGradient(
    colors: [Color(0xFF14246e), Color(0xFF24389c), Color(0xFF4b67c6)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Goals / savings — blue into soft violet (aspirational).
  static const LinearGradient goalsGradient = LinearGradient(
    colors: [Color(0xFF1a2d8a), Color(0xFF2b3aa3), Color(0xFF6b4fd4)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Split / groups — indigo pulse based on the local Splitwise design references.
  static const LinearGradient splitGradient = LinearGradient(
    colors: [Color(0xFF24389C), Color(0xFF3147AA), Color(0xFF3F51B5)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Profile — deep indigo to soft slate-blue (calm, personal).
  static const LinearGradient profileGradient = LinearGradient(
    colors: [Color(0xFF1c2568), Color(0xFF24389c), Color(0xFF5c6bc0)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Subtle bottom-right illustration; keep opacity low so numbers stay primary.
  static Widget cornerWatermark(
    IconData icon, {
    double size = 92,
    double opacity = 0.085,
  }) {
    return Align(
      alignment: Alignment.bottomRight,
      child: Padding(
        padding: const EdgeInsets.only(right: 6, bottom: 6),
        child: Icon(
          icon,
          size: size,
          color: Colors.white.withValues(alpha: opacity),
        ),
      ),
    );
  }

  static Widget dashboardWatermark() =>
      cornerWatermark(Icons.receipt_long_rounded);
  static Widget goalsWatermark() => cornerWatermark(Icons.flag_rounded);
  static Widget splitWatermark() => cornerWatermark(Icons.call_split_rounded);
  static Widget profileWatermark() => cornerWatermark(Icons.person_rounded);
}
