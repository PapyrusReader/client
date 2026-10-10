import 'package:papyrus/widgets/shared/app_bottom_sheet.dart';
import 'package:papyrus/widgets/shared/app_drawer.dart';
import 'package:flutter/material.dart';
import 'package:papyrus/data/data_store.dart';
import 'package:papyrus/models/shelf.dart';
import 'package:papyrus/providers/shelves_provider.dart';
import 'package:papyrus/providers/enums/library_view_mode.dart';
import 'package:papyrus/widgets/library/book_grid_layout.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:go_router/go_router.dart';
import 'package:papyrus/widgets/library/library_drawer.dart';
import 'package:papyrus/widgets/library/library_page_header.dart';
import 'package:papyrus/widgets/shared/empty_state.dart';
import 'package:papyrus/widgets/shelves/add_shelf_sheet.dart';
import 'package:papyrus/widgets/shelves/shelf_card.dart';
import 'package:papyrus/widgets/shelves/shelves_filter_chips.dart';
import 'package:provider/provider.dart';
import 'package:papyrus/themes/app_motion.dart';
import 'package:papyrus/widgets/shared/app_progress_indicator.dart';

/// Shelves page for managing book collections.
///
/// Features responsive layouts for mobile and desktop.
/// Allows users to view, create, edit, and delete shelves,
/// as well as manage books within shelves.
class ShelvesPage extends StatefulWidget {
  const ShelvesPage({super.key});

  @override
  State<ShelvesPage> createState() => _ShelvesPageState();
}

