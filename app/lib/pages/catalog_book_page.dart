import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:papyrus/opds/opds_browser.dart';
import 'package:papyrus/opds/opds_catalogs.dart';
import 'package:papyrus/opds/opds_downloads.dart';
import 'package:papyrus/opds/opds_http_client.dart';
import 'package:papyrus/opds/opds_models.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/widgets/opds/opds_download_panel.dart';
import 'package:papyrus/widgets/opds/opds_download_actions.dart';
import 'package:papyrus/widgets/opds/opds_publication_details.dart';
import 'package:papyrus/widgets/shared/app_progress_indicator.dart';
import 'package:provider/provider.dart';

/// An optional in-memory preview, never a substitute for a reloadable URL.
class CatalogBookSelection {
  const CatalogBookSelection({required this.catalog, required this.publication, required this.scope});
  final OpdsCatalog catalog;
  final OpdsPublication publication;
  final String? scope;
}

GoRoute catalogBookRoute() => GoRoute(
  path: 'book',
  name: 'CATALOG_BOOK',
  pageBuilder: (_, state) => NoTransitionPage(
    key: state.pageKey,
    child: CatalogBookPage(
      catalogId: state.pathParameters['catalogId']!,
      source: Uri.tryParse(state.uri.queryParameters['feed'] ?? ''),
      publicationId: state.uri.queryParameters['publication'] ?? '',
      query: state.uri.queryParameters['q'] ?? '',
      initial: state.extra is CatalogBookSelection ? state.extra as CatalogBookSelection : null,
    ),
  ),
);

class CatalogBookPage extends StatefulWidget {
  const CatalogBookPage({
    super.key,
    required this.catalogId,
    required this.source,
    required this.publicationId,
    this.query = '',
    this.initial,
  });
  final String catalogId;
  final Uri? source;
  final String publicationId;
  final String query;
  final CatalogBookSelection? initial;

  @override
  State<CatalogBookPage> createState() => _CatalogBookPageState();
}

class _CatalogBookPageState extends State<CatalogBookPage> {
  late final _browser = OpdsBrowser(httpClient: context.read<OpdsHttpClient>());
  String? _loadKey;
  OpdsPublication? _publication;
  OpdsCredentials? _credentials;
  String? _error;
  bool _loading = true;

