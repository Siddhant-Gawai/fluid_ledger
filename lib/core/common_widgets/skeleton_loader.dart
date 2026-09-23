import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

/// Base shimmer wrapper — wraps any child with a shimmer effect
class ShimmerWrap extends StatelessWidget {
  final Widget child;

  const ShimmerWrap({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Shimmer.fromColors(
      baseColor: colors.surfaceContainerHigh,
      highlightColor: colors.surfaceContainerLowest,
      child: child,
    );
  }
}

/// A single skeleton box with rounded corners
class SkeletonBox extends StatelessWidget {
  final double width;
  final double height;
  final double radius;

  const SkeletonBox({
    super.key,
    required this.width,
    required this.height,
    this.radius = 12,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// A skeleton line (text placeholder)
class SkeletonLine extends StatelessWidget {
  final double width;
  final double height;

  const SkeletonLine({
    super.key,
    this.width = double.infinity,
    this.height = 14,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}

/// A skeleton circle (avatar placeholder)
class SkeletonCircle extends StatelessWidget {
  final double size;

  const SkeletonCircle({super.key, this.size = 44});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pre-built skeleton screens
// ---------------------------------------------------------------------------

class DashboardSkeleton extends StatelessWidget {
  const DashboardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ShimmerWrap(
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SkeletonBox(width: double.infinity, height: 190, radius: 24),
            const SizedBox(height: 16),
            const SkeletonBox(width: double.infinity, height: 160, radius: 24),
            const SizedBox(height: 16),
            ...List.generate(
              3,
              (_) => const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: SkeletonBox(
                  width: double.infinity,
                  height: 56,
                  radius: 16,
                ),
              ),
            ),
            const SizedBox(height: 16),
            const SkeletonBox(width: double.infinity, height: 150, radius: 24),
          ],
        ),
      ),
    );
  }
}

class HistorySkeleton extends StatelessWidget {
  const HistorySkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ShimmerWrap(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Month pills
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(
                4,
                (_) => const SkeletonBox(width: 65, height: 34, radius: 10),
              ),
            ),
            const SizedBox(height: 10),
            // Budget bar
            const SkeletonBox(width: double.infinity, height: 42, radius: 14),
            const SizedBox(height: 10),
            // Search
            const SkeletonBox(width: double.infinity, height: 42, radius: 14),
            const SizedBox(height: 10),
            // Filter chips
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(
                3,
                (_) => const SkeletonBox(width: 60, height: 32, radius: 10),
              ),
            ),
            const SizedBox(height: 12),
            // Transaction rows
            ...List.generate(
              4,
              (_) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: const SkeletonBox(
                  width: double.infinity,
                  height: 56,
                  radius: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ProfileSkeleton extends StatelessWidget {
  const ProfileSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ShimmerWrap(
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // [GradientHeroCard] / profile header: radius 28, same vertical rhythm
            const SkeletonBox(width: double.infinity, height: 230, radius: 28),
            const SizedBox(height: 16),
            const SkeletonBox(width: double.infinity, height: 168, radius: 20),
            const SizedBox(height: 16),
            const SkeletonBox(width: double.infinity, height: 76, radius: 20),
          ],
        ),
      ),
    );
  }
}

class GroupDetailSkeleton extends StatelessWidget {
  const GroupDetailSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ShimmerWrap(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Total card
            const SkeletonBox(width: double.infinity, height: 80, radius: 18),
            const SizedBox(height: 12),
            // Cards
            ...List.generate(
              4,
              (_) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: const SkeletonBox(
                  width: double.infinity,
                  height: 60,
                  radius: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PageSkeleton extends StatelessWidget {
  final int rows;
  const PageSkeleton({super.key, this.rows = 6});

  @override
  Widget build(BuildContext context) {
    return ShimmerWrap(
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        itemCount: rows,
        itemBuilder: (_, i) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: SkeletonBox(
            width: double.infinity,
            height: i == 0 ? 84 : 64,
            radius: 16,
          ),
        ),
      ),
    );
  }
}

class GridPageSkeleton extends StatelessWidget {
  const GridPageSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ShimmerWrap(
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        itemCount: 6,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.06,
        ),
        itemBuilder: (_, __) =>
            const SkeletonBox(width: double.infinity, height: 120, radius: 18),
      ),
    );
  }
}
