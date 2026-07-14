import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:papyrus/data/data_store.dart';
import 'package:papyrus/media/media_upload_queue.dart';
import 'package:papyrus/models/book.dart';
import 'package:papyrus/powersync/powersync_service.dart';
import 'package:papyrus/powersync/sync_state.dart';
import 'package:papyrus/providers/auth_provider.dart';
import 'package:papyrus/services/book_import_commit_service.dart';
import 'package:papyrus/services/book_import_service_stub.dart'
    if (dart.library.js_interop) 'package:papyrus/services/book_import_service.dart';
import 'package:papyrus/themes/design_tokens.dart';
import 'package:papyrus/widgets/shared/bottom_sheet_handle.dart';
import 'package:papyrus/widgets/shared/bottom_sheet_header.dart';
import 'package:provider/provider.dart';

enum _ImportState { idle, processing, success, error }

/// Sheet for importing a digital book file.
///
/// Opens a file picker, processes the file in a Web Worker,
/// previews the extracted metadata, and adds the book to the library.
class ImportBookSheet extends StatelessWidget {
  const ImportBookSheet({super.key}) : initialResult = null;

  @visibleForTesting
  const ImportBookSheet.withInitialResult(this.initialResult, {super.key});

  final BookImportResult? initialResult;

  /// Show the import sheet as a scrollable, content-sized bottom sheet.
  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
      builder: (_) => const ImportBookSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(child: _ImportContent(initialResult: initialResult));
  }
}

class _ImportContent extends StatefulWidget {
  const _ImportContent({this.initialResult});

  final BookImportResult? initialResult;

  @override
  State<_ImportContent> createState() => _ImportContentState();
}

class _ImportContentState extends State<_ImportContent> {
  static const double _pendingContentHeight = 232;

  final _importService = BookImportService();
  late _ImportState _state;
  String? _filename;
  String? _errorMessage;
  BookImportResult? _result;

  @override
  void initState() {
    super.initState();
    _result = widget.initialResult;
    _state = _result == null ? _ImportState.idle : _ImportState.success;
  }

  @override
  void dispose() {
    _importService.dispose();
    super.dispose();
  }

  /// Allowed file extensions per platform.
  static const _webExtensions = ['epub'];
  static const _nativeExtensions = ['epub', 'pdf', 'mobi', 'azw3', 'txt', 'cbr', 'cbz'];

  /// Schedule a setState that is guaranteed to trigger a frame.
  ///
  /// On web, setState called from a continuation resumed by a JS callback
  /// (e.g. Web Worker message) may not trigger frame scheduling because the
  /// callback runs outside Flutter's animation frame context. Wrapping in
  /// [Timer.run] pushes the call into the event loop proper.
  void _safeSetState(VoidCallback fn) {
    Timer.run(() {
      if (!mounted) return;
      setState(fn);
    });
  }

  bool _picking = false;
  bool _committing = false;