class _ShelvesPageState extends State<ShelvesPage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final TextEditingController _searchController = TextEditingController();
  late ShelvesProvider _provider;

  @override
  void initState() {
    super.initState();
    _provider = ShelvesProvider();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Connect to DataStore for persistent storage
    final dataStore = context.read<DataStore>();
    _provider.attach(dataStore);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _provider.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _provider,
      child: Consumer<ShelvesProvider>(
        builder: (context, provider, _) {
          final screenWidth = MediaQuery.of(context).size.width;
          final isDesktop = screenWidth >= Breakpoints.desktopSmall;

          if (provider.isLoading) {
            return _buildLoadingState(context);
          }

          if (isDesktop) {
            return _buildDesktopLayout(context, provider);
          }

          return _buildMobileLayout(context, provider);
        },
      ),
    );
  }

  Widget _buildLoadingState(BuildContext context) {
    return const Scaffold(body: Center(child: AppCircularProgressIndicator()));
  }

  Widget _buildMobileLayout(BuildContext context, ShelvesProvider provider) {
    final shelves = provider.shelves;

    return Scaffold(
      key: _scaffoldKey,
      drawerEnableOpenDragGesture: !AppMotion.disabled(context),
      drawer: AppDrawerScope.maybeOf(context) == null ? const LibraryDrawer(currentPath: '/library/shelves') : null,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.only(
                top: Spacing.md,
                left: libraryPageHorizontalPadding(context),
                right: libraryPageHorizontalPadding(context),
              ),
              child: LibraryMobileToolbar(
                onMenuPressed: () => openAppDrawer(context, _scaffoldKey.currentState),
                searchBuilder: (leading) => _buildSearchField(provider, leading: leading),
              ),
            ),
            const SizedBox(height: Spacing.sm),
            const ShelvesFilterChips(),
            Expanded(child: _buildShelfResults(context, provider, shelves)),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddShelfSheet(context),
        tooltip: 'Add shelf',
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildDesktopLayout(BuildContext context, ShelvesProvider provider) {
    final shelves = provider.shelves;

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: EdgeInsets.only(
                top: Spacing.lg,
                left: libraryPageHorizontalPadding(context),
                right: libraryPageHorizontalPadding(context),
              ),
              child: LibraryToolbar(
                search: _buildSearchField(provider),
                actions: [LibraryAddButton(label: 'Add shelf', onPressed: () => _showAddShelfSheet(context))],
              ),
            ),
            const SizedBox(height: Spacing.sm),
            const ShelvesFilterChips(horizontalPadding: Spacing.lg),
            Expanded(child: _buildShelfResults(context, provider, shelves)),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchField(ShelvesProvider provider, {Widget? leading}) {
    return TextField(
      controller: _searchController,
      decoration: InputDecoration(
        hintText: 'Search shelves...',
        prefixIcon: leading ?? const Icon(Icons.search),
        suffixIcon: provider.searchQuery.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear),
                tooltip: 'Clear shelf search',
                onPressed: () {
                  _searchController.clear();
                  provider.clearSearch();
                },
              )
            : null,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(vertical: Spacing.sm),
        isDense: true,
      ),
      onChanged: provider.setSearchQuery,
    );
  }

  Widget _buildShelfResults(BuildContext context, ShelvesProvider provider, List<Shelf> shelves) {
    if (!provider.hasAnyShelves) {
      return _buildEmptyState(context);
    }

    if (shelves.isEmpty) {
      return _buildNoResultsState(context);
    }

    if (provider.viewMode == LibraryViewMode.list) {
      return _buildShelfList(context, shelves);
    }

    return _buildShelfGrid(context, shelves, provider.gridItemWidth);
  }

  Widget _buildShelfGrid(BuildContext context, List<Shelf> shelves, double itemWidth) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontalPadding = libraryPageHorizontalPadding(context);
        final layout = bookGridLayout(constraints.maxWidth - horizontalPadding * 2, itemWidth: itemWidth);
        final textTheme = Theme.of(context).textTheme;
        final scaler = MediaQuery.textScalerOf(context);
        double lineHeight(TextStyle? style) => scaler.scale(style?.fontSize ?? 14) * (style?.height ?? 1);
        final metadataHeight = lineHeight(textTheme.titleSmall) + lineHeight(textTheme.bodySmall) + Spacing.sm * 2 + 2;

        return GridView.builder(
          padding: EdgeInsets.fromLTRB(horizontalPadding, Spacing.sm, horizontalPadding, Spacing.md),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: layout.crossAxisCount,
            mainAxisSpacing: layout.spacing,
            crossAxisSpacing: layout.spacing,
            mainAxisExtent: layout.itemWidth * 1.5 + metadataHeight,
          ),
          itemCount: shelves.length,
          itemBuilder: (context, index) {
            final shelf = shelves[index];

            return ShelfCard(
              shelf: shelf,
              onTap: () => _showShelfDetail(context, shelf),
              onMoreTap: () => _showShelfOptions(context, shelf),
              onLongPress: () => _showShelfOptions(context, shelf),
            );
          },
        );
      },
    );
  }

  Widget _buildShelfList(BuildContext context, List<Shelf> shelves) {
    return ListView.builder(
      padding: EdgeInsets.symmetric(horizontal: libraryPageHorizontalPadding(context)),
      itemCount: shelves.length,
      itemBuilder: (context, index) {
        final shelf = shelves[index];

        return ShelfCard(
          shelf: shelf,
          isListItem: true,
          onTap: () => _showShelfDetail(context, shelf),
          onMoreTap: () => _showShelfOptions(context, shelf),
          onLongPress: () => _showShelfOptions(context, shelf),
        );
      },
    );
  }

  Widget _buildNoResultsState(BuildContext context) {
    return const EmptyState(
      icon: Icons.search_off,
      title: 'No shelves found',
      subtitle: 'Try changing your search or filters',
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return EmptyState(
      icon: Icons.shelves,
      title: 'No shelves yet',
      subtitle: 'Create shelves to organize your books into collections',
      action: EmptyStateAction(onPressed: () => _showAddShelfSheet(context), icon: Icons.add, label: 'Create shelf'),
    );
  }

  void _showAddShelfSheet(BuildContext context) {
    final repository = context.read<DataStore>().libraryRepository?.shelves;

    AddShelfSheet.show(
      context,
      onSave: (name, description, colorHex, icon) async {
        await _provider.createShelf(
          name: name,
          description: description,
          colorHex: colorHex,
          icon: icon,
          repository: repository,
        );
      },
    );
  }

  void _showEditShelfSheet(BuildContext context, Shelf shelf) {
    final repository = context.read<DataStore>().libraryRepository?.shelves;

    AddShelfSheet.show(
      context,
      shelf: shelf,
      onSave: (name, description, colorHex, icon) async {
        await _provider.updateShelf(
          previous: shelf,
          repository: repository,
          shelfId: shelf.id,
          name: name,
          description: description,
          clearDescription: description == null,
          colorHex: colorHex,
          icon: icon,
        );
      },
    );
  }

  void _showShelfDetail(BuildContext context, Shelf shelf) {
    context.go('/library/shelves/${shelf.id}');
  }

  void _showShelfOptions(BuildContext context, Shelf shelf) {
    final colorScheme = Theme.of(context).colorScheme;

    showModalBottomSheet(
      sheetAnimationStyle: AppMotion.animationStyle(context),
      context: context,
      useRootNavigator: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => AppBottomSheet(
        header: Text(
          shelf.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        body: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Options
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit shelf'),
              onTap: () {
                Navigator.of(context).pop();
                _showEditShelfSheet(context, shelf);
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outlined, color: colorScheme.error),
              title: Text('Delete shelf', style: TextStyle(color: colorScheme.error)),
              onTap: () {
                Navigator.of(context).pop();
                _confirmDeleteShelf(context, shelf);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteShelf(BuildContext context, Shelf shelf) {
    final repository = context.read<DataStore>().libraryRepository?.shelves;
    final colorScheme = Theme.of(context).colorScheme;

    showDialog(
      animationStyle: AppMotion.animationStyle(context),
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete shelf'),
        content: Text('Delete "${shelf.name}"? Books will not be deleted.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              try {
                await _provider.deleteShelf(shelf.id, repository: repository);

                if (context.mounted) {
                  Navigator.of(context).pop();
                }
              } catch (_) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    snackBarAnimationStyle: AppMotion.animationStyle(context),
                    const SnackBar(content: Text('Could not delete shelf. Please try again.')),
                  );
                }
              }
            },
            style: FilledButton.styleFrom(backgroundColor: colorScheme.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
