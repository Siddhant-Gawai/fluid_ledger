import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _currentPage = 0;

  final _pages = const [
    _OnboardingPage(
      icon: Icons.auto_awesome,
      iconBgColor: Color(0xFF24389c),
      title: 'AI Tracking.',
      titleAccent: 'Your financial guardian.',
      description: 'The Fluid Ledger automatically tracks every transaction directly from your messages. No manual entry needed.',
      mockWidget: _SmsPreviewCard(),
    ),
    _OnboardingPage(
      icon: Icons.insights,
      iconBgColor: Color(0xFF006a6a),
      title: 'Smart Insights.',
      titleAccent: 'Know where your money goes.',
      description: 'Get personalized insights to optimize your spending and unlock growth opportunities. AI-powered, privacy-first.',
      mockWidget: _InsightPreviewCard(),
    ),
    _OnboardingPage(
      icon: Icons.savings,
      iconBgColor: Color(0xFF313e7e),
      title: 'Save More.',
      titleAccent: 'Hit your goals with ease.',
      description: 'Set budgets and track saving milestones effortlessly. Your ethereal curator manages the math.',
      mockWidget: _BudgetPreviewCard(),
    ),
  ];

  void _next() {
    if (_currentPage < _pages.length - 1) {
      _controller.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    } else {
      context.go('/auth');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colors.surface,
      body: SafeArea(
        child: Column(
          children: [
            // Top bar
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('The Fluid Ledger', style: GoogleFonts.manrope(fontSize: 18, fontWeight: FontWeight.w800, color: colors.primary)),
                  GestureDetector(
                    onTap: () => context.go('/auth'),
                    child: Text('SKIP', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: colors.onSurfaceVariant, letterSpacing: 0.5)),
                  ),
                ],
              ),
            ),

            // Page view
            Expanded(
              child: PageView.builder(
                controller: _controller,
                onPageChanged: (i) => setState(() => _currentPage = i),
                itemCount: _pages.length,
                itemBuilder: (_, i) => _pages[i],
              ),
            ),

            // Dots + button
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
              child: Column(
                children: [
                  // Page indicator
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(_pages.length, (i) {
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: i == _currentPage ? 24 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: i == _currentPage ? colors.primary : colors.outlineVariant.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 28),

                  // CTA button
                  SizedBox(
                    width: double.infinity,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        gradient: LinearGradient(colors: [colors.primary, colors.primaryContainer]),
                        boxShadow: [BoxShadow(color: colors.primary.withValues(alpha: 0.25), blurRadius: 16, offset: const Offset(0, 6))],
                      ),
                      child: ElevatedButton(
                        onPressed: _next,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _currentPage == _pages.length - 1 ? 'Get Started' : 'Next',
                              style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white),
                            ),
                            const SizedBox(width: 8),
                            const Icon(Icons.arrow_forward, size: 18, color: Colors.white),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Onboarding page template
// ---------------------------------------------------------------------------

class _OnboardingPage extends StatelessWidget {
  final IconData icon;
  final Color iconBgColor;
  final String title;
  final String titleAccent;
  final String description;
  final Widget mockWidget;

  const _OnboardingPage({
    required this.icon,
    required this.iconBgColor,
    required this.title,
    required this.titleAccent,
    required this.description,
    required this.mockWidget,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Mock preview card
          mockWidget,
          const SizedBox(height: 40),

          // Title
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: '$title\n', style: GoogleFonts.manrope(fontSize: 32, fontWeight: FontWeight.w800, color: colors.onSurface, height: 1.2)),
                TextSpan(text: titleAccent, style: GoogleFonts.manrope(fontSize: 32, fontWeight: FontWeight.w800, color: colors.primary, fontStyle: FontStyle.italic, height: 1.2)),
              ],
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),

          // Description
          Text(
            description,
            style: GoogleFonts.inter(fontSize: 15, color: colors.onSurfaceVariant, height: 1.6),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Preview cards for each onboarding page
// ---------------------------------------------------------------------------

class _SmsPreviewCard extends StatelessWidget {
  const _SmsPreviewCard();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: colors.primary.withValues(alpha: 0.06), blurRadius: 24, offset: const Offset(0, 8))],
      ),
      child: Column(
        children: [
          // SMS bubble
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: colors.surfaceContainerLow, borderRadius: BorderRadius.circular(16)),
            child: Text(
              'HDFC Bank: Rs. 1,450 spent on Zomato using Card ending 4402.',
              style: GoogleFonts.inter(fontSize: 13, color: colors.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: 12),
          // Detected card
          Row(
            children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(color: const Color(0xFFE23744).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                child: const Center(child: Text('🔴', style: TextStyle(fontSize: 18))),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Zomato', style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w700)),
                    Text('Food & Dining', style: GoogleFonts.inter(fontSize: 12, color: colors.onSurfaceVariant)),
                  ],
                ),
              ),
              Text('₹1,450', style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w800, color: colors.primary)),
            ],
          ),
        ],
      ),
    );
  }
}

class _InsightPreviewCard extends StatelessWidget {
  const _InsightPreviewCard();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: colors.primary.withValues(alpha: 0.06), blurRadius: 24, offset: const Offset(0, 8))],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(color: colors.secondaryContainer.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(12)),
            child: Row(
              children: [
                Icon(Icons.trending_down, size: 18, color: colors.secondary),
                const SizedBox(width: 8),
                Text('Save ₹2,400/month', style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w700, color: colors.secondary)),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _chip(context, Icons.auto_awesome, 'AI Analysis', colors.primary),
              const SizedBox(width: 10),
              _chip(context, Icons.shield_outlined, 'Spending Guard', colors.secondary),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(label, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }
}

class _BudgetPreviewCard extends StatelessWidget {
  const _BudgetPreviewCard();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: colors.primary.withValues(alpha: 0.06), blurRadius: 24, offset: const Offset(0, 8))],
      ),
      child: Column(
        children: [
          Text('₹45,00,000', style: GoogleFonts.manrope(fontSize: 28, fontWeight: FontWeight.w800, color: colors.onSurface)),
          const SizedBox(height: 4),
          Text('NEW HOME GOAL', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: colors.onSurfaceVariant, letterSpacing: 1)),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _miniCard(context, Icons.schedule, '₹95K', 'Travel Fund', colors.primary),
              const SizedBox(width: 12),
              _miniCard(context, Icons.bolt, '₹2.4L', 'Emergency', colors.secondary),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniCard(BuildContext context, IconData icon, String amount, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(amount, style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w700, color: color)),
              Text(label, style: GoogleFonts.inter(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ],
          ),
        ],
      ),
    );
  }
}
