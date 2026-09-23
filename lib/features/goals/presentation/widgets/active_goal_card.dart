import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../../core/common_widgets/premium_surface_card.dart';
import '../../../../core/common_widgets/skeleton_loader.dart';
import '../../data/goals_repository.dart';

/// Stable accent per goal — hash on [Goal.id].
Color goalAccentFor(Goal goal) {
  const palette = <Color>[
    Color(0xFF3949AB),
    Color(0xFF00897B),
    Color(0xFFD84315),
    Color(0xFF7B1FA2),
    Color(0xFFC2185B),
    Color(0xFFF57C00),
    Color(0xFF00695C),
    Color(0xFF5E35B1),
    Color(0xFF283593),
    Color(0xFFAD1457),
  ];
  var h = 0;
  final key = goal.id?.trim();
  if (key != null && key.isNotEmpty) {
    for (final c in key.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return palette[h % palette.length];
  }
  final fallback = '${goal.name}_${goal.createdAt ?? ''}';
  for (final c in fallback.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return palette[h % palette.length];
}

class ActiveGoalCard extends StatelessWidget {
  final Goal goal;
  final NumberFormat fmt;
  final VoidCallback onTap;
  final VoidCallback onTopUp;
  final VoidCallback? onPinToggle;

  const ActiveGoalCard({
    super.key,
    required this.goal,
    required this.fmt,
    required this.onTap,
    required this.onTopUp,
    this.onPinToggle,
  });

  Color get _accentColor => goalAccentFor(goal);

  int? _estimateDaysToGoal() {
    if (goal.isCompleted) return 0;
    final created = DateTime.tryParse(goal.createdAt ?? '');
    if (created == null) return null;
    final elapsedDays = DateTime.now()
        .difference(created)
        .inDays
        .clamp(1, 10000);
    if (goal.savedAmount <= 0) return null;
    final pacePerDay = goal.savedAmount / elapsedDays;
    if (pacePerDay <= 0) return null;
    final remaining = (goal.targetAmount - goal.savedAmount).clamp(
      0,
      double.infinity,
    );
    return (remaining / pacePerDay).ceil();
  }

  static String formatDeadline(String iso, {String fallback = ''}) {
    try {
      final dt = DateTime.parse(iso);
      return DateFormat('d MMM yyyy').format(dt);
    } catch (_) {
      return fallback.isEmpty ? iso : fallback;
    }
  }

  @override
  Widget build(BuildContext context) {
    return PremiumSurfaceCard(
      variant: PremiumSurfaceVariant.goals,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      radius: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: onTap,
            behavior: HitTestBehavior.opaque,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _accentColor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(
                      goal.emoji,
                      style: const TextStyle(fontSize: 22),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              goal.name,
                              style: GoogleFonts.manrope(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (onPinToggle != null && !goal.isCompleted)
                            GestureDetector(
                              onTap: onPinToggle,
                              behavior: HitTestBehavior.opaque,
                              child: Padding(
                                padding: const EdgeInsets.only(left: 8),
                                child: Icon(
                                  goal.pinned
                                      ? Icons.push_pin_rounded
                                      : Icons.push_pin_outlined,
                                  size: 18,
                                  color: goal.pinned
                                      ? _accentColor.withValues(alpha: 0.95)
                                      : _accentColor.withValues(alpha: 0.55),
                                ),
                              ),
                            ),
                          if (goal.isCompleted)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFF43A047,
                                ).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'Done!',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF43A047),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '₹${fmt.format(goal.savedAmount.round())} / ₹${fmt.format(goal.targetAmount.round())}',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                        ),
                      ),
                      if (!goal.isCompleted) ...[
                        const SizedBox(height: 2),
                        Text(
                          '₹${fmt.format((goal.targetAmount - goal.savedAmount).clamp(0, double.infinity).round())} away',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: _accentColor.withValues(alpha: 0.9),
                          ),
                        ),
                        if (_estimateDaysToGoal() != null)
                          Text(
                            'At current pace: ${_estimateDaysToGoal()} day${_estimateDaysToGoal() == 1 ? '' : 's'}',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: Colors.grey.shade500,
                            ),
                          ),
                      ],
                      if (goal.deadline != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          'By ${formatDeadline(goal.deadline!)}',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: Colors.grey.shade400,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                GoalProgressRing(progress: goal.progress, color: _accentColor),
              ],
            ),
          ),
          if (!goal.isCompleted) ...[
            const SizedBox(height: 12),
            GestureDetector(
              onTap: onTopUp,
              behavior: HitTestBehavior.opaque,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      _accentColor,
                      _accentColor.withValues(alpha: 0.78),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: _accentColor.withValues(alpha: 0.28),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.add_rounded,
                      size: 16,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Add money',
                      style: GoogleFonts.manrope(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class GoalCardSkeleton extends StatelessWidget {
  const GoalCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ShimmerWrap(
      child: PremiumSurfaceCard(
        variant: PremiumSurfaceVariant.goals,
        padding: const EdgeInsets.all(16),
        radius: 18,
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SkeletonLine(width: 150, height: 14),
            SizedBox(height: 10),
            SkeletonLine(width: 104, height: 24),
            SizedBox(height: 10),
            SkeletonBox(width: double.infinity, height: 8, radius: 6),
            SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: SkeletonLine(width: 96, height: 12)),
                SizedBox(width: 12),
                Expanded(child: SkeletonLine(width: 96, height: 12)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class GoalProgressRing extends StatelessWidget {
  final double progress;
  final Color color;

  const GoalProgressRing({
    super.key,
    required this.progress,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final pct = (progress * 100).round().clamp(0, 100);
    return SizedBox(
      width: 48,
      height: 48,
      child: CustomPaint(
        painter: GoalRingPainter(
          progress: progress.clamp(0.0, 1.0),
          color: color,
        ),
        child: Center(
          child: Text(
            '$pct%',
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}

class GoalRingPainter extends CustomPainter {
  final double progress;
  final Color color;

  GoalRingPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final radius = (size.width - 6) / 2;
    final rect = Rect.fromCircle(center: Offset(cx, cy), radius: radius);
    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi,
      false,
      Paint()
        ..color = color.withValues(alpha: 0.12)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round,
    );
    if (progress > 0) {
      canvas.drawArc(
        rect,
        -math.pi / 2,
        2 * math.pi * progress,
        false,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(GoalRingPainter old) =>
      old.progress != progress || old.color != color;
}
