import 'package:papyrus/services/reading_device_identity.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:papyrus/reader/reading_activity_tracker.dart';
import 'package:papyrus/providers/enums/library_reading_status.dart';
import 'package:go_router/go_router.dart';
import 'package:papyrus/data/data_store.dart';
import 'package:papyrus/media/media_cache_service.dart';
import 'package:papyrus/models/book.dart';
import 'package:papyrus/providers/auth_provider.dart';
import 'package:papyrus/providers/preferences_provider.dart';
import 'package:papyrus/reader/reader_book_adapter.dart';
import 'package:papyrus/reader/reader_session.dart';
import 'package:papyrus/reader/reader_panel_sheet.dart';
import 'package:papyrus/services/book_import_service_stub.dart'
    if (dart.library.js_interop) 'package:papyrus/services/book_import_service.dart';
import 'package:papyrus_reader/papyrus_reader.dart';
import 'package:provider/provider.dart';
import 'package:papyrus/widgets/shared/app_progress_indicator.dart';

class ReaderPage extends StatefulWidget {
  const ReaderPage({super.key, required this.bookId});

  final String bookId;

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  Book? _book;
  ReaderDocument? _document;
  ReaderLocator? _initialLocator;
  ReaderPreferences? _initialPreferences;
  ReaderSession? _session;
  String? _error;
  bool _startedLoading = false;
  ReadingActivityTracker? _tracker;
  DataStore? _trackingStore;
  Timer? _finishTimer;
  bool _finishPrompted = false;
  bool _promptOpen = false;
  bool _foreground = true;
  String? _trackingError;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();

    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

    _lifecycle = AppLifecycleListener(
      onStateChange: (state) {
        _foreground = state == AppLifecycleState.resumed;
        _tracker?.setForeground(_foreground && !_promptOpen);

        if (!_foreground) {
          _finishTimer?.cancel();
          _finishTimer = null;
        }
      },
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (_startedLoading) {
      return;
    }

    _startedLoading = true;
    _load();
  }

  Future<void> _load() async {
    final dataStore = context.read<DataStore>();
    final repository = dataStore.requireBookRepository();
    final trackingRepository = dataStore.trackingRepository;
    var book = dataStore.getBook(widget.bookId);
    book ??= await repository.getById(widget.bookId);

    if (book == null && !dataStore.isLoaded) {
      await dataStore.waitUntilLoaded();
      book = dataStore.getBook(widget.bookId);
    }

    if (!mounted) {
      return;
    }

    if (book == null) {
      setState(() => _error = 'Book not found.');
      return;
    }

    final format = ReaderBookAdapter.formatFor(book.fileFormat);

    if (format == null) {
      setState(() {
        _book = book;
        _error = 'This book format is not supported yet.';
      });

      return;
    }

    try {
      final importService = context.read<BookImportService>();

      final bytes = await context.read<MediaCacheService>().ensureBookFileCached(
        book,
        readLocalBookFile: importService.getBookFile,
        writeLocalBookFile: importService.storeBookFile,
        downloadMedia: context.read<AuthProvider>().downloadMedia,
      );

      if (!mounted) {
        return;
      }

      if (!dataStore.isBookRepositoryCurrent(repository) || trackingRepository?.isCurrent == false) {
        setState(() => _error = 'Your library changed. Reopen this book from the library.');
        return;
      }

      ReadingActivityTracker? tracker;

      if (trackingRepository != null) {
        tracker = ReadingActivityTracker(
          repository: trackingRepository,
          book: book,
          shelfIds: dataStore.getShelfIdsForBook(book.id),
          deviceId: ReadingDeviceIdentity.current,
          onError: (error) {
            if (!mounted || _trackingError != null) {
              return;
            }

            _trackingError = error.toString();

            ScaffoldMessenger.maybeOf(
              context,
            )?.showSnackBar(const SnackBar(content: Text('Reading activity could not be saved. Retrying.')));
          },
        );

        tracker.setForeground(_foreground);
      }

      _tracker = tracker;

      if (tracker != null) {
        _trackingStore = dataStore;
        dataStore.addListener(_scopeChanged);
      }

      final session = ReaderSession(
        book: book,
        tracker: tracker,
        saveBook: (updated) => unawaited(dataStore.updateBookAndWait(updated, repository: repository, previous: book)),
      );

      final preferences = ReaderBookAdapter.preferencesFor(
        context.read<PreferencesProvider>(),
        Theme.of(context).colorScheme,
      );

      setState(() {
        _book = book;

        _document = ReaderDocument(
          id: book!.id,
          format: format,
          title: book.title,
          author: book.author,
          loadBytes: () async => bytes,
        );

        _initialLocator = ReaderBookAdapter.restoreLocator(book);
        _initialPreferences = preferences;
        _session = session;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() => _error = 'Could not open this book file.');
    }
  }

  void _scopeChanged() => _tracker?.updateScope(_trackingStore!.getShelfIdsForBook(widget.bookId));

  @override
  void dispose() {
    _trackingStore?.removeListener(_scopeChanged);
    _finishTimer?.cancel();
    _lifecycle.dispose();
    _session?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;

    if (error != null) {
      return Scaffold(
        appBar: AppBar(leading: const BackButton()),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(error, textAlign: TextAlign.center),
          ),
        ),
      );
    }

