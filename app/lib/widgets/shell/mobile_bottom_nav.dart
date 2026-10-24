import 'package:flutter/material.dart';
import 'package:papyrus/themes/app_motion.dart';
import 'package:papyrus/utils/navigation_utils.dart';
import 'package:papyrus/widgets/shell/adaptive_app_shell.dart';

/// Mobile bottom navigation bar with Material 3 styling.
class MobileBottomNav extends StatelessWidget {
  final List<AppShellNavItem> items;
  final String currentPath;
  final void Function(String path) onNavigate;

  const MobileBottomNav({super.key, required this.items, required this.currentPath, required this.onNavigate});

  @override
  Widget build(BuildContext context) {
    // Only show main nav items (no children in bottom nav)
    final mainItems = items.where((item) => !isChildPath(item.path)).toList();
    final currentIndex = _getCurrentIndex(mainItems);

    void navigate(int index) {
      final item = mainItems[index];
      onNavigate(item.path == '/library' ? '/library/books' : item.path);
    }

    // Material's NavigationBar caps label scaling. Keep enlarged labels fully
    // readable and keyboard reachable in a horizontally scrollable alternative.
    if (MediaQuery.textScalerOf(context).scale(14) > 14 * 1.3) {
      final colors = Theme.of(context).colorScheme;

      return Material(
        color: colors.surface,
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: List.generate(mainItems.length, (index) {
                final item = mainItems[index];
                final selected = currentIndex == index;

                return Semantics(
                  selected: selected,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: TextButton.icon(
                      style: TextButton.styleFrom(
                        minimumSize: const Size(48, 48),
                        backgroundColor: selected ? colors.primaryContainer : null,
                        foregroundColor: selected ? colors.onPrimaryContainer : colors.onSurface,
                      ),
                      onPressed: () => navigate(index),
                      icon: Icon(selected ? item.selectedIcon ?? item.icon : item.icon),
                      label: Text(item.label),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      );
    }

    return NavigationBar(
      animationDuration: AppMotion.duration(context, const Duration(milliseconds: 500)),
      selectedIndex: currentIndex,
      onDestinationSelected: navigate,
      destinations: mainItems.map((item) {
        return NavigationDestination(
          icon: Icon(item.icon),
          selectedIcon: Icon(item.selectedIcon ?? item.icon),
          label: item.label,
        );
      }).toList(),
    );
  }

  int _getCurrentIndex(List<AppShellNavItem> mainItems) {
    for (var i = 0; i < mainItems.length; i++) {
      if (isNavItemSelected(currentPath, mainItems[i])) {
        return i;
      }
    }

    return 0;
  }
}
