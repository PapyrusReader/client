import 'package:flutter/material.dart';
import 'package:papyrus/themes/app_motion.dart';

/// Lets collection pages open the app shell's full-screen drawer.
/// A standalone page can still fall back to its own scaffold.
class AppDrawerScope extends InheritedWidget {
  const AppDrawerScope({super.key, required this.scaffold, required super.child});

  final ScaffoldState scaffold;

  static ScaffoldState? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppDrawerScope>()?.scaffold;

  @override
  bool updateShouldNotify(AppDrawerScope oldWidget) => scaffold != oldWidget.scaffold;
}

/// Opens the same drawer without a sliding transition on e-ink displays.
void openAppDrawer(BuildContext context, ScaffoldState? scaffold) {
  scaffold = AppDrawerScope.maybeOf(context) ?? scaffold;

  if (scaffold == null) {
    return;
  }

  if (!AppMotion.disabled(context)) {
    scaffold.openDrawer();
    return;
  }

  final drawer = scaffold.widget.drawer;

  if (drawer == null) {
    return;
  }

  showDialog<void>(
    context: context,
    useSafeArea: false,
    animationStyle: AnimationStyle.noAnimation,
    builder: (_) => Align(alignment: AlignmentDirectional.centerStart, child: drawer),
  );
}
