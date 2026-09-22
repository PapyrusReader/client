import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:papyrus/opds/opds_downloads.dart';
import 'package:papyrus/opds/opds_http_client.dart';
import 'package:papyrus/opds/opds_models.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/widgets/opds/opds_download_panel.dart';
import 'package:papyrus/widgets/opds/opds_publication_tile.dart';
import 'package:papyrus/widgets/opds/opds_sheet.dart';
import 'package:papyrus/widgets/shared/app_progress_indicator.dart';

/// Read-only catalog metadata; library ownership is established only by import.
class OpdsPublicationDetails extends StatelessWidget {
  const OpdsPublicationDetails({
    super.key,
    required this.catalog,
    required this.publication,
    required this.httpClient,
    required this.downloads,
    required this.onDownload,
    required this.onNavigate,
    this.credentials,
    this.resolving = false,
  });
  final OpdsCatalog catalog;
  final OpdsPublication publication;
  final OpdsHttpClient httpClient;
  final OpdsDownloads downloads;
  final OpdsCredentials? credentials;
  final ValueChanged<OpdsLink> onDownload;
  final ValueChanged<Uri> onNavigate;
  final bool resolving;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final desktop = constraints.maxWidth >= Breakpoints.desktopSmall;
      final theme = Theme.of(context);
      final cover = ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: OpdsCover(
          catalog: catalog,
          uri: publication.images.firstOrNull?.uri,
          httpClient: httpClient,
          credentials: credentials,
          width: desktop ? 240 : 180,
          height: desktop ? 360 : 270,
        ),
      );
      final metadata = Column(
        crossAxisAlignment: desktop ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          Text(
            publication.title,
            textAlign: desktop ? TextAlign.start : TextAlign.center,
            style: (desktop ? theme.textTheme.displaySmall : theme.textTheme.headlineSmall)?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: Spacing.sm),
          Text(
            publication.authors.isEmpty ? 'Unknown author' : publication.authors.join(', '),
            textAlign: desktop ? TextAlign.start : TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: Spacing.md),
          FilledButton.icon(
            onPressed: resolving
                ? null
                : () => showOpdsSheet<void>(
                    context,
                    title: 'Download options',
                    child: _DownloadOptions(
                      catalog: catalog,
                      publication: publication,
                      downloads: downloads,
                      onDownload: onDownload,
                      onNavigate: onNavigate,
                    ),
                  ),
            icon: const Icon(Icons.add),
            label: const Text('Add to library'),
          ),
        ],
      );
      return SingleChildScrollView(
        key: PageStorageKey('publication/${catalog.id}/${publication.id}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (desktop)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  cover,
                  const SizedBox(width: Spacing.xl),
                  Expanded(child: metadata),
                ],
              )
            else ...[
              Center(child: cover),
              const SizedBox(height: Spacing.lg),
              metadata,
            ],
            const SizedBox(height: Spacing.xl),
            const Divider(height: 1),
            const SizedBox(height: Spacing.lg),
            Text('About this book', style: theme.textTheme.titleLarge),
            const SizedBox(height: Spacing.md),
            Text(
              publication.description?.trim().isNotEmpty == true
                  ? publication.description!
                  : 'No description is available for this book.',
              key: const Key('opds-description'),
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
            ),
            if (publication.language != null || publication.publisher != null || publication.isbn != null) ...[
              const SizedBox(height: Spacing.xl),
              Wrap(
                spacing: Spacing.xxl,
                runSpacing: Spacing.lg,
                children: [
                  if (publication.language != null) _metadata(context, 'Language', publication.language!),
                  if (publication.publisher != null) _metadata(context, 'Publisher', publication.publisher!),
                  if (publication.isbn != null) _metadata(context, 'ISBN', publication.isbn!),
                ],
              ),
            ],
            const SizedBox(height: Spacing.xl),
          ],
        ),
      );
    },
  );

  Widget _metadata(BuildContext context, String label, String value) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 320),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: Spacing.xs),
        Text(value, style: Theme.of(context).textTheme.bodyMedium),
      ],
    ),
  );
}

class _DownloadOptions extends StatefulWidget {
  const _DownloadOptions({
    required this.catalog,
    required this.publication,
    required this.downloads,
    required this.onDownload,
    required this.onNavigate,
  });
  final OpdsCatalog catalog;
  final OpdsPublication publication;
  final OpdsDownloads downloads;
  final ValueChanged<OpdsLink> onDownload;
  final ValueChanged<Uri> onNavigate;
  @override
  State<_DownloadOptions> createState() => _DownloadOptionsState();
}

