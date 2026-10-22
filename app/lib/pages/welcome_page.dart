import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:papyrus/auth/offline_link.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/widgets/auth/auth_branding.dart';
import 'package:papyrus/widgets/titled_divider.dart';

class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width >= Breakpoints.desktopSmall;

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/images/welcome-illustration.png',
              fit: BoxFit.cover,
              alignment: isDesktop ? Alignment.centerLeft : Alignment.topCenter,
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    (isDark ? const Color(0xCC18161D) : const Color(0x885654A8)),
                    (isDark ? const Color(0xE61A1720) : const Color(0xC03E3C8F)),
                    (isDark ? const Color(0xF518161C) : const Color(0xE01F1D2B)),
                  ],
                  stops: const [0.0, 0.55, 1.0],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: isDesktop ? const Alignment(0.75, -0.2) : const Alignment(0, -0.45),
                  radius: isDesktop ? 1.2 : 1.0,
                  colors: [theme.colorScheme.primary.withValues(alpha: 0.12), Colors.transparent],
                ),
              ),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (isDesktop) {
                  final minDesktopHeight = constraints.maxHeight - (Spacing.xl * 2);

                  return SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Spacing.pageMarginsDesktop * 2,
                      vertical: Spacing.xl,
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: minDesktopHeight > 0 ? minDesktopHeight : 0),
                      child: const _DesktopWelcomeContent(),
                    ),
                  );
                }

                return CustomScrollView(
                  slivers: [
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: Spacing.pageMarginsTablet,
                          vertical: Spacing.md,
                        ),
                        child: _MobileWelcomeContent(maxHeight: constraints.maxHeight - (Spacing.md * 2)),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _DesktopWelcomeContent extends StatelessWidget {
  const _DesktopWelcomeContent();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: Container(
          padding: const EdgeInsets.all(Spacing.lg),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.55)),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 24, offset: const Offset(0, 8)),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AuthBranding.hero(
                textColor: theme.colorScheme.onSurface,
                fontSize: 36,
                iconSize: 80,
                direction: Axis.vertical,
                spacing: 0,
              ),
              const SizedBox(height: Spacing.lg),
              const _WelcomeActions(center: true, compact: true, useSurfaceColors: true, isDesktop: true),
            ],
          ),
        ),
      ),
    );
  }
}

class _MobileWelcomeContent extends StatelessWidget {
  final double maxHeight;

  const _MobileWelcomeContent({required this.maxHeight});

  @override
  Widget build(BuildContext context) {
    final isShortScreen = maxHeight < 760;

    return Column(
      children: [
        Spacer(flex: isShortScreen ? 2 : 3),
        AuthBranding.hero(
          textColor: Colors.white,
          fontSize: isShortScreen ? 32 : 36,
          iconSize: isShortScreen ? 72 : 88,
          direction: Axis.vertical,
          spacing: 0,
        ),
        const SizedBox(height: Spacing.lg),
        const _WelcomeActions(center: true, compact: true),
        Spacer(flex: isShortScreen ? 3 : 4),
        SizedBox(height: isShortScreen ? Spacing.lg : Spacing.xl),
      ],
    );
  }
}

class _WelcomeActions extends StatelessWidget {
  final bool center;
  final bool compact;
  final bool useSurfaceColors;
  final bool isDesktop;

  const _WelcomeActions({
    required this.center,
    this.compact = false,
    this.useSurfaceColors = false,
    this.isDesktop = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CreateAccountButton(isDesktop: isDesktop),
        const SizedBox(height: Spacing.md),
        _SignInButton(isDesktop: isDesktop, useSurfaceColors: useSurfaceColors),
        SizedBox(height: compact ? Spacing.sm : Spacing.sm),
        TitledDivider(title: 'or', verticalPadding: compact ? Spacing.sm : Spacing.md),
        OfflineModeLink(center: center),
      ],
    );
  }
}

class _CreateAccountButton extends StatelessWidget {
  final bool isDesktop;

  const _CreateAccountButton({required this.isDesktop});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ElevatedButton(
      onPressed: () => context.go('/register'),
      style: ElevatedButton.styleFrom(
        minimumSize: Size.fromHeight(
          isDesktop ? ComponentSizes.buttonHeightDesktop : ComponentSizes.buttonHeightMobile,
        ),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
        elevation: AppElevation.level2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.button)),
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.buttonPaddingHorizontal,
          vertical: Spacing.buttonPaddingVertical,
        ),
      ),
      child: const Text('Create an account', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
    );
  }
}

class _SignInButton extends StatelessWidget {
  final bool isDesktop;
  final bool useSurfaceColors;

  const _SignInButton({required this.isDesktop, required this.useSurfaceColors});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return OutlinedButton(
      onPressed: () => context.go('/login'),
      style: OutlinedButton.styleFrom(
        minimumSize: Size.fromHeight(
          isDesktop ? ComponentSizes.buttonHeightDesktop : ComponentSizes.buttonHeightMobile,
        ),
        foregroundColor: useSurfaceColors ? theme.colorScheme.onSurface : Colors.white,
        side: BorderSide(
          color: useSurfaceColors ? theme.colorScheme.outline : Colors.white.withValues(alpha: 0.38),
          width: BorderWidths.thin,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.button)),
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.buttonPaddingHorizontal,
          vertical: Spacing.buttonPaddingVertical,
        ),
      ),
      child: const Text('Sign in', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
    );
  }
}
