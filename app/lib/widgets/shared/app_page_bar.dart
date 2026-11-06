import 'package:flutter/material.dart';
import 'package:papyrus/themes/app_motion.dart';
import 'package:papyrus/themes/design_tokens.dart';

/// Mobile toolbar geometry shared by scaffold app bars and inline page headers.
/// The containing page or scaffold owns the system safe-area inset.
class AppPageToolbar extends StatelessWidget {
  const AppPageToolbar({super.key, this.leading, this.content, this.actions = const [], this.scrollAware = true});

  final Widget? leading;
  final Widget? content;
  final List<Widget> actions;
  final bool scrollAware;

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
  Widget build(BuildContext context) {
    final toolbar = Padding(
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

    return scrollAware ? _ScrolledHeader(child: toolbar) : toolbar;
  }
}

/// Inline headers share the Scaffold's scroll observer with native app bars.
class _ScrolledHeader extends StatefulWidget {
  const _ScrolledHeader({required this.child});

  final Widget child;

  @override
  State<_ScrolledHeader> createState() => _ScrolledHeaderState();
}

class _ScrolledHeaderState extends State<_ScrolledHeader> {
  ScrollNotificationObserverState? _observer;
  bool _scrolledUnder = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _observer?.removeListener(_onScroll);
    _observer = ScrollNotificationObserver.maybeOf(context);
    _observer?.addListener(_onScroll);
  }

  @override
  void dispose() {
    _observer?.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll(ScrollNotification notification) {
    if (notification is! ScrollUpdateNotification || !defaultScrollNotificationPredicate(notification)) {
      return;
    }

    final metrics = notification.metrics;
    final scrolledUnder = switch (metrics.axisDirection) {
      AxisDirection.down => metrics.extentBefore > 0,
      AxisDirection.up => metrics.extentAfter > 0,
      AxisDirection.left || AxisDirection.right => _scrolledUnder,
    };

    if (scrolledUnder != _scrolledUnder) {
      setState(() => _scrolledUnder = scrolledUnder);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bar = theme.appBarTheme;
    final states = {if (_scrolledUnder) WidgetState.scrolledUnder};
    final background =
        bar.backgroundColor ??
        (_scrolledUnder && theme.useMaterial3 ? theme.colorScheme.surfaceContainer : theme.colorScheme.surface);
    final elevation = bar.elevation ?? (theme.useMaterial3 ? 0 : 4);

    return Material(
      color: WidgetStateProperty.resolveAs(background, states),
      elevation: _scrolledUnder ? bar.scrolledUnderElevation ?? (theme.useMaterial3 ? 3 : elevation) : elevation,
      shadowColor: bar.shadowColor ?? (theme.useMaterial3 ? Colors.transparent : theme.shadowColor),
      surfaceTintColor: bar.surfaceTintColor ?? (theme.useMaterial3 ? theme.colorScheme.surfaceTint : null),
      shape: bar.shape,
      animationDuration: AppMotion.duration(context, kThemeChangeDuration),
      textStyle: DefaultTextStyle.of(context).style,
      child: widget.child,
    );
  }
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
      title: compact
          ? AppPageToolbar(leading: navigation, content: title, actions: actions, scrollAware: false)
          : title,
      actions: compact ? null : actions,
    );
  }
}