class _DownloadOptionsState extends State<_DownloadOptions> {
  bool _showUnsupported = false;

  @override
  Widget build(BuildContext context) {
    final links = widget.publication.links.where((link) => link.isAcquisition);
    final supported = links.where(OpdsDownloads.supports).toList();
    final unsupported = links.where((link) => !OpdsDownloads.supports(link)).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.publication.title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: Spacing.xs),
        const Text('Choose a format to add to your library.'),
        const SizedBox(height: Spacing.sm),
        AnimatedBuilder(
          animation: widget.downloads,
          builder: (_, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [for (final link in supported) _format(context, link)],
          ),
        ),
        if (supported.isEmpty) const Text('No direct downloads are available for this publication.'),
        if (widget.publication.detailLink != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                widget.onNavigate(widget.publication.detailLink!.uri);
              },
              icon: const Icon(Icons.arrow_forward),
              label: const Text('Full catalog details'),
            ),
          ),
        if (unsupported.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
            child: Semantics(
              expanded: _showUnsupported,
              child: TextButton(
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, TouchTargets.mobileRecommended),
                  padding: const EdgeInsets.all(Spacing.sm),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                  foregroundColor: Theme.of(context).colorScheme.onSurface,
                  textStyle: Theme.of(context).textTheme.titleSmall,
                  alignment: Alignment.centerLeft,
                ),
                onPressed: () => setState(() => _showUnsupported = !_showUnsupported),
                child: Row(
                  children: [
                    Expanded(child: Text('Other catalog options (${unsupported.length})')),
                    const SizedBox(width: Spacing.md),
                    Icon(
                      _showUnsupported ? Icons.expand_less : Icons.expand_more,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_showUnsupported) ...[
            const Text('These formats or acquisition methods cannot be imported on this device.'),
            for (final link in unsupported)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.info_outline),
                title: Text(link.title ?? link.type ?? 'Catalog acquisition'),
              ),
          ],
        ],
      ],
    );
  }

  Widget _format(BuildContext context, OpdsLink link) {
    final theme = Theme.of(context);
    final key = OpdsDownloads.jobKey(widget.catalog, widget.publication, link);
    final jobs = widget.downloads.jobs.where((job) => job.key == key);
    final job = jobs.isEmpty ? null : jobs.first;
    final format = link.supportedExtension!.toUpperCase();
    final complete = job?.status == OpdsDownloadStatus.complete;
    final active = job?.isActive ?? false;
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.colorScheme.outlineVariant)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Spacing.listItemPaddingVertical),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final label = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(format, style: theme.textTheme.titleSmall),
                    if (link.title != null && link.title!.toUpperCase() != format)
                      Text(
                        link.title!,
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                  ],
                );
                final button = FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                  onPressed: active
                      ? null
                      : complete
                      ? job?.bookId == null
                            ? null
                            : () {
                                Navigator.of(context).pop();
                                context.go('/library/details/${Uri.encodeComponent(job!.bookId!)}');
                              }
                      : () => widget.onDownload(link),
                  icon: Icon(complete ? Icons.check : Icons.download_outlined, size: IconSizes.small),
                  label: Text(
                    complete
                        ? 'Open book'
                        : job?.error != null
                        ? 'Retry download'
                        : 'Download $format',
                  ),
                );
                return constraints.maxWidth < 400
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          label,
                          const SizedBox(height: Spacing.sm),
                          button,
                        ],
                      )
                    : Row(
                        children: [
                          Expanded(child: label),
                          const SizedBox(width: Spacing.md),
                          button,
                        ],
                      );
              },
            ),
            if (active) ...[
              const SizedBox(height: Spacing.sm),
              Row(
                children: [
                  Expanded(child: Text(opdsDownloadStatus(job!), style: theme.textTheme.bodySmall)),
                  if (job.isCancellable)
                    TextButton(onPressed: () => widget.downloads.cancel(job.key), child: const Text('Cancel')),
                ],
              ),
              const SizedBox(height: Spacing.sm),
              AppLinearProgressIndicator(value: job.progress),
            ],
            if (job?.error != null)
              Padding(
                padding: const EdgeInsets.only(top: Spacing.sm),
                child: Text(job!.error!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
              ),
          ],
        ),
      ),
    );
  }
}