  void _scheduleLoad(OpdsCatalogs catalogs, OpdsCatalog? catalog) {
    final key = '${catalogs.scope}/${catalogs.revision}/${widget.catalogId}/${widget.source}/${widget.publicationId}';
    if (key == _loadKey) return;
    _loadKey = key;
    _browser.clear();
    _credentials = null;
    _publication = null;
    _error = null;
    _loading = catalog != null;
    if (catalog == null) return;
    final initial = widget.initial;
    if (initial != null &&
        initial.scope == catalogs.scope &&
        identical(initial.catalog, catalog) &&
        initial.publication.id == widget.publicationId) {
      _publication = initial.publication;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || key != _loadKey) return;
      try {
        final credentials = await catalogs.credentials(catalog.id);
        if (!mounted || key != _loadKey) return;
        _credentials = credentials;
        if (_publication == null) {
          final source = widget.source;
          if (source == null || !source.hasScheme || widget.publicationId.isEmpty) {
            throw const OpdsException('This book link is incomplete. Return to the catalog and select the book again.');
          }
          await _browser.load(catalog, source, credentials: credentials);
          if (!mounted || key != _loadKey) return;
          if (_browser.error != null) throw OpdsException(_browser.error!);
          final feed = _browser.feed!;
          _publication = [
            ...feed.publications,
            for (final group in feed.groups) ...group.publications,
          ].where((book) => book.id == widget.publicationId).firstOrNull;
          if (_publication == null) throw const OpdsException('This book is no longer available in this catalog feed.');
        }
        // Resolve standalone publication metadata using the existing OPDS parser
        // and detail-link classification. Multi-edition feeds remain distinct.
        final detail = _publication!.detailLink;
        if (detail != null && detail.uri != widget.source) {
          await _browser.load(catalog, detail.uri, credentials: credentials);
          if (!mounted || key != _loadKey) return;
          final books = _browser.feed?.publications ?? <OpdsPublication>[];
          final type = detail.type?.toLowerCase() ?? '';
          final standalone =
              type.startsWith('application/opds-publication+json') || RegExp(r'type\s*=\s*"?entry').hasMatch(type);
          final matching = books.where((book) => book.id == _publication!.id).firstOrNull;
          if (matching != null || (standalone && books.length == 1)) {
            _publication = matching ?? books.single;
          } else if (_browser.error != null) {
            _error = _browser.error;
          }
        }
      } catch (error) {
        if (!mounted || key != _loadKey) return;
        _error = opdsErrorMessage(error);
      } finally {
        if (mounted && key == _loadKey) setState(() => _loading = false);
      }
    });
  }

  void _back() {
    if (context.canPop()) {
      context.pop();
    } else {
      _navigate(widget.source);
    }
  }

  void _navigate(Uri? uri) => context.go(
    Uri(
      path: '/library/catalogs/${Uri.encodeComponent(widget.catalogId)}',
      queryParameters: {if (uri != null) 'feed': uri.toString(), if (widget.query.isNotEmpty) 'q': widget.query},
    ).toString(),
  );

  Future<void> _download(OpdsCatalog catalog, OpdsPublication publication, OpdsLink link) async {
    if (!mounted) return;
    final catalogs = context.read<OpdsCatalogs>();
    final downloads = context.read<OpdsDownloads>();
    final scope = catalogs.scope;
    final revision = catalogs.revision;
    if (!identical(catalogs.find(catalog.id), catalog)) {
      _message('The catalog or account changed. Close these details and reopen the book.');
      return;
    }
    try {
      final credentials = await catalogs.credentials(catalog.id);
      if (!mounted || scope != catalogs.scope || revision != catalogs.revision) return;
      await downloads.start(catalog, publication, link, credentials: credentials);
    } catch (error) {
      if (mounted) _message(opdsErrorMessage(error));
    }
  }

  void _message(String message) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  void _retry() {
    final catalogs = context.read<OpdsCatalogs>();
    if (catalogs.error != null) catalogs.reload();
    setState(() => _loadKey = null);
  }

  @override
  void dispose() {
    _browser.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final catalogs = context.watch<OpdsCatalogs>();
    final catalog = catalogs.find(widget.catalogId);
    final downloads = context.watch<OpdsDownloads>();
    _scheduleLoad(catalogs, catalog);
    final publication = _publication;
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: ComponentSizes.appBarHeight),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: Spacing.sm),
                child: Row(
                  children: [
                    IconButton(tooltip: 'Back to catalog', onPressed: _back, icon: const Icon(Icons.arrow_back)),
                    const SizedBox(width: Spacing.sm),
                    Expanded(
                      child: Text(
                        catalog?.name ?? 'Book details',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                    OpdsDownloadsButton(
                      compact: MediaQuery.sizeOf(context).width < Breakpoints.desktopSmall,
                      downloads: downloads,
                      onRetry: (job) => unawaited(retryOpdsDownload(context, job)),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(key: Key('catalog-book-header-divider'), height: 1),
            Expanded(
              child: Padding(
                padding: EdgeInsets.all(constraints.maxWidth < Breakpoints.tablet ? Spacing.md : Spacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_error != null && _publication != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: Spacing.md),
                        child: Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: Spacing.sm,
                          children: [
                            Text(_error!),
                            TextButton(onPressed: _retry, child: const Text('Retry')),
                          ],
                        ),
                      ),
                    Expanded(
                      child: catalog == null
                          ? _unavailable(catalogs.error ?? 'This catalog is not saved for the active account.')
                          : _loading && _publication == null
                          ? const Center(child: AppCircularProgressIndicator())
                          : _publication == null
                          ? _unavailable(_error ?? 'This book is unavailable.')
                          : OpdsPublicationDetails(
                              key: ValueKey('${catalogs.scope}/${catalogs.revision}/${_publication!.id}'),
                              catalog: catalog,
                              publication: _publication!,
                              httpClient: _browser.httpClient,
                              credentials: _credentials,
                              downloads: downloads,
                              onNavigate: _navigate,
                              resolving: _loading,
                              onDownload: (link) => unawaited(_download(catalog, publication!, link)),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _unavailable(String message) => Center(
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.menu_book_outlined, size: 48),
          const SizedBox(height: Spacing.md),
          Text('Book unavailable', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: Spacing.sm),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: Spacing.md),
          Wrap(
            spacing: Spacing.sm,
            children: [
              TextButton(onPressed: _retry, child: const Text('Retry')),
              FilledButton(onPressed: _back, child: const Text('Back to catalog')),
            ],
          ),
        ],
      ),
    ),
  );
}
