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
typedef LocalBookCoverLoader = Future<Uint8List?> Function(String bookId);

/// Renders a public cover URL or a lazily persisted authenticated cover.
class PrivateBookCover extends StatefulWidget {
  const PrivateBookCover({
    super.key,
    this.bookId,
    this.imageUrl,
    this.mediaId,
    this.fit = BoxFit.cover,
    required this.placeholder,
    this.loadPrivateCover,
    this.loadLocalBookCover,
  });

  final String? bookId;
  final String? imageUrl;
  final String? mediaId;
  final BoxFit fit;
  final Widget placeholder;
  final PrivateCoverLoader? loadPrivateCover;
  final LocalBookCoverLoader? loadLocalBookCover;

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
    if (!_hasInjectedLoaderForCurrentSource) {
      _configureProviderLoader();
    }
  }

  @override
  void didUpdateWidget(covariant PrivateBookCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl ||
        oldWidget.mediaId != widget.mediaId ||
        oldWidget.bookId != widget.bookId ||
        (oldWidget.loadPrivateCover == null) != (widget.loadPrivateCover == null) ||
        (oldWidget.loadLocalBookCover == null) != (widget.loadLocalBookCover == null)) {
      _coverFuture = null;
      _loadKey = null;
      _configureInjectedLoader();
      if (!_hasInjectedLoaderForCurrentSource) {
        _configureProviderLoader();
      }
    }
  }

  void _configureInjectedLoader() {
    if (_hasPublicUrl) return;

    final mediaId = _usableMediaId;
    if (mediaId != null) {
      final loader = widget.loadPrivateCover;
      if (loader == null) return;
      final key = 'injected-media:$mediaId';
      if (_loadKey == key) return;
      _loadKey = key;
      _coverFuture = loader(mediaId);
      return;
    }

    final bookId = _usableBookId;
    final loader = widget.loadLocalBookCover;
    if (bookId == null || loader == null) return;
    final key = 'injected-local:$bookId';
    if (_loadKey == key) return;
    _loadKey = key;
    _coverFuture = loader(bookId);
  }

  void _configureProviderLoader() {
    try {
      _configureProviderLoaderFromContext();
    } on ProviderNotFoundException {
      // Standalone cover surfaces can still render their placeholder.
    }
  }

  void _configureProviderLoaderFromContext() {
    if (_hasPublicUrl) return;

    final mediaId = _usableMediaId;
    final authProvider = context.read<AuthProvider>();
    final user = authProvider.user;
    if (mediaId != null) {
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
      return;
    }

    final bookId = _usableBookId;
    if (bookId == null) return;

    final importService = context.read<BookImportService>();
    if (authProvider.isSignedIn && !authProvider.isOfflineMode && user != null) {
      final syncSettings = context.read<SyncSettingsProvider>();
      final scope = MediaStorageScope(profileKey: syncSettings.activeProfileKey, userId: user.userId);
      final key = 'local:$bookId:account:${scope.persistenceKey}';
      if (_loadKey == key) return;
      _loadKey = key;
      _coverFuture = importService.getPendingCoverFile(scope, bookId);
      return;
    }

    final key = 'local:$bookId:guest:no-scope';
    if (_loadKey == key) return;
    _loadKey = key;
    _coverFuture = importService.getGuestCoverFile(bookId);
  }

  bool get _hasPublicUrl => widget.imageUrl != null && widget.imageUrl!.isNotEmpty;
  bool get _hasInlineDataUri => widget.imageUrl?.startsWith('data:') ?? false;
  String? get _usableMediaId => widget.mediaId == null || widget.mediaId!.isEmpty ? null : widget.mediaId;
  String? get _usableBookId => widget.bookId == null || widget.bookId!.isEmpty ? null : widget.bookId;

  bool get _hasInjectedLoaderForCurrentSource {
    if (_hasPublicUrl) return true;
    if (_usableMediaId != null) return widget.loadPrivateCover != null;
    if (_usableBookId != null) return widget.loadLocalBookCover != null;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    if (_hasInlineDataUri) {
      try {
        final data = Uri.parse(widget.imageUrl!).data;
        if (data != null && data.mimeType.startsWith('image/')) {
          final bytes = data.contentAsBytes();
          return Image.memory(bytes, fit: widget.fit, errorBuilder: (_, _, _) => widget.placeholder);
        }
      } on FormatException {
        return widget.placeholder;
      }
      return widget.placeholder;
    }

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
