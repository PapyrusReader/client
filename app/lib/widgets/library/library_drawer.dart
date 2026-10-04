import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:papyrus/data/data_store.dart';
import 'package:papyrus/opds/opds_catalogs.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/widgets/shell/nav_item_count.dart';
import 'package:provider/provider.dart';

/// Navigation drawer for the library section on mobile.
///
/// Provides navigation to the different library sub-sections:
/// Books, Shelves, Catalogs, Bookmarks, Annotations, and Notes.
class LibraryDrawer extends StatelessWidget {
  /// The current route path, used to determine which item is selected.
  final String currentPath;

  const LibraryDrawer({super.key, this.currentPath = '/library'});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final dataStore = context.watch<DataStore?>();
    final catalogs = context.watch<OpdsCatalogs?>();

    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drawer header
            Padding(
              padding: const EdgeInsets.all(Spacing.lg),
              child: Text('Library', style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
            ),
            Divider(height: 1, color: colorScheme.outlineVariant),
            const SizedBox(height: Spacing.sm),
            // Navigation items with horizontal padding for rounded corners
            Expanded(
              child: ListView(
                primary: false,
                padding: const EdgeInsets.symmetric(horizontal: Spacing.sm),
                children: [
                  _DrawerNavItem(
                    icon: Icons.book,
                    label: 'Books',
                    count: dataStore?.books.length ?? 0,
                    isSelected: currentPath == '/library' || currentPath == '/library/books',
                    onTap: () {
                      Navigator.of(context).pop();
                      context.go('/library');
                    },
                  ),
                  _DrawerNavItem(
                    icon: Icons.shelves,
                    label: 'Shelves',
                    count: dataStore?.shelves.length ?? 0,
                    isSelected: currentPath.startsWith('/library/shelves'),
                    onTap: () {
                      Navigator.of(context).pop();
                      context.go('/library/shelves');
                    },
                  ),
                  _DrawerNavItem(
                    icon: Icons.public,
                    label: 'Catalogs',
                    count: catalogs?.catalogs.length ?? 0,
                    isSelected: currentPath.startsWith('/library/catalogs'),
                    onTap: () {
                      Navigator.of(context).pop();
                      context.go('/library/catalogs');
                    },
                  ),
                  _DrawerNavItem(
                    icon: Icons.bookmark,
                    label: 'Bookmarks',
                    count: dataStore?.bookmarks.length ?? 0,
                    isSelected: currentPath == '/library/bookmarks',
                    onTap: () {
                      Navigator.of(context).pop();
                      context.go('/library/bookmarks');
                    },
                  ),
                  _DrawerNavItem(
                    icon: Icons.format_quote,
                    label: 'Annotations',
                    count: dataStore?.annotations.length ?? 0,
                    isSelected: currentPath == '/library/annotations',
                    onTap: () {
                      Navigator.of(context).pop();
                      context.go('/library/annotations');
                    },
                  ),
                  _DrawerNavItem(
                    icon: Icons.note,
                    label: 'Notes',
                    count: dataStore?.notes.length ?? 0,
                    isSelected: currentPath == '/library/notes',
                    onTap: () {
                      Navigator.of(context).pop();
                      context.go('/library/notes');
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Navigation item for the library drawer.
class _DrawerNavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final int count;
  final VoidCallback onTap;

  const _DrawerNavItem({
    required this.icon,
    required this.label,
    this.isSelected = false,
    this.count = 0,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return ListTile(
      leading: Icon(icon, color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant),
      title: Text(
        label,
        style: textTheme.bodyLarge?.copyWith(
          color: isSelected ? colorScheme.primary : colorScheme.onSurface,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      selected: isSelected,
      trailing: count > 0 ? NavItemCount(count: count, selected: isSelected) : null,
      selectedTileColor: colorScheme.primaryContainer.withValues(alpha: 0.3),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.full)),
      contentPadding: const EdgeInsets.symmetric(horizontal: Spacing.md),
      visualDensity: VisualDensity.compact,
      onTap: onTap,
    );
  }
}
