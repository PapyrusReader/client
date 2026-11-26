import 'package:papyrus/config/page_history.dart';
import 'package:papyrus/themes/app_motion.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:papyrus/admin/admin_navigation.dart';
import 'package:papyrus/data/data_store.dart';
import 'package:papyrus/opds/opds_catalogs.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/utils/navigation_utils.dart';
import 'package:papyrus/widgets/library/library_drawer.dart';
import 'package:papyrus/widgets/shared/app_drawer.dart';
import 'package:papyrus/widgets/shell/desktop_sidebar.dart';
import 'package:papyrus/widgets/shell/mobile_bottom_nav.dart';
import 'package:provider/provider.dart';

/// Main app shell that adapts to available screen width.
/// - Desktop: Permanent collapsible sidebar
/// - Mobile: Bottom navigation bar
class AdaptiveAppShell extends StatelessWidget {
  final Widget child;

  const AdaptiveAppShell({super.key, required this.child});

  static List<AppShellNavItem> buildNavItems(
    DataStore dataStore, {
    required int catalogCount,
    required bool includeAdministration,
  }) {
    return [
      const AppShellNavItem(
        path: '/dashboard',
        label: 'Dashboard',
        icon: Icons.dashboard_outlined,
        selectedIcon: Icons.dashboard,
      ),
      AppShellNavItem(
        path: '/library',
        label: 'Library',
        icon: Icons.library_books_outlined,
        selectedIcon: Icons.library_books,
        children: [
          AppShellNavItem(
            path: '/library/books',
            label: 'Books',
            icon: Icons.menu_book_outlined,
            count: dataStore.books.length,
            selectedIcon: Icons.menu_book,
          ),
          AppShellNavItem(
            path: '/library/shelves',
            label: 'Shelves',
            icon: Icons.shelves,
            count: dataStore.shelves.length,
            selectedIcon: Icons.shelves,
          ),
          const AppShellNavItem(
            path: '/library/folders',
            label: 'Folders',
            icon: Icons.folder_outlined,
            selectedIcon: Icons.folder,
          ),
          AppShellNavItem(
            path: '/library/catalogs',
            label: 'Catalogs',
            icon: Icons.public_outlined,
            selectedIcon: Icons.public,
            count: catalogCount,
          ),
          AppShellNavItem(
            path: '/library/bookmarks',
            label: 'Bookmarks',
            icon: Icons.bookmark_outline,
            count: dataStore.bookmarks.length,
            selectedIcon: Icons.bookmark,
          ),
          AppShellNavItem(
            path: '/library/annotations',
            label: 'Annotations',
            icon: Icons.border_color_outlined,
            count: dataStore.annotations.length,
            selectedIcon: Icons.border_color,
          ),
          AppShellNavItem(
            path: '/library/notes',
            label: 'Notes',
            icon: Icons.notes_outlined,
            count: dataStore.notes.length,
            selectedIcon: Icons.notes,
          ),
          const AppShellNavItem(
            path: '/library/timer',
            label: 'Timer',
            icon: Icons.timer_outlined,
            selectedIcon: Icons.timer,
          ),
        ],
      ),
      const AppShellNavItem(
        path: '/goals',
        label: 'Goals',
        icon: Icons.emoji_events_outlined,
        selectedIcon: Icons.emoji_events,
      ),
      const AppShellNavItem(
        path: '/statistics',
        label: 'Statistics',
        icon: Icons.bar_chart_outlined,
        selectedIcon: Icons.bar_chart,
      ),
      if (includeAdministration) administrationNavItem,
      const AppShellNavItem(
        path: '/profile',
        label: 'Settings',
        icon: Icons.settings_outlined,
        selectedIcon: Icons.settings,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final dataStore = context.watch<DataStore>();
    final catalogCount = context.select<OpdsCatalogs, int>((catalogs) => catalogs.catalogs.length);
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= Breakpoints.desktopSmall;

    final navItems = buildNavItems(
      dataStore,
      catalogCount: catalogCount,
      includeAdministration: isDesktop && canShowAdministration(context),
    );

    if (isDesktop) {
      return _buildDesktopShell(context, navItems);
    } else {
      return _buildMobileShell(context, navItems);
    }
  }

  Widget _buildDesktopShell(BuildContext context, List<AppShellNavItem> navItems) {
    return Scaffold(
      body: Row(
        children: [
          DesktopSidebar(
            items: navItems,
            currentPath: GoRouterState.of(context).uri.toString(),
            onNavigate: (path) => context.go(path),
          ),
          Expanded(child: Semantics(container: true, child: child)),
        ],
      ),
    );
  }

  Widget _buildMobileShell(BuildContext context, List<AppShellNavItem> navItems) {
    final currentPath = GoRouterState.of(context).uri.path;
    final isInLibrary = currentPath.startsWith('/library');

    final bookBackGesture =
        usesBookBackGesture(context) &&
        (currentPath.startsWith('/library/details/') || currentPath.startsWith('/library/edit/'));

    return Scaffold(
      body: Semantics(
        container: true,
        child: isInLibrary
            ? Builder(
                builder: (context) => AppDrawerScope(scaffold: Scaffold.of(context), child: child),
              )
            : child,
      ),
      bottomNavigationBar: currentPath == adminUsersPath
          ? null
          : MobileBottomNav(
              items: navItems,
              currentPath: currentPath,
              onNavigate: (path) => context.go(path),
            ),
      drawerEnableOpenDragGesture: !AppMotion.disabled(context) && !bookBackGesture,
      drawer: isInLibrary ? LibraryDrawer(currentPath: currentPath) : null,
    );
  }
}
