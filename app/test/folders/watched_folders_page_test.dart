import 'package:papyrus/widgets/folders/folder_identity.dart';
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:papyrus/data/data_store.dart';
import 'package:papyrus/auth/auth_models.dart';
import 'package:papyrus/folders/folder_models.dart';
import 'package:papyrus/folders/directory_access.dart';
import 'package:papyrus/folders/watched_folders.dart';
import 'package:papyrus/media/media_upload_queue.dart';
import 'package:papyrus/pages/library_page.dart';
import 'package:papyrus/pages/watched_folders_page.dart';
import 'package:papyrus/providers/auth_provider.dart';
import 'package:papyrus/providers/library_provider.dart';
import 'package:papyrus/themes/app_theme.dart';
import 'package:papyrus/widgets/folders/folder_details_sheet.dart';
import 'package:papyrus/widgets/folders/edit_folder_sheet.dart';
import 'package:papyrus/widgets/library/library_page_header.dart';
import 'package:papyrus/widgets/library/book_grid.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/test_helpers.dart';
import 'watched_folders_test.dart' show MemoryAccess, grant;

class _Folders extends WatchedFolders {
  _Folders() : super(access: MemoryAccess(), captureTarget: () => throw UnimplementedError(), libraryReady: () => true);
  final items = <WatchedFolder>[];
  int edits = 0;
  Object? updateFailure;
  int scans = 0;
  Completer<void>? scanPending;
  Object? scanFailure;
  String profile = 'guest';

  @override
  bool get ready => true;

  @override
  String get scope => profile;

  @override
  List<WatchedFolder> get folders => items;

  @override
  Set<String> bookIds(String folderId) => {'book-1'};

  @override
  Future<void> update(
    WatchedFolder folder, {
    String? name,
    bool? enabled,
    bool? recursive,
    String? shelfId,
    bool changeShelf = false,
  }) async {
    if (updateFailure != null) {
      throw updateFailure!;
    }

    edits++;
    folder.customName = name?.trim() ?? folder.customName;
    folder.recursive = recursive ?? folder.recursive;
    folder.enabled = enabled ?? folder.enabled;
    folder.status = folder.enabled ? FolderStatus.upToDate : FolderStatus.paused;

    if (changeShelf) {
      folder.shelfId = shelfId;
    }

    notifyListeners();
  }

  @override
  Future<void> scanNow(String id) async {
    scans++;
    await scanPending?.future;

    if (scanFailure != null) {
      throw scanFailure!;
    }
  }

  void switchProfile() {
    profile = 'another';
    items.clear();
    notifyListeners();
  }
}

