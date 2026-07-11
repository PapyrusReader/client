import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:papyrus/media/media_cache_service.dart';
import 'package:papyrus/media/media_storage_scope.dart';
import 'package:papyrus/providers/auth_provider.dart';
import 'package:papyrus/providers/sync_settings_provider.dart';
import 'package:papyrus/services/book_import_service_stub.dart'
    if (dart.library.js_interop) 'package:papyrus/services/book_import_service.dart';
import 'package:provider/provider.dart';

typedef PrivateCoverLoader = Future<Uint8List?> Function(String mediaId);

/// Renders a public cover URL or a lazily persisted authenticated cover.
class PrivateBookCover extends StatefulWidget {
  const PrivateBookCover({
    super.key,
    this.imageUrl,
    this.mediaId,
    this.fit = BoxFit.cover,
    required this.placeholder,
    this.loadPrivateCover,
  });

  final String? imageUrl;
  final String? mediaId;
  final BoxFit fit;
  final Widget placeholder;
  final PrivateCoverLoader? loadPrivateCover;

  @override
  State<PrivateBookCover> createState() => _PrivateBookCoverState();
}

class _PrivateBookCoverState extends State<PrivateBookCover> {
  Future<Uint8List?>? _coverFuture;
  String? _loadKey;

  @override
  void initState() {
    super.initState();
    _configureInjectedLoader();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.loadPrivateCover == null) {
      _configureProviderLoader();
    }
  }

  @override
  void didUpdateWidget(covariant PrivateBookCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl ||
        oldWidget.mediaId != widget.mediaId ||
        !identical(oldWidget.loadPrivateCover, widget.loadPrivateCover)) {
      _coverFuture = null;
      _loadKey = null;
      _configureInjectedLoader();
      if (widget.loadPrivateCover == null) {
        _configureProviderLoader();
      }
    }
  }

  void _configureInjectedLoader() {
    final mediaId = widget.mediaId;
    final loader = widget.loadPrivateCover;
    if (_hasPublicUrl || mediaId == null || mediaId.isEmpty || loader == null) return;
    final key = 'injected:$mediaId';
    if (_loadKey == key) return;
    _loadKey = key;
    _coverFuture = loader(mediaId);
  }

  void _configureProviderLoader() {
    final mediaId = widget.mediaId;
    if (_hasPublicUrl || mediaId == null || mediaId.isEmpty) return;

    final authProvider = context.read<AuthProvider>();
    final user = authProvider.user;
    if (!authProvider.isSignedIn || authProvider.isOfflineMode || user == null) return;

    final syncSettings = context.read<SyncSettingsProvider>();
    final scope = MediaStorageScope(profileKey: syncSettings.activeProfileKey, userId: user.userId);
    final key = '${scope.persistenceKey}:$mediaId';
    if (_loadKey == key) return;

    final importService = context.read<BookImportService>();
    final cacheService = context.read<MediaCacheService>();
    _loadKey = key;
    _coverFuture = cacheService.ensureCoverCached(
      scope: scope,
      mediaId: mediaId,
      readLocalCover: importService.getCoverFile,
      writeLocalCover: importService.storeCoverFile,
      downloadMedia: authProvider.downloadMedia,
    );
  }

  bool get _hasPublicUrl => widget.imageUrl != null && widget.imageUrl!.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    if (_hasPublicUrl) {
      return CachedNetworkImage(
        imageUrl: widget.imageUrl!,
        fit: widget.fit,
        errorWidget: (_, _, _) => widget.placeholder,
      );
    }

    final coverFuture = _coverFuture;
    if (coverFuture == null) return widget.placeholder;

    return FutureBuilder<Uint8List?>(
      future: coverFuture,
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes != null) {
          return Image.memory(bytes, fit: widget.fit, errorBuilder: (_, _, _) => widget.placeholder);
        }
        if (snapshot.hasError) return widget.placeholder;
        return widget.placeholder;
      },
    );
  }
}
