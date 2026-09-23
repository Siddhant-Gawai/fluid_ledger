import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Extended pill used as [Scaffold.floatingActionButton] content.
///
/// Pair with [Scaffold.floatingActionButtonAnimator] =
/// [FloatingActionButtonAnimator.noAnimation] so the wide pill is not run
/// through the default scale-to-zero FAB motion (which looks wrong on pills).
class FabPillButton extends StatelessWidget {
  const FabPillButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon = Icons.add_rounded,
    required this.gradientColors,
  });

  final String label;
  final VoidCallback onTap;
  final IconData icon;
  final List<Color> gradientColors;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(50),
          splashColor: Colors.white24,
          highlightColor: Colors.white10,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(50),
              gradient: LinearGradient(colors: gradientColors),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: Colors.white, size: 22),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: GoogleFonts.manrope(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