class _Auth extends ChangeNotifier implements AuthProvider {
  @override
  PapyrusUser? get user => null;
  @override
  bool get isOfflineMode => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _capture = bool.fromEnvironment('FOLDER_DESIGN_CAPTURE');
final _reviewBoundary = GlobalKey();

ThemeData _captureTheme(ThemeData theme) {
  if (!_capture) {
    return theme;
  }

  // Resolve the platform font for component styles that otherwise use Ahem in tests.
  ButtonStyle? font(ButtonStyle? style) => style?.copyWith(
    textStyle: WidgetStateProperty.resolveWith(
      (states) => style.textStyle?.resolve(states)?.copyWith(fontFamily: 'Roboto'),
    ),
  );

  return theme.copyWith(
    textButtonTheme: TextButtonThemeData(style: font(theme.textButtonTheme.style)),
    outlinedButtonTheme: OutlinedButtonThemeData(style: font(theme.outlinedButtonTheme.style)),
    elevatedButtonTheme: ElevatedButtonThemeData(style: font(theme.elevatedButtonTheme.style)),
    chipTheme: theme.chipTheme.copyWith(labelStyle: theme.chipTheme.labelStyle?.copyWith(fontFamily: 'Roboto')),
  );
}

Future<void> _captureReview(WidgetTester tester, String name) async {
  if (!_capture) {
    return;
  }

  await tester.runAsync(() async {
    final boundary = _reviewBoundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final directory = Directory('build/folder-review')..createSync(recursive: true);
    await File('${directory.path}/$name.png').writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    if (_capture) {
      final flutterRoot = Platform.environment['FLUTTER_ROOT']!;

      for (final (family, file) in [('Roboto', 'Roboto-Regular.ttf'), ('MaterialIcons', 'MaterialIcons-Regular.otf')]) {
        final font = File('$flutterRoot/bin/cache/artifacts/material_fonts/$file');
        await (FontLoader(family)..addFont(Future.value(ByteData.sublistView(font.readAsBytesSync())))).load();
      }
    }
  });
  late _Folders folders;
  late DataStore store;
  late _Auth auth;
  late MediaUploadQueue uploads;
  late LibraryProvider library;
  late GoRouter router;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    folders = _Folders();
    store = createTestDataStore();
    auth = _Auth();
    uploads = MediaUploadQueue(await SharedPreferences.getInstance());
    library = LibraryProvider();
    router = GoRouter(
      initialLocation: '/library/folders',
      routes: [
        GoRoute(path: '/library/folders', builder: (_, _) => const WatchedFoldersPage()),
        GoRoute(
          path: '/library/books',
          builder: (_, state) => const LibraryPage(),
        ),
      ],
    );
  });

  tearDown(() {
    router.dispose();
    folders.dispose();
    store.dispose();
    auth.dispose();
    uploads.dispose();
    library.dispose();
  });

  Future<void> mount(
    WidgetTester tester, {
    Size size = const Size(1200, 900),
    ThemeData? theme,
    double textScale = 1,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<WatchedFolders>.value(value: folders),
          ChangeNotifierProvider<DataStore>.value(value: store),
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProvider<MediaUploadQueue>.value(value: uploads),
          ChangeNotifierProvider<LibraryProvider>.value(value: library),
        ],
        child: MaterialApp.router(
          theme: _captureTheme(theme ?? AppTheme.light),
          routerConfig: router,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
            child: RepaintBoundary(key: _reviewBoundary, child: child!),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final size in [const Size(390, 844), const Size(1200, 900)]) {
    testWidgets('one empty-state action and stable list actions at $size', (tester) async {
      await mount(tester, size: size);
      expect(find.text('Connect folder'), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsNothing);
      final toolbar = find.byType(size.width < 840 ? LibraryMobileToolbar : LibraryToolbar);
      final toolbarPosition = tester.getTopLeft(toolbar);
      folders.items.add(WatchedFolder(id: 'folder', grant: grant));
      folders.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.descendant(of: find.byType(FolderIdentity), matching: find.text('Books')), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.byType(Card), findsNothing);
      expect(find.text('Account upload'), findsNothing);
      expect(tester.getTopLeft(toolbar), toolbarPosition);
      expect(find.byType(FloatingActionButton), size.width < 840 ? findsOneWidget : findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  for (final size in [const Size(390, 844), const Size(820, 900), const Size(1200, 800)]) {
    testWidgets('folder table aligns rows and opens compact details at $size', (tester) async {
      folders.items.addAll([
        WatchedFolder(
          id: 'folder',
          customName: 'Reading inbox',
          grant: const FolderGrant(
            key: 'root',
            identity: 'root',
            name: 'Books',
            location: '/Users/reader/Documents/Books',
          ),
          lastScan: DateTime(2026, 10, 31, 9, 30),
        ),
        WatchedFolder(
          id: 'archive',
          grant: const FolderGrant(key: 'archive', identity: 'archive', name: 'Archive', location: '/Archive'),
          status: FolderStatus.accessNeeded,
        ),
      ]);
      await mount(tester, size: size, theme: AppTheme.dark);
      expect(find.byType(Card), findsNothing);
      expect(find.text('Reconnect'), findsOneWidget);
      expect(find.text('1'), findsNWidgets(2));
      expect(find.text('BOOKS'), size.width >= 840 ? findsOneWidget : findsNothing);
      expect(find.text('LIBRARY'), findsNothing);
      expect(find.text('DESTINATION SHELF'), size.width >= 840 ? findsOneWidget : findsNothing);
      expect(find.text('LAST CHECKED'), size.width >= 840 ? findsOneWidget : findsNothing);
      expect(find.text('FOLDER'), size.width >= 840 ? findsOneWidget : findsNothing);
      expect(find.text('2 connected folders'), findsNothing);

      if (size.width >= 840) {
        expect(tester.getTopLeft(find.text('Reading inbox')).dx, tester.getTopLeft(find.text('Archive')).dx);
        expect(tester.getTopLeft(find.text('1').first).dx, tester.getTopLeft(find.text('1').last).dx);
      }

      if (size.width < 840) {
        final status = tester.getTopLeft(find.text('Status').first);
        final books = tester.getTopLeft(find.text('Books').first);
        final shelf = tester.getTopLeft(find.text('Destination shelf').first);
        final checked = tester.getTopLeft(find.text('Last checked').first);
        expect(status.dy, books.dy);
        expect(shelf.dy, checked.dy);

        if (size.width < 600) {
          expect(status.dx, shelf.dx);
          expect(books.dx, checked.dx);
          expect(shelf.dy, greaterThan(status.dy));
        } else {
          expect(status.dy, shelf.dy);
        }
      }

      await _captureReview(tester, 'folders-${size.width.toInt()}');
      await tester.tap(find.text('Reading inbox'));
      await tester.pumpAndSettle();
      await _captureReview(tester, 'details-${size.width.toInt()}');
      expect(find.text('Stop watching'), findsNothing);
      expect(find.text('Connection'), findsNothing);
      expect(
        find.descendant(of: find.byType(FolderDetailsSheet), matching: find.text('Destination shelf')),
        findsOneWidget,
      );
      expect(find.text('Close').hitTestable(), findsOneWidget);
      expect(tester.getSize(find.byType(FolderDetailsSheet)).height, lessThan(size.height * .85));
      final viewBooks = find.descendant(of: find.byType(FolderDetailsSheet), matching: find.text('View 1 book'));
      await tester.ensureVisible(viewBooks);
      await tester.pumpAndSettle();
      await tester.tap(viewBooks);
      await tester.pumpAndSettle();
      expect(find.byType(InputChip), findsNothing);
      await tester.tap(find.byTooltip('Advanced filters, 1 active'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Source folders'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Source folders'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Source folders'));
      await tester.pumpAndSettle();
      await _captureReview(tester, 'filters-${size.width.toInt()}');
      expect(tester.takeException(), isNull);
    });
  }

  for (final (size, scale, theme) in [
    (const Size(390, 844), 1.0, AppTheme.dark),
    (const Size(1200, 800), 1.0, AppTheme.dark),
    (const Size(320, 700), 2.0, AppTheme.eink),
  ]) {
    testWidgets('connect sheet groups source settings and preview at $size', (tester) async {
      final access = folders.access as MemoryAccess;
      final browser = size.width == 390;

      if (browser) {
        access.selected = const FolderGrant(key: 'root', identity: 'root', name: 'Books', location: 'Books');
      }

      access.put('sample.epub', [1, 2, 3]);
      await mount(tester, size: size, theme: theme, textScale: scale);
      await tester.ensureVisible(find.text('Connect folder'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Connect folder'));
      await tester.pumpAndSettle();
      expect(find.text(browser ? 'Selected folder' : 'Folder path'), findsOneWidget);
      expect(find.widgetWithText(SelectableText, browser ? 'Books' : '/Books'), findsOneWidget);
      expect(find.text('Name'), findsOneWidget);
      expect(find.text('Books found'), findsOneWidget);
      expect(find.text('Total size'), findsOneWidget);
      expect(find.text('Import and watch').hitTestable(), findsOneWidget);
      await _captureReview(tester, 'connect-${size.width.toInt()}');
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(folders.items, isEmpty);
    });
  }

  testWidgets('browser folders show the name once in rows and details without a path substitute', (tester) async {
    final folder = WatchedFolder(
      id: 'folder',
      grant: const FolderGrant(key: 'root', identity: 'root', name: 'Books', location: 'Books'),
    );
    folders.items.add(folder);
    await mount(tester);
    expect(find.descendant(of: find.byType(FolderIdentity), matching: find.text('Books')), findsOneWidget);
    await tester.tap(find.descendant(of: find.byType(FolderIdentity), matching: find.text('Books')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(FolderDetailsSheet),
        matching: find.descendant(of: find.byType(FolderIdentity), matching: find.text('Books')),
      ),
      findsOneWidget,
    );
    await _captureReview(tester, 'details-browser');
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    await folders.update(folder, name: 'Reading inbox');
    await tester.pumpAndSettle();
    expect(find.text('Reading inbox'), findsOneWidget);
    expect(find.descendant(of: find.byType(FolderIdentity), matching: find.text('Books')), findsNothing);
  });

  for (final size in [const Size(390, 844), const Size(1024, 800)]) {
    testWidgets('progress reserves row and sheet space and displays remaining books at $size', (tester) async {
      final folder = WatchedFolder(id: 'folder', grant: grant);
      folders.items.addAll([
        folder,
        WatchedFolder(
          id: 'second',
          grant: const FolderGrant(key: 'second', identity: 'second', name: 'Archive', location: '/Archive'),
        ),
      ]);
      await mount(tester, size: size, theme: AppTheme.dark);
      final nextRow = find.byKey(const ValueKey('second'));
      final position = tester.getTopLeft(nextRow);
      folder.status = FolderStatus.scanning;
      folders.notifyListeners();
      await tester.pump();
      expect(tester.getTopLeft(nextRow), position);
      expect(tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).value, isNull);
      folder.status = FolderStatus.importing;
      folder.progress = FolderImportProgress(total: 10000)..processed = 2500;
      folders.notifyListeners();
      await tester.pump();
      expect(tester.getTopLeft(nextRow), position);
      expect(find.text('2500/10000\n7500 left'), findsOneWidget);
      expect(tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).value, .25);
      await _captureReview(tester, 'import-progress-${size.width.toInt()}');
      folder.status = FolderStatus.upToDate;
      folder.progress = null;
      folders.notifyListeners();
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(nextRow), position);
      await tester.tap(find.descendant(of: find.byType(FolderIdentity), matching: find.text('Books')));
      await tester.pumpAndSettle();
      final details = find.byType(FolderDetailsSheet);
      final sheetBounds = tester.getRect(details);
      final viewBooks = find.descendant(of: details, matching: find.text('View 1 book'));
      final buttonPosition = tester.getTopLeft(viewBooks);
      folder.status = FolderStatus.importing;
      folder.progress = FolderImportProgress(total: 9)..processed = 3;
      folders.notifyListeners();
      await tester.pump();
      expect(tester.getRect(details), sheetBounds);
      expect(tester.getTopLeft(viewBooks), buttonPosition);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.descendant(of: details, matching: find.byType(LinearProgressIndicator)),
            )
            .value,
        closeTo(1 / 3, .001),
      );
      await _captureReview(tester, 'import-details-${size.width.toInt()}');
      expect(tester.takeException(), isNull);
    });
  }

  for (final (size, scale) in [
    (const Size(320, 900), 2.0),
    (const Size(390, 844), 1.0),
    (const Size(820, 900), 1.0),
    (const Size(1200, 900), 1.3),
  ]) {
    testWidgets('folder row height stays stable across all statuses at $size and scale $scale', (tester) async {
      final folder = WatchedFolder(id: 'folder', grant: grant, status: FolderStatus.paused);
      folders.items.add(folder);
      await mount(tester, size: size, textScale: scale, theme: AppTheme.dark);
      final row = find.byKey(const ValueKey('folder'));
      final bounds = tester.getRect(row);

      for (final status in FolderStatus.values) {
        for (final shelfMissing in [false, true]) {
          folder.status = status;
          folder.shelfId = shelfMissing ? 'deleted-shelf' : null;
          folder.lastScan = DateTime(2026, 11, 1, 23, 59);
          folder.progress = status == FolderStatus.importing
              ? (FolderImportProgress(total: 10000)..processed = 2500)
              : null;
          folders.notifyListeners();
          await tester.pump();
          expect(tester.getRect(row), bounds, reason: '$status, missing shelf: $shelfMissing');
          expect(tester.takeException(), isNull);
        }
      }

      folder.status = FolderStatus.paused;
      folder.shelfId = null;
      folder.lastScan = null;
      folder.progress = null;
      folders.notifyListeners();
      await tester.pumpAndSettle();
      expect(tester.getRect(row), bounds);
    });
  }

  testWidgets('folder rows open details from keyboard focus', (tester) async {
    folders.items.add(WatchedFolder(id: 'folder', grant: grant));
    await mount(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(FolderDetailsSheet), findsOneWidget);
    expect(find.text('Connection'), findsNothing);
  });

  testWidgets('folder action errors are inline and disappear when switching profiles', (tester) async {
    folders.items.add(WatchedFolder(id: 'folder', grant: grant, enabled: false, status: FolderStatus.paused));
    folders.updateFailure = StateError('Could not resume folder');
    await mount(tester);
    await tester.tap(find.text('Resume'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not resume folder'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    folders.switchProfile();
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not resume folder'), findsNothing);
  });

  testWidgets('contextual resume updates the row and scanning is available in details', (tester) async {
    final folder = WatchedFolder(id: 'folder', grant: grant, enabled: false, status: FolderStatus.paused);
    folders.items.add(folder);
    await mount(tester);
    await tester.tap(find.text('Resume'));
    await tester.pumpAndSettle();
    expect(folder.enabled, isTrue);
    expect(folders.edits, 1);
    expect(find.byType(FolderDetailsSheet), findsNothing);
    expect(find.text('Up to date'), findsOneWidget);
    expect(find.text('Details'), findsNothing);
    await tester.tap(find.descendant(of: find.byType(FolderIdentity), matching: find.text('Books')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan now'));
    await tester.pumpAndSettle();
    expect(folders.scans, 1);
    expect(find.byType(FolderDetailsSheet), findsOneWidget);
    expect(find.text('Close').hitTestable(), findsOneWidget);
  });

  testWidgets('scan keeps details open, shows errors, and allows closing while work continues', (tester) async {
    folders.items.add(WatchedFolder(id: 'folder', grant: grant));
    folders.scanPending = Completer<void>();
    await mount(tester);
    await tester.tap(find.descendant(of: find.byType(FolderIdentity), matching: find.text('Books')));
    await tester.pumpAndSettle();
    final detailsState = tester.state(find.byType(FolderDetailsSheet));
    await tester.tap(find.text('Scan now'));
    await tester.pump();
    expect(tester.state(find.byType(FolderDetailsSheet)), same(detailsState));
    expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Scan now')).onPressed, isNull);
    expect(find.text('Close').hitTestable(), findsOneWidget);
    folders.scanPending!.complete();
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(FolderDetailsSheet)), same(detailsState));
    folders.scanFailure = StateError('Scan failed');
    await tester.tap(find.text('Scan now'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Scan failed'), findsOneWidget);
    expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Scan now')).onPressed, isNotNull);
    folders.scanFailure = null;
    folders.scanPending = Completer<void>();
    await tester.tap(find.text('Scan now'));
    await tester.pump();
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(FolderDetailsSheet), findsNothing);
    folders.scanPending!.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('management has no draft and editing is explicit and cancelable', (tester) async {
    final folder = WatchedFolder(id: 'folder', grant: grant);
    folders.items.add(folder);
    await mount(tester);
    await tester.tap(find.descendant(of: find.byType(FolderIdentity), matching: find.text('Books')));
    await tester.pumpAndSettle();
    final detailsState = tester.state(find.byType(FolderDetailsSheet));
    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(SwitchListTile), findsNothing);
    expect(find.text('Save changes'), findsNothing);
    await tester.tap(find.byTooltip('Books options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pause watching'));
    await tester.pumpAndSettle();
    expect(folder.enabled, isFalse);
    expect(find.text('Paused'), findsNWidgets(2));
    await tester.tap(find.byTooltip('Books options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit folder'));
    await tester.pumpAndSettle();
    expect(find.byType(EditFolderSheet), findsOneWidget);
    expect(find.byType(FolderDetailsSheet), findsOneWidget);
    expect(find.text('Pause watching'), findsNothing);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save changes')).onPressed, isNull);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(folder.recursive, isTrue);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(folder.recursive, isTrue);
    expect(find.byType(FolderDetailsSheet), findsOneWidget);
    await tester.tap(find.byTooltip('Books options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit folder'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(folder.recursive, isFalse);
    expect(folder.enabled, isFalse);
    expect(find.text('1'), findsOneWidget);
    expect(find.byType(EditFolderSheet), findsNothing);
    expect(tester.state(find.byType(FolderDetailsSheet)), same(detailsState));
    expect(find.text('Excluded'), findsOneWidget);
  });

  testWidgets('renaming is cancelable and uses the saved name in rows and source filters', (tester) async {
    final folder = WatchedFolder(id: 'folder', grant: grant);
    folders.items.add(folder);
    await mount(tester);
    await tester.tap(find.descendant(of: find.byType(FolderIdentity), matching: find.text('Books')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Books options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit folder'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Draft');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(folder.name, 'Books');
    expect(find.byType(FolderDetailsSheet), findsOneWidget);
    await tester.tap(find.byTooltip('Books options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit folder'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '  Reading inbox  ');
    await tester.pumpAndSettle();
    await _captureReview(tester, 'edit-name');
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    final details = find.byType(FolderDetailsSheet);
    expect(details, findsOneWidget);
    expect(find.descendant(of: details, matching: find.text('Reading inbox')), findsOneWidget);
    expect(find.descendant(of: details, matching: find.text('/Books')), findsOneWidget);
    expect(folder.grant.identity, grant.identity);
    await tester.tap(find.text('View 1 book'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Advanced filters, 1 active'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Source folders'));
    await tester.tap(find.text('Source folders'));
    await tester.pumpAndSettle();
    expect(find.text('Reading inbox'), findsOneWidget);
    expect(library.filters.folderIds, {'folder'});
  });

  testWidgets('view books uses advanced source folder filters and reset restores the library', (tester) async {
    folders.items.add(WatchedFolder(id: 'folder', grant: grant));
    await mount(tester);
    await tester.tap(find.descendant(of: find.byType(FolderIdentity), matching: find.text('Books')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('View 1 book'));
    await tester.pumpAndSettle();
    expect(library.filters.folderIds, {'folder'});
    expect(library.activeFilterCount, 1);
    expect(find.byType(InputChip), findsNothing);
    expect(tester.widget<BookGrid>(find.byType(BookGrid)).books.map((book) => book.id), ['book-1']);
    await tester.tap(find.byTooltip('Advanced filters, 1 active'));
    await tester.pumpAndSettle();
    final facet = find.text('Source folders');
    await tester.ensureVisible(facet);
    await tester.pumpAndSettle();
    await tester.tap(facet);
    await tester.pumpAndSettle();
    expect(find.text('Books'), findsOneWidget);
    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show ${store.books.length} books'));
    await tester.pumpAndSettle();
    expect(library.filters.folderIds, isEmpty);
    expect(tester.widget<BookGrid>(find.byType(BookGrid)).books.length, store.books.length);
    expect(tester.takeException(), isNull);
  });

  testWidgets('source folder selection is a draft until applied and combines with other filters', (tester) async {
    folders.items.add(WatchedFolder(id: 'folder', grant: grant));
    await mount(tester);
    router.go('/library/books');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Advanced filters'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Source folders'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Source folders'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Books'));
    await tester.tap(find.text('Books'));
    await tester.pumpAndSettle();
    expect(library.filters.folderIds, isEmpty);
    expect(find.text('Show 1 book'), findsOneWidget);
    await tester.tap(find.text('Show 1 book'));
    await tester.pumpAndSettle();
    expect(library.filters.folderIds, {'folder'});
    library.applyFilters(library.filters.copyWith(authors: {'missing author'}));
    await tester.pumpAndSettle();
    expect(library.activeFilterCount, 2);
    expect(find.byType(BookGrid), findsNothing);
    library.clearFilters();
    await tester.pumpAndSettle();
    expect(tester.widget<BookGrid>(find.byType(BookGrid)).books.length, store.books.length);
  });

  testWidgets('details keep removal explanation in the confirmation only', (tester) async {
    folders.items.add(WatchedFolder(id: 'folder', grant: grant));
    await mount(tester);
    await tester.tap(find.text('Books'));
    await tester.pumpAndSettle();
    expect(find.text('Imported books stay in your library.'), findsNothing);
    expect(find.text('Stop watching…'), findsNothing);
    expect(find.text('/Books'), findsNWidgets(2));
    expect(find.text('Subfolders'), findsOneWidget);
    await tester.tap(find.byTooltip('Books options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stop watching'));
    await tester.pumpAndSettle();
    expect(find.text('Stop watching this folder?'), findsOneWidget);
    expect(
      find.text('Imported books stay in your library. Pending imports from this folder will stop.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(folders.items, hasLength(1));
  });

  testWidgets('profile changes invalidate open details', (tester) async {
    folders.items.add(WatchedFolder(id: 'folder', grant: grant));
    await mount(tester);
    await tester.tap(find.descendant(of: find.byType(FolderIdentity), matching: find.text('Books')));
    await tester.pumpAndSettle();
    folders.switchProfile();
    await tester.pumpAndSettle();
    expect(find.text('This folder is no longer available in the selected library.'), findsOneWidget);
    expect(find.text('Edit folder'), findsNothing);
    expect(find.text('Close').hitTestable(), findsOneWidget);
    expect(folders.edits, 0);
  });

  for (final (name, theme) in [('light', AppTheme.light), ('dark', AppTheme.dark), ('e-ink', AppTheme.eink)]) {
    testWidgets('large text retains reachable management and edit actions in $name', (tester) async {
      folders.items.add(WatchedFolder(id: 'folder', grant: grant, status: FolderStatus.accessNeeded));
      await mount(tester, size: const Size(320, 700), theme: theme, textScale: 2);
      expect(find.text('Reconnect'), findsOneWidget);
      expect(find.text('/Books'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.descendant(of: find.byType(FolderIdentity), matching: find.text('Books')));
      await tester.pumpAndSettle();
      expect(find.text('Close').hitTestable(), findsOneWidget);
      await _captureReview(tester, 'large-text-$name');
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: find.byType(FolderIdentity), matching: find.text('Books')));
      await tester.pumpAndSettle();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Books options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit folder'));
      await tester.pumpAndSettle();
      expect(find.text('Save changes').hitTestable(), findsOneWidget);
      expect(find.text('Cancel').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('profile changes invalidate a pending preference edit', (tester) async {
    final folder = WatchedFolder(id: 'folder', grant: grant);
    folders.items.add(folder);
    await mount(tester);
    await tester.tap(find.descendant(of: find.byType(FolderIdentity), matching: find.text('Books')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Books options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit folder'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    folders.switchProfile();
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(EditFolderSheet),
        matching: find.text('This folder is no longer available in the selected library.'),
      ),
      findsOneWidget,
    );
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save changes')).onPressed, isNull);
    expect(folder.recursive, isTrue);
    expect(folders.edits, 0);
  });
}
