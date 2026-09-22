import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:papyrus/opds/opds_browser.dart';
import 'package:papyrus/opds/opds_catalogs.dart';
import 'package:papyrus/opds/opds_downloads.dart';
import 'package:papyrus/opds/opds_http_client.dart';
import 'package:papyrus/opds/opds_models.dart';
import 'package:papyrus/themes/app_motion.dart';
import 'package:papyrus/pages/catalog_book_page.dart';
import 'package:papyrus/widgets/input/search_field.dart';
import 'package:papyrus/widgets/opds/opds_sheet.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/widgets/opds/catalog_editor.dart';
import 'package:papyrus/widgets/opds/catalog_source_tile.dart';
import 'package:papyrus/widgets/opds/opds_feed_view.dart';
import 'package:papyrus/widgets/opds/opds_download_panel.dart';
import 'package:papyrus/widgets/opds/opds_download_actions.dart';
import 'package:papyrus/widgets/opds/opds_mobile_header.dart';
import 'package:papyrus/widgets/shared/app_progress_indicator.dart';
import 'package:provider/provider.dart';

class CatalogsPage extends StatefulWidget {
  const CatalogsPage({super.key, this.catalogId, this.feedUri, this.query = '', this.httpClient});
  final String? catalogId;
  final Uri? feedUri;
  final String query;
  final OpdsHttpClient? httpClient;
  @override
  State<CatalogsPage> createState() => _CatalogsPageState();
}

class _CatalogsPageState extends State<CatalogsPage> {
  late final _browser = OpdsBrowser(httpClient: widget.httpClient ?? context.read<OpdsHttpClient>());
  late final _search = TextEditingController(text: widget.query);
  OpdsCredentials? _credentials;
  String? _loadKey;
  bool _reloadRequested = false;
  OpdsFeed? _feedForHeader;
  bool _searching = false;
  bool _isGridView = true;
  final _feedScroll = ScrollController();

