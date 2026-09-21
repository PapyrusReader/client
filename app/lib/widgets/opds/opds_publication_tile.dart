import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:papyrus/opds/opds_http_client.dart';
import 'package:papyrus/opds/opds_models.dart';
import 'package:papyrus/themes/design_tokens.dart';

class OpdsPublicationTile extends StatelessWidget {
  const OpdsPublicationTile({
    super.key,
    required this.catalog,
    required this.publication,
    required this.onOpen,
    required this.httpClient,
    this.credentials,
    this.isGridView = false,
  });
  final OpdsCatalog catalog;
  final OpdsPublication publication;
  final VoidCallback onOpen;
  final OpdsHttpClient httpClient;
  final OpdsCredentials? credentials;
  final bool isGridView;

  Widget _cover({double width = double.infinity, double height = double.infinity}) => OpdsCover(
    catalog: catalog,
    uri: publication.images.isEmpty ? null : publication.images.first.uri,
    credentials: credentials,
    httpClient: httpClient,
    width: width,
    height: height,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final acquisition = publication.links.where((link) => link.isAcquisition);
    final formats = acquisition
        .map((link) => link.supportedExtension?.toUpperCase())
        .whereType<String>()
        .toSet()
        .join(' · ');
    final edition = acquisition.isEmpty ? null : acquisition.first.title;
    final caption = edition ?? (formats.isEmpty ? 'View details' : formats);
    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(publication.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
        const SizedBox(height: Spacing.xs),
        Text(
          publication.authors.isEmpty ? 'Unknown author' : publication.authors.join(', '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: Spacing.xs),
        Text(
          caption,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.primary),
        ),
      ],
    );
    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(AppRadius.md),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: isGridView
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AspectRatio(aspectRatio: 2 / 3, child: _cover()),
                  Padding(padding: const EdgeInsets.all(Spacing.sm), child: info),
                ],
              )
            : Padding(
                padding: const EdgeInsets.all(Spacing.md),
                child: Row(
                  children: [
                    ClipRRect(borderRadius: BorderRadius.circular(AppRadius.sm), child: _cover(width: 60, height: 90)),
                    const SizedBox(width: Spacing.md),
                    Expanded(child: info),
                    const SizedBox(width: Spacing.sm),
                    const Icon(Icons.chevron_right, size: IconSizes.small),
                  ],
                ),
              ),
      ),
    );
  }
}

class OpdsCover extends StatefulWidget {
  const OpdsCover({
    super.key,
    required this.catalog,
    required this.uri,
    required this.httpClient,
    this.credentials,
    this.width = 40,
    this.height = 56,
  });
  final OpdsCatalog catalog;
  final Uri? uri;
  final OpdsHttpClient httpClient;
  final OpdsCredentials? credentials;
  final double width;
  final double height;
  @override
  State<OpdsCover> createState() => _OpdsCoverState();
}

class _OpdsCoverState extends State<OpdsCover> {
  OpdsCancellation _token = OpdsCancellation();
  Uint8List? _bytes;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant OpdsCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uri != widget.uri ||
        oldWidget.catalog != widget.catalog ||
        oldWidget.credentials != widget.credentials) {
      _load();
    }
  }

  Future<void> _load() async {
    _token.cancel();
    final token = _token = OpdsCancellation();
    _bytes = null;
    if (widget.uri == null || !['http', 'https'].contains(widget.uri!.scheme)) return;
    try {
      final response = await widget.httpClient.get(
        widget.catalog,
        widget.uri!,
        credentials: widget.credentials,
        cancellation: token,
      );
      if (mounted && !token.isCancelled) setState(() => _bytes = response.bytes);
    } catch (_) {
      // Catalog artwork is optional; keep the themed cover placeholder.
    }
  }

  @override
  void dispose() {
    _token.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final placeholder = ColoredBox(
      color: colors.surfaceContainerHighest,
      child: Center(
        child: Icon(Icons.menu_book_outlined, size: widget.width <= 56 ? 24 : 48, color: colors.onSurfaceVariant),
      ),
    );
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: _bytes == null
          ? placeholder
          : Image.memory(_bytes!, fit: BoxFit.cover, errorBuilder: (_, _, _) => placeholder),
    );
  }
}
