import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:papyrus/models/book.dart';
import 'package:papyrus/opds/opds_catalog_store.dart';
import 'package:papyrus/opds/opds_catalogs.dart';
import 'package:papyrus/opds/opds_downloads.dart';
import 'package:papyrus/opds/opds_http_client.dart';
import 'package:papyrus/opds/opds_models.dart';
import 'package:papyrus/services/book_import_session.dart';
import 'package:papyrus/services/book_import_result.dart';
import 'package:papyrus/themes/app_theme.dart';
import 'package:papyrus/themes/app_motion.dart';
import 'package:papyrus/widgets/opds/catalog_editor.dart';
import 'package:papyrus/widgets/opds/opds_download_panel.dart';
import 'package:papyrus/widgets/shared/app_progress_indicator.dart';
import 'package:papyrus/widgets/shared/bottom_sheet_handle.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'catalog_store_test.dart' show MemorySecrets;

class _PendingStore extends OpdsCatalogStore {
  _PendingStore(super.prefs) : super(secrets: MemorySecrets());
  final finish = Completer<void>();

  @override
  Future<void> save(
    String scope,
    OpdsCatalog catalog, {
    OpdsCredentials? credentials,
    bool clearCredentials = false,
  }) async {
    await finish.future;
    return super.save(scope, catalog, credentials: credentials, clearCredentials: clearCredentials);
  }
}

final _catalog = OpdsCatalog(id: 'one', name: 'Books', uri: Uri.parse('https://books.test/feed'));
final _publication = OpdsPublication(id: 'book', title: 'A long book title that wraps on a small display');
final _link = OpdsLink(
  uri: Uri.parse('https://books.test/book.epub'),
  type: 'application/epub+zip',
  rels: ['download'],
);

class _PendingHttp extends OpdsHttpClient {
  final response = Completer<OpdsResponse>();
  void Function(int, int?)? progress;

  @override
  Future<OpdsResponse> get(
    OpdsCatalog catalog,
    Uri uri, {
    OpdsCredentials? credentials,
    OpdsCancellation? cancellation,
    void Function(int, int?)? onProgress,
    int maxBytes = 8 * 1024 * 1024,
  }) {
    progress = onProgress;

    cancellation?.addListener(() {
      if (!response.isCompleted) {
        response.completeError(const OpdsCancelled());
      }
    });

    onProgress?.call(20, 100);
    return response.future;
  }
}

BookImportSession _unusedSession() => BookImportSession(
  process: (_, _) async => throw StateError('Unexpected import'),
  deleteFile: (_) async {},
  commit: (_, _) async => throw StateError('Unexpected commit'),
  isCurrent: () => true,
);

Future<void> _mountDownloads(WidgetTester tester, OpdsDownloads downloads, ValueChanged<OpdsDownloadJob> retry) async {
  tester.view.physicalSize = const Size(360, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.eink,
      home: Scaffold(
        appBar: AppBar(
          actions: [OpdsDownloadsButton(downloads: downloads, onRetry: retry)],
        ),
      ),
    ),
  );

  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    downloads.dispose();
  });

  await tester.pumpAndSettle();
}

