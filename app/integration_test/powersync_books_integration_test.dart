import '../test/support/disposable_sync_accounts.dart';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:papyrus/auth/auth_api_client.dart';
import 'package:papyrus/auth/auth_repository.dart';
import 'package:papyrus/auth/papyrus_api_config.dart';
import 'package:papyrus/auth/token_store.dart';
import 'package:papyrus/data/data_store.dart';
import 'package:papyrus/folders/directory_access.dart';
import 'package:papyrus/folders/folder_import_target.dart';
import 'package:papyrus/folders/folder_repository.dart';
import 'package:papyrus/folders/watched_folders.dart';
import 'package:papyrus/media/media_storage_scope.dart';
import 'package:papyrus/media/media_upload_queue.dart';
import 'package:papyrus/models/book.dart';
import 'package:papyrus/powersync/papyrus_powersync_connector.dart';
import 'package:papyrus/powersync/powersync_service.dart';
import 'package:papyrus/providers/auth_provider.dart';
import 'package:papyrus/services/book_import_service_stub.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'desktop_package_fixtures.dart' show createEpub;

const runIntegration = bool.fromEnvironment('RUN_POWERSYNC_INTEGRATION');

/// Keeps OS grant acceptance separate from the live import and sync contract.
class IntegrationFolderAccess implements DirectoryAccess {
  IntegrationFolderAccess(this.bytes);
  final Uint8List bytes;
  static const grant = FolderGrant(key: 'fixture', identity: 'fixture', name: 'Fixture', location: 'Test books');
  FolderFile get file => FolderFile(key: 'book.epub', name: 'book.epub', size: bytes.length, modified: 1);
  @override
  bool get supportsWatching => true;
  @override
  Future<FolderGrant?> pick() async => grant;
  @override
  Future<bool> reconnect(FolderGrant grant) async => true;
  @override
  Stream<FolderFile> enumerate(FolderGrant grant, {required bool recursive}) => Stream.value(file);
  @override
  Future<FolderFile> stat(FolderGrant grant, FolderFile file) async => this.file;
  @override
  Future<Uint8List> read(FolderGrant grant, FolderFile file) async => bytes;
  @override
  Stream<void> changes(FolderGrant grant) => const Stream.empty();
  @override
  Future<void> release(FolderGrant grant) async {}
}

Future<void> verifyFolderImport(
  PapyrusPowerSyncService first,
  PapyrusPowerSyncService second,
  AuthRepository repository,
  Directory root,
) async {
  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();
  final auth = AuthProvider(preferences, repository: repository, bootstrapOnCreate: false);
  await auth.bootstrap();
  final queue = MediaUploadQueue(preferences);
  await queue.activateScope(MediaStorageScope(profileKey: 'official', userId: auth.user!.userId));
  final store = DataStore();
  await store.attachBookRepository(first);
  final importer = BookImportService();
  final source = File(path.join(root.path, 'source.epub'));
  final original = createEpub();
  await source.writeAsBytes(original);
  final access = IntegrationFolderAccess(original);
  final folders = WatchedFolders(
    access: access,
    libraryReady: () => true,
    captureTarget: () => LibraryFolderImportTarget(
      store: store,
      queue: queue,
      importer: importer,
      auth: auth,
      database: first,
    ),
    openRepository: (_) => FolderRepository.open('integration', databasePath: path.join(root.path, 'folders.db')),
  );
  String? importedId;

  try {
    await first.setOnline(false);
    await folders.activate('integration');
    await folders.connect(IntegrationFolderAccess.grant);
    await folders.waitUntilIdle();
    expect(folders.folders.single.added, 1);
    final imported = store.books.singleWhere((book) => book.fileHash != null);
    importedId = imported.id;
    expect(await importer.getBookFile(imported.id), original);
    expect(queue.pendingTasks.where((task) => task.bookId == imported.id), isNotEmpty);
    expect(await second.getById(imported.id), isNull);
    await folders.activate(null);
    await folders.activate('integration');
    await folders.waitUntilIdle();
    expect(store.books.where((book) => book.fileHash == imported.fileHash), hasLength(1));
    await first.setOnline(true);
    await waitForBook(second, imported.id);
    await queue.processPending(
      dataStore: store,
      readBookFile: importer.getBookFile,
      readPendingCover: importer.getPendingCoverFile,
      uploadMedia: repository.uploadMedia,
    );
    expect(queue.pendingTasks, isEmpty);
    final deadline = DateTime.now().add(const Duration(seconds: 20));

    while ((await second.getById(imported.id))?.fileMediaId == null && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }

    expect((await second.getById(imported.id))?.fileMediaId, isNotNull);
    expect(await source.readAsBytes(), original);
  } finally {
    await folders.activate(null);
    folders.dispose();

    if (importedId != null) {
      await first.delete(importedId);
      await importer.deleteBookFile(importedId);
      await importer.deletePendingCoverFile(queue.activeScope!, importedId);
    }

    await store.disposeBookRepository();
    store.dispose();
    queue.dispose();
    auth.dispose();
    importer.dispose();
  }
}