  @override
  void didUpdateWidget(covariant CatalogsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.query != widget.query) _search.text = widget.query;
  }

  void _scheduleLoad(OpdsCatalogs catalogs) {
    final catalog = widget.catalogId == null ? null : catalogs.find(widget.catalogId!);
    final key = '${catalogs.scope}/${catalogs.revision}/${widget.catalogId}/${widget.feedUri ?? catalog?.uri}';
    if (_loadKey == key && !_reloadRequested) return;
    final sameFeed = _loadKey == key;
    _feedForHeader = sameFeed ? (_browser.feed ?? _feedForHeader) : null;
    _reloadRequested = false;
    _loadKey = key;
    _credentials = null;
    if (!sameFeed) _browser.clear();
    if (catalog == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || _loadKey != key) return;
      if (_feedScroll.hasClients) _feedScroll.jumpTo(0);
      try {
        final credentials = await catalogs.credentials(catalog.id);
        if (!mounted || _loadKey != key) return;
        _credentials = credentials;
        await _browser.load(catalog, widget.feedUri ?? catalog.uri, credentials: credentials);
      } catch (error) {
        if (mounted && _loadKey == key) setState(() => _browser.error = opdsErrorMessage(error));
      }
    });
  }

  Future<void> _edit(OpdsCatalogs catalogs, [OpdsCatalog? catalog]) =>
      CatalogEditor.show(context, catalogs: catalogs, catalog: catalog);

  Future<void> _remove(OpdsCatalogs catalogs, OpdsCatalog catalog) async {
    final scope = catalogs.scope;
    ScaffoldMessenger.of(context).clearSnackBars();
    final confirmed = await showOpdsSheet<bool>(
      context,
      title: 'Remove catalog',
      cancelLabel: 'Cancel',
      saveLabel: 'Remove',
      onSave: () => Navigator.of(context, rootNavigator: true).pop(true),
      child: Text(
        'This will remove “${catalog.name}” and its saved credentials. '
        'Downloaded books will remain in your library.',
      ),
    );
    if (confirmed != true || !mounted || catalogs.scope != scope) return;
    try {
      await catalogs.remove(catalog.id);
    } catch (error) {
      if (mounted) _message(opdsErrorMessage(error));
    }
  }

  void _navigate(OpdsCatalog catalog, Uri uri, {String query = ''}) {
    try {
      OpdsHttpClient.validateUri(uri);
      context.push(
        Uri(
          path: '/library/catalogs/${Uri.encodeComponent(catalog.id)}',
          queryParameters: {'feed': uri.toString(), if (query.isNotEmpty) 'q': query},
        ).toString(),
      );
    } catch (error) {
      _message(opdsErrorMessage(error));
    }
  }

  void _back(OpdsCatalog? catalog) {
    final router = GoRouter.of(context);
    if (router.routerDelegate.currentConfiguration.last is ImperativeRouteMatch && router.canPop()) {
      router.pop();
    } else if (catalog != null && widget.feedUri != null && widget.feedUri != catalog.uri) {
      // A refreshed/shared subsection has no earlier visit in its route stack.
      // Return to this catalog's root before leaving the catalog altogether.
      router.go('/library/catalogs/${Uri.encodeComponent(catalog.id)}');
    } else {
      router.go('/library/catalogs');
    }
  }

  Future<void> _submitSearch(OpdsCatalog catalog) async {
    if (_searching || _search.text.trim().isEmpty) return;
    final key = _loadKey;
    final query = _search.text.trim();
    setState(() => _searching = true);
    try {
      final uri = await _browser.search(query);
      if (mounted && key == _loadKey) _navigate(catalog, uri, query: query);
    } catch (error) {
      if (mounted && key == _loadKey) _message(opdsErrorMessage(error));
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _message(String text) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(snackBarAnimationStyle: AppMotion.animationStyle(context), SnackBar(content: Text(text)));

  @override
  void dispose() {
    _browser.dispose();
    _search.dispose();
    _feedScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final catalogs = context.watch<OpdsCatalogs>();
    _scheduleLoad(catalogs);
    final catalog = widget.catalogId == null ? null : catalogs.find(widget.catalogId!);
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < Breakpoints.tablet;
          final mobileHome = widget.catalogId == null && MediaQuery.sizeOf(context).width < Breakpoints.desktopSmall;
          final body = Padding(
            padding: EdgeInsets.fromLTRB(
              compact ? Spacing.md : Spacing.lg,
              compact ? Spacing.md : Spacing.lg,
              compact ? Spacing.md : Spacing.lg,
              0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (catalog != null)
                  SearchField(
                    controller: _search,
                    hintText: 'Search this catalog',
                    height: MediaQuery.textScalerOf(context).scale(16) > 24 ? 56 : 40,
                    onSubmitted: (_) => _submitSearch(catalog),
                    onChanged: (_) => setState(() {}),
                    onClear: () {
                      setState(() {});
                      if (widget.query.isNotEmpty) _navigate(catalog, catalog.uri);
                    },
                    trailing: IconButton(
                      tooltip: 'Search catalog',
                      onPressed: _searching ? null : () => _submitSearch(catalog),
                      icon: _searching
                          ? const SizedBox.square(dimension: 20, child: AppCircularProgressIndicator())
                          : const Icon(Icons.arrow_forward),
                    ),
                  ),
                Expanded(
                  child: catalog == null
                      ? _catalogList(catalogs)
                      : AnimatedBuilder(animation: _browser, builder: (_, _) => _feedView(catalog)),
                ),
              ],
            ),
          );
          final content = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (MediaQuery.sizeOf(context).width < Breakpoints.desktopSmall)
                _header(catalogs, catalog)
              else ...[
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: ComponentSizes.appBarHeight),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: Spacing.sm),
                    child: _header(catalogs, catalog),
                  ),
                ),
                const Divider(key: Key('catalog-header-divider'), height: 1),
              ],
              Expanded(child: body),
            ],
          );
          if (!mobileHome) return content;
          return Stack(
            fit: StackFit.expand,
            children: [
              content,
              Positioned(
                right: Spacing.md,
                bottom: Spacing.md,
                child: FloatingActionButton(
                  tooltip: 'Add catalog',
                  onPressed: catalogs.scope == null ? null : () => _edit(catalogs),
                  child: const Icon(Icons.add),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _header(OpdsCatalogs catalogs, OpdsCatalog? catalog) {
    final theme = Theme.of(context);
    final mobile = MediaQuery.sizeOf(context).width < Breakpoints.desktopSmall;
    final downloads = context.watch<OpdsDownloads>();
    final downloadsButton = OpdsDownloadsButton(
      compact: mobile,
      downloads: downloads,
      onRetry: (job) => unawaited(retryOpdsDownload(context, job)),
    );
    if (mobile) {
      return OpdsMobileHeader(
        key: const Key('catalog-mobile-header'),
        title: catalog?.name ?? 'Catalogs',
        leading: widget.catalogId != null
            ? IconButton(tooltip: 'Back', icon: const BackButtonIcon(), onPressed: () => _back(catalog))
            : IconButton(
                tooltip: 'Library sections',
                icon: const Icon(Icons.menu),
                onPressed: () => Scaffold.maybeOf(context)?.openDrawer(),
              ),
        actions: [
          downloadsButton,
          if (catalog != null)
            IconButton(
              tooltip: 'Edit catalog',
              onPressed: () => _edit(catalogs, catalog),
              icon: const Icon(Icons.settings_outlined),
            ),
        ],
      );
    }
    if (widget.catalogId != null) {
      return Row(
        children: [
          IconButton(tooltip: 'Back', icon: const Icon(Icons.arrow_back), onPressed: () => _back(catalog)),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: Text(
              catalog?.name ?? 'Catalogs',
              style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          downloadsButton,
          if (catalog != null)
            IconButton(
              tooltip: 'Edit catalog',
              onPressed: () => _edit(catalogs, catalog),
              icon: const Icon(Icons.settings_outlined),
            ),
        ],
      );
    }
    final heading = Row(
      children: [
        Expanded(
          child: Text('Catalogs', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600)),
        ),
      ],
    );
    final actions = Wrap(
      spacing: Spacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        downloadsButton,
        FilledButton.icon(
          onPressed: catalogs.scope == null ? null : () => _edit(catalogs),
          icon: const Icon(Icons.add),
          label: const Text('Add catalog'),
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        return constraints.maxWidth < Breakpoints.tablet || MediaQuery.textScalerOf(context).scale(1) > 1.4
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  heading,
                  const SizedBox(height: Spacing.md),
                  Align(alignment: Alignment.centerRight, child: actions),
                ],
              )
            : Row(
                children: [
                  Expanded(child: heading),
                  const SizedBox(width: Spacing.md),
                  actions,
                ],
              );
      },
    );
  }

  Widget _catalogList(OpdsCatalogs catalogs) {
    if (catalogs.error != null) {
      return _empty(
        'Could not load catalogs',
        detail: catalogs.error,
        action: 'Retry',
        onAction: catalogs.reload,
        icon: Icons.cloud_off_outlined,
      );
    }
    if (catalogs.scope == null) return const Center(child: Text('Waiting for your library…'));
    if (widget.catalogId != null) {
      return _empty(
        'Catalog unavailable',
        detail: 'This catalog is not saved for the active account.',
        action: 'All catalogs',
        onAction: () => context.go('/library/catalogs'),
      );
    }
    if (catalogs.catalogs.isEmpty) {
      return _empty(
        'No catalogs yet',
        detail: 'Connect an OPDS catalog to explore its collection and add books to your library.',
        action: 'Add catalog',
        onAction: () => _edit(catalogs),
      );
    }
    return ListView.separated(
      key: ValueKey(catalogs.scope),
      padding: EdgeInsets.only(bottom: MediaQuery.sizeOf(context).width < Breakpoints.desktopSmall ? 96 : Spacing.lg),
      itemCount: catalogs.catalogs.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (_, index) {
        final catalog = catalogs.catalogs[index];
        return CatalogSourceTile(
          key: ValueKey(catalog.id),
          catalog: catalog,
          onOpen: () => context.push('/library/catalogs/${Uri.encodeComponent(catalog.id)}'),
          onEdit: () => _edit(catalogs, catalog),
          onRemove: () => _remove(catalogs, catalog),
        );
      },
    );
  }

  void _reloadFeed() => setState(() => _reloadRequested = true);

  Widget _feedView(OpdsCatalog catalog) {
    Widget? status;
    if (_browser.error != null && _browser.feed == null) {
      status = _empty(
        'Could not open this catalog',
        detail: _browser.error,
        action: 'Retry',
        onAction: _reloadFeed,
        icon: Icons.cloud_off_outlined,
      );
    } else if (_browser.feed == null) {
      status = const Center(child: AppCircularProgressIndicator());
    }
    final feed = _browser.feed ?? _feedForHeader;
    if (feed == null) return status ?? const SizedBox.shrink();
    return OpdsFeedView(
      libraryBookId: (publication) => context.read<OpdsDownloads>().libraryBookId(catalog, publication),
      status: _browser.feed != null && _browser.error != null
          ? Padding(
              padding: const EdgeInsets.only(bottom: Spacing.sm),
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: Spacing.sm,
                children: [
                  const Text('Showing saved content. Could not refresh this catalog.'),
                  TextButton(onPressed: _reloadFeed, child: const Text('Retry')),
                ],
              ),
            )
          : null,
      isRefreshing: _browser.loading && _browser.feed != null,
      contentOverride: status,
      scrollController: _feedScroll,
      catalog: catalog,
      feed: feed,
      credentials: _credentials,
      httpClient: _browser.httpClient,
      query: widget.query,
      isGridView: _isGridView,
      onViewChanged: (value) => setState(() => _isGridView = value),
      onNavigate: (uri) => _navigate(catalog, uri),
      onPage: (uri) => _navigate(catalog, uri, query: widget.query),
      onRefresh: _browser.loading || (_browser.feed == null && _browser.error == null) ? null : _reloadFeed,
      onOpenPublication: (publication) => context.push(
        Uri(
          path: '/library/catalogs/${Uri.encodeComponent(catalog.id)}/book',
          queryParameters: {
            'feed': (widget.feedUri ?? catalog.uri).toString(),
            'publication': publication.id,
            if (widget.query.isNotEmpty) 'q': widget.query,
          },
        ).toString(),
        extra: CatalogBookSelection(
          catalog: catalog,
          publication: publication,
          scope: context.read<OpdsCatalogs>().scope,
          cached: _browser.isCached,
        ),
      ),
    );
  }

  Widget _empty(
    String title, {
    String? detail,
    required String action,
    required VoidCallback onAction,
    IconData icon = Icons.local_library_outlined,
  }) => Center(
    child: SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 56, color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(height: Spacing.lg),
              Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
              if (detail != null)
                Padding(
                  padding: const EdgeInsets.only(top: Spacing.sm),
                  child: Text(
                    detail,
                    textAlign: TextAlign.center,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ),
              const SizedBox(height: Spacing.lg),
              FilledButton(
                onPressed: onAction,
                style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                child: Text(action),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