    final book = _book;
    final document = _document;
    final preferences = _initialPreferences;

    if (book == null || document == null || preferences == null) {
      return Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        body: const SafeArea(child: _ReaderLoading()),
      );
    }

    return PapyrusReader(
      document: document,
      initialLocator: _initialLocator,
      initialPreferences: preferences,
      builders: ReaderUiBuilders(
        loading: (context, state) => const _ReaderLoading(),
        compactPanelRoute: (_, panel) => buildReaderPanelSheet(context, panel),
      ),
      onLocatorChanged: _session!.updateLocator,
      onActivity: _onActivity,
      onPreferencesChanged: (updated) {
        ReaderBookAdapter.persistPreferences(context.read<PreferencesProvider>(), updated);
      },
      onBack: _close,
    );
  }

  void _onActivity(ReaderActivityEvent event) {
    _tracker?.onActivity(event);

    if (!event.atEnd || !event.visible || !event.ready) {
      _finishTimer?.cancel();
      _finishTimer = null;

      if (!event.atEnd) {
        _finishPrompted = false;
      }

      return;
    }

    if (_foreground &&
        !_finishPrompted &&
        _finishTimer == null &&
        context.read<DataStore>().getBook(widget.bookId)?.readingStatus != LibraryReadingStatus.completed) {
      _finishTimer = Timer(const Duration(seconds: 10), _confirmFinished);
    }
  }

  Future<void> _confirmFinished() async {
    _finishTimer = null;

    if (!mounted || !_foreground || _tracker?.repository.isCurrent == false) {
      return;
    }

    _finishPrompted = true;
    _promptOpen = true;
    _tracker?.setForeground(false);

    final finished = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Finished this book?'),
        content: const Text('Mark it as finished to update your library and reading goals.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Not yet')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Mark finished')),
        ],
      ),
    );

    if (!mounted) {
      return;
    }

    try {
      if (finished == true && _tracker?.repository.isCurrent != false) {
        final store = context.read<DataStore>();
        final book = store.getBook(widget.bookId);

        if (book != null) {
          await store.updateBookAndWait(
            book.copyWith(readingStatus: LibraryReadingStatus.completed, completedAt: DateTime.now()),
            previous: book,
            completionSource: 'reader',
            completionDeviceId: _tracker?.deviceId,
          );
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text('Could not save completion. Please try again from book details.')),
        );
      }
    } finally {
      _promptOpen = false;
      _tracker?.setForeground(_foreground);
    }
  }

  Future<void> _close() async {
    _finishTimer?.cancel();

    try {
      await _tracker?.close();
      await _session?.flush();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(
          context,
        )?.showSnackBar(const SnackBar(content: Text('Could not save reading activity. Please try leaving again.')));
      }

      return;
    }

    if (!mounted) {
      return;
    }

    if (context.canPop()) {
      context.pop();
      return;
    }

    context.goNamed('BOOK_DETAILS', pathParameters: {'bookId': widget.bookId});
  }
}

class _ReaderLoading extends StatelessWidget {
  const _ReaderLoading();

  @override
  Widget build(BuildContext context) {
    return const Center(child: AppCircularProgressIndicator(semanticsLabel: 'Opening book'));
  }
}