class MemoryRefreshTokenStorage implements RefreshTokenStorage {
  String? value;

  @override
  Future<void> delete() async => value = null;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String refreshToken) async => value = refreshToken;
}

Future<void> waitForBook(PapyrusPowerSyncService service, String id, {bool present = true, String? title}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 20));

  while (DateTime.now().isBefore(deadline)) {
    final book = await service.getById(id);

    if ((book != null) == present && (title == null || book?.title == title)) {
      return;
    }

    await Future<void>.delayed(const Duration(milliseconds: 200));
  }

  fail('Book $id did not reach expected presence=$present');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('two clients sync books, reconnect offline writes, and isolate users', (tester) async {
    final config = PapyrusApiConfig.fromEnvironment();
    requireDisposableSyncAccounts();
    const email = syncOwnerEmail;
    const password = syncPassword;
    final root = await Directory.systemTemp.createTemp('papyrus-e2e-');

    AuthRepository repository(String label) {
      return AuthRepository(
        apiClient: AuthApiClient(config: config),
        tokenStore: TokenStore(MemoryRefreshTokenStorage()),
      );
    }

    PapyrusPowerSyncService service(AuthRepository repository, String label) {
      return PapyrusPowerSyncService(
        connectorFactory: () => PapyrusPowerSyncConnector(authRepository: repository, config: config),
        pathResolver: (mode, profileKey, userId) async =>
            path.join(root.path, '$label-${mode.name}-${profileKey ?? 'default'}-${userId ?? 'none'}.db'),
      );
    }

    final firstAuth = repository('first');

    final firstTokens = await firstAuth.login(
      email: email,
      password: password,
      clientType: 'desktop',
    );

    final secondAuth = repository('second');
    await secondAuth.login(email: email, password: password, clientType: 'desktop');
    final otherAuth = repository('other');

    final otherTokens = await otherAuth.login(
      email: syncOtherEmail,
      password: password,
      clientType: 'desktop',
    );

    final first = service(firstAuth, 'first');
    final second = service(secondAuth, 'second');
    final other = service(otherAuth, 'other');

    try {
      await Future.wait([
        first.activateAuthenticated(firstTokens.user.userId),
        second.activateAuthenticated(firstTokens.user.userId),
        other.activateAuthenticated(otherTokens.user.userId),
      ]);

      await Future.wait([
        first.syncStates.firstWhere((state) => state.connected),
        second.syncStates.firstWhere((state) => state.connected),
        other.syncStates.firstWhere((state) => state.connected),
      ]).timeout(const Duration(seconds: 20));

      final book = Book(
        id: const Uuid().v4(),
        title: 'Realtime book',
        author: 'Papyrus',
        addedAt: DateTime.now().toUtc(),
      );

      await first.upsert(book);
      await waitForBook(second, book.id, title: book.title);
      expect(await other.getById(book.id), isNull);
      await first.setOnline(false);
      await first.upsert(book.copyWith(title: 'Offline edit'));
      await first.setOnline(true);
      await waitForBook(second, book.id, title: 'Offline edit');
      expect((await second.getById(book.id))?.title, 'Offline edit');
      await verifyFolderImport(first, second, firstAuth, root);
      await second.delete(book.id);
      await waitForBook(first, book.id, present: false);
    } finally {
      await Future.wait([first.close(), second.close(), other.close()]);
      await root.delete(recursive: true);
      await firstAuth.deleteAccount();
      await otherAuth.deleteAccount();
    }
  }, skip: !runIntegration);
}
