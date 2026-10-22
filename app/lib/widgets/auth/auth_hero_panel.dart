import 'package:flutter/material.dart';
import 'package:papyrus/themes/app_motion.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/widgets/auth/auth_branding.dart';
import 'package:papyrus/widgets/auth/curved_bottom_clipper.dart';

/// Hero gradient colors for auth pages.
class AuthColors {
  AuthColors._();

  // Light mode gradient
  static const Color gradientStartLight = Color(0xFF5654A8);
  static const Color gradientEndLight = Color(0xFF3E3C8F);

  // Dark mode gradient
  static const Color gradientStartDark = Color(0xFF3E3C8F);
  static const Color gradientEndDark = Color(0xFF272377);
}

/// Desktop hero panel with illustration background and branding overlay.
class AuthHeroPanel extends StatelessWidget {
  final bool isDark;

  const AuthHeroPanel({super.key, this.isDark = false});

  @override
  Widget build(BuildContext context) {
    final gradientStart = isDark ? AuthColors.gradientStartDark : AuthColors.gradientStartLight;
    final gradientEnd = isDark ? AuthColors.gradientEndDark : AuthColors.gradientEndLight;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Gradient background (fallback)
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [gradientStart, gradientEnd],
            ),
          ),
        ),
        Positioned.fill(
          child: Image.asset('assets/images/auth-illustration.png', fit: BoxFit.cover, alignment: Alignment.center),
        ),
        const Positioned(
          top: Spacing.xl,
          left: Spacing.xl,
          child: AuthBranding.hero(
            iconSize: 48,
            fontSize: 32,
          ),
        ),
      ],
    );
  }
}

class SliverAuthHeader extends StatelessWidget {
  final bool isDark;
  final bool collapsed;

  const SliverAuthHeader({super.key, this.isDark = false, this.collapsed = false});

  @override
  Widget build(BuildContext context) {
    final minimumHeight = MediaQuery.paddingOf(context).top + CompactAuthHeader.collapsedHeight;
    final expandedHeight = ComponentSizes.mobileHeroHeight < minimumHeight
        ? minimumHeight
        : ComponentSizes.mobileHeroHeight;
    final target = collapsed ? 1.0 : 0.0;

    if (AppMotion.disabled(context)) {
      return SliverToBoxAdapter(
        child: CompactAuthHeader(
          isDark: isDark,
          height: collapsed ? minimumHeight : expandedHeight,
          collapseProgress: target,
        ),
      );
    }

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: target, end: target),
      duration: AnimationDurations.standard,
      curve: Curves.easeInOut,
      builder: (context, keyboardProgress, child) => SliverPersistentHeader(
        delegate: _AuthHeaderDelegate(
          isDark: isDark,
          expandedHeight: expandedHeight,
          minimumHeight: minimumHeight,
          keyboardProgress: keyboardProgress,
        ),
      ),
    );
  }
}

class _AuthHeaderDelegate extends SliverPersistentHeaderDelegate {
  final bool isDark;
  final double expandedHeight;
  final double minimumHeight;
  final double keyboardProgress;

  const _AuthHeaderDelegate({
    required this.isDark,
    required this.expandedHeight,
    required this.minimumHeight,
    required this.keyboardProgress,
  });

  @override
  double get minExtent => minimumHeight;

  @override
  double get maxExtent => expandedHeight * (1 - keyboardProgress) + minimumHeight * keyboardProgress;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final collapseDistance = expandedHeight - minimumHeight;
    final scrollProgress = shrinkOffset / (collapseDistance > 0 ? collapseDistance : CompactAuthHeader.collapsedHeight);

    return CompactAuthHeader(
      isDark: isDark,
      height: (maxExtent - shrinkOffset).clamp(minExtent, maxExtent),
      collapseProgress: (keyboardProgress + scrollProgress).clamp(0.0, 1.0),
    );
  }

  @override
  bool shouldRebuild(covariant _AuthHeaderDelegate oldDelegate) =>
      isDark != oldDelegate.isDark ||
      expandedHeight != oldDelegate.expandedHeight ||
      minimumHeight != oldDelegate.minimumHeight ||
      keyboardProgress != oldDelegate.keyboardProgress;
}

/// Branding and illustration shared by the expanded and collapsed auth header.
class CompactAuthHeader extends StatelessWidget {
  final bool isDark;
  final double height;
  final double collapseProgress;

  const CompactAuthHeader({
    super.key,
    this.isDark = false,
    this.height = ComponentSizes.mobileHeroHeight,
    this.collapseProgress = 0,
  }) : assert(collapseProgress >= 0 && collapseProgress <= 1);

  static const collapsedHeight = 64.0;

  @override
  Widget build(BuildContext context) {
    final gradientStart = isDark ? AuthColors.gradientStartDark : AuthColors.gradientStartLight;
    final gradientEnd = isDark ? AuthColors.gradientEndDark : AuthColors.gradientEndLight;
    final expanded = 1 - collapseProgress;

    return ClipPath(
      clipper: CurvedBottomClipper(curveHeight: 30 * expanded),
      child: SizedBox(
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [gradientStart, gradientEnd],
                ),
              ),
            ),
            Positioned.fill(
              child: Opacity(
                opacity: expanded,
                child: Image.asset(
                  'assets/images/auth-illustration.png',
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                ),
              ),
            ),
            Positioned(
              top: MediaQuery.paddingOf(context).top,
              bottom: Spacing.sm * expanded,
              left: Spacing.lg,
              right: Spacing.lg,
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: AuthBranding.hero(
                    iconSize: 70 * expanded + 32 * collapseProgress,
                    fontSize: 40 * expanded + 24 * collapseProgress,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