  Future<void> _pickAndProcess() async {
    if (_picking || _committing) return;
    _picking = true;

    try {
      final extensions = kIsWeb ? _webExtensions : _nativeExtensions;
      final pickerResult = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: extensions,
        withData: true,
      );

      if (!mounted) return;
      if (pickerResult == null || pickerResult.files.isEmpty) return;

      final file = pickerResult.files.first;
      final bytes = file.bytes;
      if (bytes == null) {
        _safeSetState(() {
          _state = _ImportState.error;
          _errorMessage = 'Could not read the selected file.';
        });
        return;
      }

      _safeSetState(() {
        _state = _ImportState.processing;
        _filename = file.name;
        _errorMessage = null;
      });

      final results = await Future.wait([
        _importService.importBook(bytes, file.name),
        Future.delayed(const Duration(milliseconds: 800)),
      ]);
      final result = results[0] as BookImportResult;
      _safeSetState(() {
        _state = _ImportState.success;
        _result = result;
      });
    } catch (e) {
      _safeSetState(() {
        _state = _ImportState.error;
        _errorMessage = e.toString();
      });
    } finally {
      _picking = false;
    }
  }

  Future<void> _addToLibrary() async {
    if (_committing) return;
    final result = _result;
    if (result == null) return;
    setState(() => _committing = true);

    Book? committedBook;
    try {
      final dataStore = context.read<DataStore>();
      final bookRepository = dataStore.requireBookRepository();
      final queue = context.read<MediaUploadQueue>();
      final importService = context.read<BookImportService>();
      final authProvider = context.read<AuthProvider>();
      final powerSyncService = context.read<PapyrusPowerSyncService>();
      final isOnlineAccount = authProvider.isSignedIn && powerSyncService.mode == LibraryDatabaseMode.authenticated;
      final accountScope = isOnlineAccount ? queue.activeScope : null;
      if (isOnlineAccount && accountScope == null) {
        throw StateError('Cannot import account media without an active media storage scope');
      }

      final ext = result.fileExtension;
      final filePath = kIsWeb
          ? 'opfs://books/${result.bookId}.$ext'
          : result.bookId; // Native resolves via BookImportService.getBookFile
      final commitService = BookImportCommitService(
        storePendingCover: importService.storePendingCoverFile,
        storeGuestCover: importService.storeGuestCoverFile,
        deletePendingCover: importService.deletePendingCoverFile,
        deleteGuestCover: importService.deleteGuestCoverFile,
        addBook: (book) => dataStore.addBookToRepositoryAndWait(bookRepository, book),
        deleteBook: (bookId) => dataStore.deleteBookFromRepositoryAndWait(bookRepository, bookId),
        enqueueImportedBookMedia: queue.enqueueImportedBookMedia,
        isLibraryContextCurrent: () {
          final currentIsOnlineAccount =
              authProvider.isSignedIn && powerSyncService.mode == LibraryDatabaseMode.authenticated;
          return dataStore.isBookRepositoryCurrent(bookRepository) &&
              currentIsOnlineAccount == isOnlineAccount &&
              queue.activeScope == accountScope;
        },
      );
      committedBook = await commitService.commit(
        result: result,
        sourceFilename: _filename ?? '${result.bookId}.$ext',
        addedAt: DateTime.now(),
        localFilePath: filePath,
        accountScope: accountScope,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _state = _ImportState.error;
        _errorMessage = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() => _committing = false);
      }
    }

    if (!mounted || committedBook == null) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    messenger.showSnackBar(SnackBar(content: Text('Added "${committedBook.title}" to library')));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Spacing.md, Spacing.md, Spacing.md, 0),
          child: Column(
            children: [
              const BottomSheetHandle(),
              const SizedBox(height: Spacing.md),
              BottomSheetHeader(title: 'Import book', onCancel: () => Navigator.of(context).pop()),
            ],
          ),
        ),
        const SizedBox(height: Spacing.md),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Spacing.lg, vertical: Spacing.md),
          child: switch (_state) {
            _ImportState.idle => _buildIdleState(context),
            _ImportState.processing => _buildProcessingState(context),
            _ImportState.success => _buildSuccessState(context),
            _ImportState.error => _buildErrorState(context),
          },
        ),
      ],
    );
  }

  Widget _buildIdleState(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return _buildPendingContent(
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.upload_file, size: 48, color: colorScheme.primary),
          const SizedBox(height: Spacing.md),
          Text('Select a digital book file', style: textTheme.titleMedium),
          const SizedBox(height: Spacing.xs),
          Text(
            'EPUB, PDF, AZW3, MOBI, CBZ/CBR',
            style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: Spacing.lg),
          FilledButton.icon(
            onPressed: _committing ? null : _pickAndProcess,
            icon: const Icon(Icons.folder_open),
            label: const Text('Browse files'),
          ),
        ],
      ),
    );
  }

  Widget _buildProcessingState(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return _buildPendingContent(
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(width: 48, height: 48, child: CircularProgressIndicator()),
          const SizedBox(height: Spacing.lg),
          Text('Processing...', style: textTheme.titleMedium),
          if (_filename != null) ...[
            const SizedBox(height: Spacing.xs),
            Text(_filename!, style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant)),
          ],
        ],
      ),
    );
  }

  Widget _buildPendingContent(Widget child) {
    return SizedBox(
      key: const Key('import-pending-content'),
      width: double.infinity,
      height: _pendingContentHeight,
      child: Center(child: child),
    );
  }

  Widget _buildSuccessState(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final result = _result!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cover preview
            Container(
              width: 80,
              height: 120,
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              clipBehavior: Clip.antiAlias,
              child: result.coverImage != null
                  ? Image.memory(result.coverImage!, fit: BoxFit.cover)
                  : Center(child: Icon(Icons.menu_book, size: 32, color: colorScheme.onSurfaceVariant)),
            ),
            const SizedBox(width: Spacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(result.title, style: textTheme.titleMedium),
                  const SizedBox(height: Spacing.xs),
                  Text(result.author, style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant)),
                  if (result.pageCount != null) ...[
                    const SizedBox(height: Spacing.xs),
                    Text(
                      '~${result.pageCount} pages',
                      style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: Spacing.lg),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _committing
                    ? null
                    : () {
                        setState(() {
                          _state = _ImportState.idle;
                          _result = null;
                          _filename = null;
                        });
                      },
                style: OutlinedButton.styleFrom(shape: const StadiumBorder()),
                child: const Text('Pick different file'),
              ),
            ),
            const SizedBox(width: Spacing.md),
            Expanded(
              child: FilledButton(
                onPressed: _committing ? null : _addToLibrary,
                style: FilledButton.styleFrom(shape: const StadiumBorder()),
                child: const Text('Add to library'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildErrorState(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        border: Border.all(color: colorScheme.error.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        children: [
          Icon(Icons.error_outline, size: 48, color: colorScheme.error),
          const SizedBox(height: Spacing.md),
          Text(
            _errorMessage ?? 'Something went wrong',
            style: textTheme.bodyMedium?.copyWith(color: colorScheme.error),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: Spacing.lg),
          FilledButton(onPressed: _committing ? null : _pickAndProcess, child: const Text('Try again')),
        ],
      ),
    );
  }
}
