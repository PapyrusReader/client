import 'package:flutter/material.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/widgets/auth/auth_hero_panel.dart';

/// Mobile auth layout with a scrolling hero and a form that fills available space.
class MobileAuthLayout extends StatelessWidget {
  final String heading;
  final IconData? headingIcon;
  final String subtitle;

  /// The form widget (login form, register form, etc.)
  final Widget form;

  /// Widgets placed below the form (divider, social button, switch link).
  final List<Widget> footer;

  /// Secondary navigation kept near the bottom when the form has spare space.
  final List<Widget> bottomActions;

  /// Whether to show branding, heading, and subtitle above the form.
  final bool showHeader;
  final bool announceSubtitle;
  final double headerBottomSpacing;

  const MobileAuthLayout({
    super.key,
    required this.heading,
    this.headingIcon,
    required this.subtitle,
    required this.form,
    required this.footer,
    this.bottomActions = const [],
    this.showHeader = true,
    this.announceSubtitle = false,
    this.headerBottomSpacing = Spacing.lg,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        top: false,
        child: CustomScrollView(
          slivers: [
            SliverAuthHeader(isDark: isDark, collapsed: keyboardVisible),
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Spacing.lg, vertical: Spacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisAlignment: keyboardVisible ? MainAxisAlignment.start : MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (showHeader) ...[
                            _AuthHeading(
                              text: heading,
                              icon: headingIcon,
                              style: theme.textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                            Semantics(
                              liveRegion: announceSubtitle,
                              child: Text(
                                subtitle,
                                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                              ),
                            ),
                            SizedBox(height: headerBottomSpacing),
                          ],
                          form,
                          ...footer,
                        ],
                      ),
                    ),
                    ...bottomActions,
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Desktop auth layout: hero panel (60%) + form panel (40%).
/// Includes a swap button to flip hero/form positions.
class DesktopAuthLayout extends StatefulWidget {
  final String heading;
  final IconData? headingIcon;
  final String subtitle;

  /// The form widget (login form, register form, etc.)
  final Widget form;

  /// Widgets placed below the form (divider, social button, switch link).
  final List<Widget> footer;

  /// Whether to show branding, heading, and subtitle above the form.
  final bool showHeader;
  final bool announceSubtitle;
  final double headerBottomSpacing;

  const DesktopAuthLayout({
    super.key,
    required this.heading,
    this.headingIcon,
    required this.subtitle,
    required this.form,
    required this.footer,
    this.showHeader = true,
    this.announceSubtitle = false,
    this.headerBottomSpacing = Spacing.xl,
  });

  /// Persists swap state across page navigations within the same session.
  static bool _isSwapped = false;

  @override
  State<DesktopAuthLayout> createState() => _DesktopAuthLayoutState();
}

class _DesktopAuthLayoutState extends State<DesktopAuthLayout> {
  void _toggleSwap() {
    setState(() {
      DesktopAuthLayout._isSwapped = !DesktopAuthLayout._isSwapped;
    });
  }

  Widget _buildFormPanel(ThemeData theme) {
    final isSwapped = DesktopAuthLayout._isSwapped;

    return FocusTraversalOrder(
      order: const NumericFocusOrder(1),
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 24,
              offset: Offset(isSwapped ? 4 : -4, 0),
            ),
          ],
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(ComponentSizes.authFormPanelPadding),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: ComponentSizes.authFormPanelMaxWidth),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.showHeader) ...[
                    // const AuthBranding(),
                    const SizedBox(height: Spacing.md),
                    _AuthHeading(
                      text: widget.heading,
                      icon: widget.headingIcon,
                      style: theme.textTheme.headlineLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    Semantics(
                      liveRegion: widget.announceSubtitle,
                      child: Text(
                        widget.subtitle,
                        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ),
                    SizedBox(height: widget.headerBottomSpacing),
                  ],
                  widget.form,
                  ...widget.footer,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isSwapped = DesktopAuthLayout._isSwapped;
    final hero = Expanded(flex: 6, child: AuthHeroPanel(isDark: isDark));
    final form = Expanded(flex: 4, child: _buildFormPanel(theme));

    return FocusTraversalGroup(
      policy: OrderedTraversalPolicy(),
      child: Scaffold(
        backgroundColor: theme.colorScheme.surface,
        body: Stack(
          children: [
            Row(children: isSwapped ? [form, hero] : [hero, form]),
            Positioned(
              left: isSwapped ? null : 0,
              right: isSwapped ? 0 : null,
              top: 0,
              bottom: 0,
              child: FocusTraversalOrder(
                order: const NumericFocusOrder(2),
                child: _SwapPanelsButton(isSwapped: isSwapped, onPressed: _toggleSwap),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Circular button that sits at the boundary between hero and form panels.
class _SwapPanelsButton extends StatelessWidget {
  final bool isSwapped;
  final VoidCallback onPressed;

  const _SwapPanelsButton({required this.isSwapped, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        // Position at 60% from the left (hero/form boundary)
        final totalWidth = MediaQuery.of(context).size.width;
        final boundaryOffset = totalWidth * 0.6;

        return SizedBox(
          width: totalWidth,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Transform.translate(
              offset: Offset(isSwapped ? totalWidth - boundaryOffset - 20 : boundaryOffset - 20, 0),
              child: SizedBox(
                width: 40,
                height: 40,
                child: Material(
                  elevation: 4,
                  shape: const CircleBorder(),
                  color: theme.colorScheme.surface,
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: onPressed,
                    child: Icon(Icons.swap_horiz, size: 20, color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _AuthHeading extends StatelessWidget {
  final String text;
  final IconData? icon;
  final TextStyle? style;

  const _AuthHeading({required this.text, required this.style, this.icon});

  @override
  Widget build(BuildContext context) {
    final heading = Text(text, style: style);
    final textScaler = MediaQuery.textScalerOf(context);
    final iconSize = textScaler.scale((style?.fontSize ?? 24) + Spacing.xs);

    return Semantics(
      header: true,
      child: icon == null
          ? heading
          : Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                ExcludeSemantics(
                  child: Transform.translate(
                    // Account for the circle inset and the heading font’s optical baseline.
                    offset: Offset(0, iconSize * 2 / 24 + textScaler.scale(2)),
                    child: Icon(
                      icon,
                      size: iconSize,
                      applyTextScaling: false,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
                const SizedBox(width: Spacing.sm),
                Expanded(child: heading),
              ],
            ),
    );
  }
}