void main() {
  testWidgets('catalog editor backdrop covers the sidebar and blocks its actions while saving', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 1000);
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final store = _PendingStore(await SharedPreferences.getInstance());
    final catalogs = OpdsCatalogs(store)..setScope('local--guest');
    var sidebarTaps = 0;

    final router = GoRouter(
      routes: [
        ShellRoute(
          builder: (_, _, child) => Scaffold(
            body: Row(
              children: [
                SizedBox(
                  width: 280,
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: TextButton(onPressed: () => sidebarTaps++, child: const Text('Sidebar action')),
                  ),
                ),
                Expanded(child: AppMotionScope(reduceAnimations: true, child: child)),
              ],
            ),
          ),
          routes: [
            GoRoute(
              path: '/',
              builder: (context, _) => Center(
                child: TextButton(
                  onPressed: () => CatalogEditor.show(context, catalogs: catalogs),
                  child: const Text('Open editor'),
                ),
              ),
            ),
          ],
        ),
      ],
    );

    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      router.dispose();
      catalogs.dispose();
    });

    await tester.pumpWidget(MaterialApp.router(theme: AppTheme.light, routerConfig: router));
    await tester.pumpAndSettle();
    final sidebarPosition = tester.getCenter(find.text('Sidebar action'));
    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();
    expect(AppMotion.disabled(tester.element(find.byType(CatalogEditor))), isTrue);
    final barrier = tester.getRect(find.byWidgetPredicate((widget) => widget is ModalBarrier && widget.color != null));
    expect(barrier.left, 0);
    expect(barrier.width, 1200);
    await tester.enterText(find.byKey(const Key('opds-name')), 'My catalog');
    await tester.enterText(find.byKey(const Key('opds-url')), 'https://books.test/feed');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.tapAt(sidebarPosition);
    await tester.pumpAndSettle();
    expect(sidebarTaps, 0);
    expect(find.byType(BottomSheet), findsOneWidget);
    store.finish.completeError(const OpdsException('Save failed.'));
    await tester.pumpAndSettle();
    await tester.tapAt(sidebarPosition);
    await tester.pumpAndSettle();
    expect(sidebarTaps, 0);
    expect(find.byType(BottomSheet), findsNothing);
    await tester.tap(find.text('Sidebar action'));
    expect(sidebarTaps, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow catalog footer keeps enlarged actions reachable above the keyboard', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    SharedPreferences.setMockInitialValues({});

    final catalogs = OpdsCatalogs(OpdsCatalogStore(await SharedPreferences.getInstance(), secrets: MemorySecrets()))
      ..setScope('local--guest');

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.eink,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => CatalogEditor.show(context, catalogs: catalogs),
              child: const Text('Open editor'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();
    final title = tester.getRect(find.text('Add catalog'));
    final footer = tester.getRect(find.byKey(const Key('opds-sheet-footer')));
    expect(title.left, 24);
    expect(find.byTooltip('Close'), findsNothing);
    expect(footer.top, greaterThan(tester.getBottomLeft(find.byKey(const Key('opds-name'))).dy));
    expect(tester.getTopLeft(find.text('Save')).dy, greaterThan(footer.top));
    final cancel = find.widgetWithText(OutlinedButton, 'Cancel');
    final save = find.widgetWithText(FilledButton, 'Save');
    expect(tester.getTopLeft(cancel).dy, tester.getTopLeft(save).dy);
    expect(tester.getSize(cancel).height, tester.getSize(save).height);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();

    for (final label in ['Cancel', 'Save']) {
      expect(find.text(label).hitTestable(), findsOneWidget);
      expect(tester.getBottomLeft(find.text(label)).dy, lessThan(340));
    }

    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    catalogs.dispose();
  });

  testWidgets('root downloads sheet preserves local reduced motion for indeterminate progress', (tester) async {
    final gateway = _PendingHttp();
    final downloads = OpdsDownloads(httpClient: gateway, captureImport: _unusedSession);
    final operation = downloads.start(_catalog, _publication, _link);
    gateway.progress!(20, null);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: AppMotionScope(
          reduceAnimations: true,
          child: Scaffold(
            body: OpdsDownloadsButton(downloads: downloads, onRetry: (_) {}),
          ),
        ),
      ),
    );

    addTearDown(() async {
      downloads.cancel(downloads.jobs.single.key);
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      downloads.dispose();
    });

    await tester.tap(find.byTooltip('Downloads'));
    await tester.pump();
    final progress = find.byType(AppLinearProgressIndicator);
    expect(AppMotion.disabled(tester.element(progress)), isTrue);
    expect(tester.widget<AppLinearProgressIndicator>(progress).value, isNull);
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
    downloads.cancel(downloads.jobs.single.key);
    await operation;
  });

  testWidgets('catalog sheet blocks drag, barrier and back while saving then allows retry', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = _PendingStore(await SharedPreferences.getInstance());
    final catalogs = OpdsCatalogs(store)..setScope('local--guest');

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.eink,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => CatalogEditor.show(context, catalogs: catalogs),
              child: const Text('Open editor'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('opds-name')), 'My catalog');
    await tester.enterText(find.byKey(const Key('opds-url')), 'https://books.test/feed');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Saving…')).onPressed, isNull);
    expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Cancel')).onPressed, isNull);
    expect(find.byIcon(Icons.close), findsNothing);
    await tester.tapAt(const Offset(10, 10));
    await tester.drag(find.byType(BottomSheetHandle), const Offset(0, 400));
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    store.finish.completeError(const OpdsException('Save failed.'));
    await tester.pumpAndSettle();
    expect(find.text('Save failed.'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save')).onPressed, isNotNull);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    catalogs.dispose();
  });

  testWidgets('catalog editor uses a sheet header and keeps Save above the keyboard', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    SharedPreferences.setMockInitialValues({});

    final catalogs = OpdsCatalogs(OpdsCatalogStore(await SharedPreferences.getInstance(), secrets: MemorySecrets()))
      ..setScope('local--guest');

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.eink,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => CatalogEditor.show(context, catalogs: catalogs),
              child: const Text('Open editor'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('opds-sheet-header')), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a name'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('opds-name')), 'My catalog');
    await tester.enterText(find.byKey(const Key('opds-url')), 'https://books.test/feed');
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    expect(tester.getBottomLeft(find.text('Save')).dy, lessThan(340));
    expect(find.text('Save').hitTestable(), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(catalogs.catalogs.single.name, 'My catalog');
    expect(find.byType(BottomSheet), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    catalogs.dispose();
  });

  testWidgets('downloads button opens a live sheet with progress and cancellation', (tester) async {
    final gateway = _PendingHttp();
    final downloads = OpdsDownloads(httpClient: gateway, captureImport: _unusedSession);
    final operation = downloads.start(_catalog, _publication, _link);
    await _mountDownloads(tester, downloads, (_) {});
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('1'), findsOneWidget);
    await tester.tap(find.byTooltip('Downloads'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('opds-sheet-header')), findsOneWidget);
    expect(find.text('Downloading · 20%'), findsOneWidget);
    gateway.progress!(70, 100);
    await tester.pumpAndSettle();
    expect(tester.widget<AppLinearProgressIndicator>(find.byType(AppLinearProgressIndicator)).value, .7);
    expect(find.byTooltip('Dismiss download'), findsNothing);
    await tester.tap(find.byTooltip('Cancel download'));
    await operation;
    await tester.pumpAndSettle();
    expect(find.text('Cancelled'), findsOneWidget);
    await tester.tap(find.byTooltip('Dismiss download'));
    await tester.pumpAndSettle();
    expect(find.text('No downloads yet'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('download failure updates header indicator and supports retry in the open sheet', (tester) async {
    final gateway = _PendingHttp();
    final downloads = OpdsDownloads(httpClient: gateway, captureImport: _unusedSession);
    final operation = downloads.start(_catalog, _publication, _link);
    final retried = <OpdsDownloadJob>[];
    await _mountDownloads(tester, downloads, retried.add);
    await tester.tap(find.byTooltip('Downloads'));
    await tester.pumpAndSettle();
    gateway.response.completeError(const OpdsException('Catalog unavailable.'));
    await operation;
    await tester.pumpAndSettle();
    expect(find.text('Catalog unavailable.'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    await tester.tap(find.text('Retry'));
    expect(retried.single, same(downloads.jobs.single));
    expect(find.text('Download in browser'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('completed download opens its library book and closes the sheet', (tester) async {
    tester.view.physicalSize = const Size(280, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final gateway = _PendingHttp();
    final finish = Completer<Book>();

    final downloads = OpdsDownloads(
      httpClient: gateway,
      captureImport: () => BookImportSession(
        process: (_, _) async => const BookImportResult(
          bookId: 'imported',
          title: 'Book',
          author: 'Author',
          fileSize: 4,
          fileHash: 'hash',
          fileExtension: 'epub',
        ),
        deleteFile: (_) async {},
        commit: (_, _) => finish.future,
        isCurrent: () => true,
      ),
    );

    final operation = downloads.start(_catalog, _publication, _link);

    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => Scaffold(
            body: OpdsDownloadsButton(downloads: downloads, onRetry: (_) {}),
          ),
        ),
        GoRoute(
          path: '/library/details/:id',
          builder: (_, state) => Scaffold(body: Text('Opened ${state.pathParameters['id']}')),
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp.router(
        theme: AppTheme.eink,
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
      ),
    );

    await tester.tap(find.byTooltip('Downloads'));
    await tester.pumpAndSettle();
    gateway.response.complete(OpdsResponse(uri: _link.uri, bytes: Uint8List.fromList([1, 2, 3]), headers: const {}));
    await tester.pumpAndSettle();
    expect(find.text('Adding to library…'), findsOneWidget);
    expect(find.byTooltip('Cancel download'), findsNothing);
    expect(find.byTooltip('Dismiss download'), findsNothing);
    finish.complete(Book(id: 'imported', title: 'Book', author: 'Author', addedAt: DateTime(2026)));
    await operation;
    await tester.pumpAndSettle();
    expect(find.byTooltip('Dismiss download'), findsOneWidget);
    await tester.tap(find.text('Open book'));
    await tester.pumpAndSettle();
    expect(find.text('Opened imported'), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    router.dispose();
    downloads.dispose();
  });
}
