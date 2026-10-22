import 'package:flutter/material.dart';
import 'package:papyrus/themes/design_tokens.dart';

double appMobileToolbarHeight(BuildContext context) {
  final painter = TextPainter(
    text: TextSpan(text: 'Search', style: Theme.of(context).textTheme.bodyLarge),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
  )..layout();

  final searchHeight = painter.height + Spacing.sm * 2;
  painter.dispose();
  return Spacing.md * 2 + searchHeight.clamp(TouchTargets.mobileRecommended, double.infinity);
}

/// Leading control for a mobile header that already has page padding.
class AppPageLeading extends StatelessWidget {
  const AppPageLeading({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: TouchTargets.mobileRecommended,
    height: appMobileToolbarHeight(context) - Spacing.md * 2,
    child: Center(
      child: SizedBox.square(dimension: TouchTargets.mobileRecommended, child: child),
    ),
  );
}

/// Matches the navigation position of a padded mobile search toolbar.
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
           ? appMobileToolbarHeight(context)
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
      leadingWidth: compact ? Spacing.md + TouchTargets.mobileRecommended + Spacing.sm : null,
      leading: compact && navigation != null
          ? Padding(
              padding: const EdgeInsets.only(left: Spacing.md, right: Spacing.sm),
              child: Center(
                child: SizedBox.square(dimension: TouchTargets.mobileRecommended, child: navigation),
              ),
            )
          : navigation,
      iconTheme: compact
          ? IconThemeData(color: foregroundColor ?? Theme.of(context).colorScheme.onSurface, size: IconSizes.navigation)
          : null,
      centerTitle: compact ? false : null,
      titleSpacing: compact ? (navigation == null ? Spacing.md : 0) : null,
      title: title,
      actions: actions,
      actionsPadding: compact ? const EdgeInsets.only(right: Spacing.md) : null,
    );
  }
}
