import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/data/data_store.dart';
import 'package:papyrus/folders/directory_access.dart';
import 'package:papyrus/folders/folder_models.dart';
import 'package:papyrus/folders/watched_folders.dart';
import 'package:papyrus/providers/auth_provider.dart';
import 'package:papyrus/themes/app_theme.dart';
import 'package:papyrus/widgets/add_book/add_book_choice_sheet.dart';
import 'package:papyrus/widgets/add_book/connect_folder_sheet.dart';
import 'package:provider/provider.dart';

import 'watched_folders_test.dart' show MemoryAccess, grant;

class _Access extends MemoryAccess {
  int picks = 0;
  int releases = 0;
  Object? pickFailure;

  @override
  Future<FolderGrant?> pick() async {
    picks++;

    if (pickFailure != null) {
      throw pickFailure!;
    }

    return grant;
  }

  @override
  Future<void> release(FolderGrant grant) async {
    releases++;
  }
}

class _Folders extends WatchedFolders {
  _Folders(DirectoryAccess access)
    : super(access: access, captureTarget: () => throw UnimplementedError(), libraryReady: () => true);
  int connections = 0;
  String? connectedName;
  Future<FolderPreview> Function(bool recursive)? previewResult;

  @override
  Future<FolderPreview> preview(FolderGrant grant, bool recursive, {bool Function()? cancelled}) =>
      previewResult?.call(recursive) ?? super.preview(grant, recursive, cancelled: cancelled);

  @override
  bool get ready => true;

  @override
  String get scope => 'guest';

  @override
  Future<void> connect(FolderGrant grant, {String? name, bool recursive = true, String? shelfId}) async {
    connections++;
    connectedName = name;
  }
}

