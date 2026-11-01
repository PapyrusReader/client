import 'package:flutter/material.dart';
import 'package:papyrus/themes/design_tokens.dart';

/// Mobile toolbar geometry shared by scaffold app bars and inline page headers.
/// The containing page or scaffold owns the system safe-area inset.
class AppPageToolbar extends StatelessWidget {
  const AppPageToolbar({super.key, this.leading, this.content, this.actions = const []});

  final Widget? leading;
  final Widget? content;
  final List<Widget> actions;

  static const padding = EdgeInsets.symmetric(horizontal: Spacing.md, vertical: Spacing.sm);

  static double height(BuildContext context) {
    final painter = TextPainter(
      text: TextSpan(text: 'Search', style: Theme.of(context).textTheme.bodyLarge),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();

    final searchHeight = painter.height + Spacing.sm * 2;
    painter.dispose();
    return padding.vertical + searchHeight.clamp(TouchTargets.mobileRecommended, double.infinity);
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: padding,
    child: ConstrainedBox(
      constraints: BoxConstraints(minHeight: height(context) - padding.vertical),
      child: IconTheme.merge(
        data: const IconThemeData(size: IconSizes.navigation),
        child: Row(
          children: [
            if (leading != null) ...[
              SizedBox.square(dimension: TouchTargets.mobileRecommended, child: leading),
              const SizedBox(width: Spacing.sm),
            ],
            Expanded(child: content ?? const SizedBox.shrink()),
            for (final action in actions) ...[
              const SizedBox(width: Spacing.sm),
              ConstrainedBox(
                constraints: const BoxConstraints(
                  minWidth: TouchTargets.mobileRecommended,
                  minHeight: TouchTargets.mobileRecommended,
                ),
                child: action,
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

/// Scaffold app bar using the same mobile toolbar as inline page headers.
class AppPageBar extends StatelessWidget implements PreferredSizeWidget {
  AppPageBar({
    super.key,
    required BuildContext context,
    this.title,
    this.leading,
    this.actions = const [],
    this.primary = true,
    this.automaticallyImplyLeading = true,
    this.backgroundColor,
    this.foregroundColor,
  }) : compact = MediaQuery.sizeOf(context).width < Breakpoints.desktopSmall,
       toolbarHeight = MediaQuery.sizeOf(context).width < Breakpoints.desktopSmall
           ? AppPageToolbar.height(context)
           : Theme.of(context).appBarTheme.toolbarHeight ?? kToolbarHeight;

  final double toolbarHeight;
  final bool compact;

  final Widget? title;
  final Widget? leading;
  final List<Widget> actions;
  final bool primary;
  final bool automaticallyImplyLeading;
  final Color? backgroundColor;
  final Color? foregroundColor;

  @override
  Size get preferredSize => Size.fromHeight(toolbarHeight);

  @override
  Widget build(BuildContext context) {
    Widget? navigation = leading;

    if (compact && navigation == null && automaticallyImplyLeading) {
      final route = ModalRoute.of(context);

      if (Scaffold.maybeOf(context)?.hasDrawer == true) {
        navigation = const DrawerButton();
      } else if (route?.impliesAppBarDismissal == true) {
        navigation = route is PageRoute && route.fullscreenDialog ? const CloseButton() : const BackButton();
      }
    }

    return AppBar(
      primary: primary,
      automaticallyImplyLeading: compact ? false : automaticallyImplyLeading,
      backgroundColor: backgroundColor,
      foregroundColor: foregroundColor,
      toolbarHeight: toolbarHeight,
      leading: compact ? null : navigation,
      iconTheme: compact
          ? IconThemeData(color: foregroundColor ?? Theme.of(context).colorScheme.onSurface, size: IconSizes.navigation)
          : null,
      centerTitle: compact ? false : null,
      titleSpacing: compact ? 0 : null,
      title: compact ? AppPageToolbar(leading: navigation, content: title, actions: actions) : title,
      actions: compact ? null : actions,
    );
  }
}
