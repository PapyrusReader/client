import 'package:flutter/material.dart';
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
          child: AuthBranding(
            textColor: Colors.white,
            iconOutlineColor: Color(0x998F89FF),
            iconSize: 48,
            fontSize: 32,
            iconOutlineWidth: 2.5,
            shadowColor: Color(0x40000000),
            textShadowColor: Color(0x59000000),
            textShadowOffset: Offset(0, 2),
            textShadowBlurRadius: 6,
          ),
        ),
      ],
    );
  }
}

/// Compact hero header for mobile auth pages with branding overlay.
class CompactAuthHeader extends StatelessWidget {
  final bool isDark;
  final double height;

  const CompactAuthHeader({super.key, this.isDark = false, this.height = 180});

  @override
  Widget build(BuildContext context) {
    final gradientStart = isDark ? AuthColors.gradientStartDark : AuthColors.gradientStartLight;
    final gradientEnd = isDark ? AuthColors.gradientEndDark : AuthColors.gradientEndLight;

    return ClipPath(
      clipper: CurvedBottomClipper(curveHeight: 30),
      child: SizedBox(
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Gradient background
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
              child: Image.asset(
                'assets/images/auth-illustration.png',
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
              ),
            ),
            const Positioned(
              top: Spacing.lg,
              left: Spacing.lg,
              right: Spacing.lg,
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: AuthBranding(
                    textColor: Colors.white,
                    iconOutlineColor: Color(0x998F89FF),
                    iconSize: 70,
                    fontSize: 40,
                    iconOutlineWidth: 3,
                    shadowColor: Color(0x40000000),
                    textShadowColor: Color(0x59000000),
                    textShadowOffset: Offset(0, 2),
                    textShadowBlurRadius: 6,
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