class _Auth extends ChangeNotifier implements AuthProvider {
  @override
  bool get isOfflineMode => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final size in [const Size(390, 844), const Size(1280, 900)]) {
    testWidgets('connect folder opens picker directly and stays in Library at $size', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.reset);
      final access = _Access()..put('sample.epub', [1, 2, 3]);
      final folders = _Folders(access);
      final store = DataStore();
      final auth = _Auth();
      addTearDown(folders.dispose);
      addTearDown(store.dispose);
      addTearDown(auth.dispose);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<WatchedFolders>.value(value: folders),
            ChangeNotifierProvider<DataStore>.value(value: store),
            ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: Builder(
              builder: (context) => Scaffold(
                appBar: AppBar(title: const Text('Library')),
                body: FilledButton(onPressed: () => AddBookChoiceSheet.show(context), child: const Text('Add book')),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Add book'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Connect folder'));
      expect(access.picks, 1, reason: 'The original tap invokes the picker without a navigation or another tap.');
      await tester.pumpAndSettle();
      expect(find.byType(ConnectFolderSheet), findsOneWidget);
      expect(find.text('Books found'), findsOneWidget);
      expect(find.text('Total size'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('Folder path'), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Cancel'), findsOneWidget);
      expect(find.text('Library'), findsOneWidget);
      expect(find.text('Watched folders'), findsNothing);
      expect(folders.connections, 0, reason: 'Preview does not create a connection.');
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'Books');
      expect(find.text('/Books'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '   ');
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Import and watch')).onPressed, isNull);
      await tester.enterText(find.byType(TextField), 'Reading inbox');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Import and watch'));
      await tester.pumpAndSettle();
      expect(folders.connections, 1);
      expect(find.byType(SnackBar), findsNothing);
      expect(folders.connectedName, 'Reading inbox');
      expect(find.byType(ConnectFolderSheet), findsNothing);
      expect(find.text('Library'), findsOneWidget);
      expect(access.releases, 0);
    });
  }

  for (final size in [const Size(390, 844), const Size(1280, 900)]) {
    testWidgets('changing recursion retains preview geometry and ignores stale scans at $size', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.reset);
      final folders = _Folders(_Access());
      final store = DataStore();
      addTearDown(folders.dispose);
      addTearDown(store.dispose);
      final scans = <Completer<FolderPreview>>[];
      folders.previewResult = (_) async => FolderPreview()..unsupported = 16;
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<WatchedFolders>.value(value: folders),
            ChangeNotifierProvider<DataStore>.value(value: store),
          ],
          child: MaterialApp(
            theme: AppTheme.dark,
            home: Builder(
              builder: (context) => Scaffold(
                body: FilledButton(onPressed: () => connectBookFolder(context), child: const Text('Connect')),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();
      final sheet = find.byType(ConnectFolderSheet);
      final toggle = find.byType(SwitchListTile);
      final name = find.byType(TextField);
      final import = find.widgetWithText(FilledButton, 'Import and watch');
      final sheetBounds = tester.getRect(sheet);
      final nameBounds = tester.getRect(name);
      final toggleBounds = tester.getRect(toggle);
      folders.previewResult = (_) {
        final scan = Completer<FolderPreview>();
        scans.add(scan);
        return scan.future;
      };

      for (var index = 0; index < 2; index++) {
        await tester.tap(toggle);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.getRect(sheet), sheetBounds);
        expect(tester.getRect(name), nameBounds);
        expect(tester.getRect(toggle), toggleBounds);
        expect(find.text('16 files cannot be imported'), findsOneWidget);
        expect(find.text('—'), findsNothing);
        expect(tester.widget<FilledButton>(import).onPressed, isNotNull);
        expect(find.byType(LinearProgressIndicator), findsNothing);
      }

      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.widget<FilledButton>(import).onPressed, isNull);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      scans.first.complete(FolderPreview()..supported = 999);
      await tester.pump();
      expect(find.text('999'), findsNothing);
      expect(tester.widget<FilledButton>(import).onPressed, isNull);
      scans.last.complete(
        FolderPreview()
          ..unsupported = 16
          ..supported = 2,
      );
      await tester.pumpAndSettle();
      expect(find.text('2'), findsOneWidget);
      expect(tester.widget<FilledButton>(import).onPressed, isNotNull);
      expect(tester.getRect(sheet), sheetBounds);
      expect(tester.getRect(name), nameBounds);
      expect(tester.getRect(toggle), toggleBounds);
      expect(tester.takeException(), isNull);

      await tester.tap(toggle);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      scans.last.complete(FolderPreview()..supported = 2);
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(tester.widget<FilledButton>(import).onPressed, isNotNull);

      await tester.tap(toggle);
      await tester.pump();
      await tester.tap(import);
      await tester.pump();
      expect(folders.connections, 0, reason: 'Import waits for the latest preview.');
      scans.last.completeError(const FolderAccessException('access', 'Folder access denied'));
      await tester.pumpAndSettle();
      expect(folders.connections, 0);
      expect(find.text('Folder access denied'), findsOneWidget);
      expect(tester.widget<FilledButton>(import).onPressed, isNull);

      await tester.tap(toggle);
      await tester.pump();
      await tester.tap(import);
      await tester.pump();
      expect(folders.connections, 0);
      scans.last.complete(FolderPreview()..supported = 3);
      await tester.pumpAndSettle();
      expect(folders.connections, 1);
      expect(find.byType(ConnectFolderSheet), findsNothing);
    });
  }

  testWidgets('picker errors stay in a sheet without a snackbar', (tester) async {
    final access = _Access()..pickFailure = const FolderAccessException('access', 'Folder access denied');
    final folders = _Folders(access);
    addTearDown(folders.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<WatchedFolders>.value(
        value: folders,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: FilledButton(onPressed: () => connectBookFolder(context), child: const Text('Connect')),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    expect(find.text('Could not connect folder'), findsOneWidget);
    expect(find.text('Folder access denied'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(folders.connections, 0);
  });

  testWidgets('canceling the preview releases access and creates no connection', (tester) async {
    final access = _Access();
    final folders = _Folders(access);
    final store = DataStore();
    final auth = _Auth();
    addTearDown(folders.dispose);
    addTearDown(store.dispose);
    addTearDown(auth.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<WatchedFolders>.value(value: folders),
          ChangeNotifierProvider<DataStore>.value(value: store),
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: FilledButton(onPressed: () => connectBookFolder(context), child: const Text('Connect')),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(folders.connections, 0);
    expect(access.releases, 1);
  });
}
