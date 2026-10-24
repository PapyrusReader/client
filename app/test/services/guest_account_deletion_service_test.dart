import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/data/data_store.dart';
import 'package:papyrus/media/media_storage_scope.dart';
import 'package:papyrus/models/book.dart';
import 'package:papyrus/models/bookmark.dart';
import 'package:papyrus/opds/opds_catalog_store.dart';
import 'package:papyrus/opds/opds_catalogs.dart';
import 'package:papyrus/opds/opds_downloads.dart';
import 'package:papyrus/opds/opds_http_client.dart';
import 'package:papyrus/opds/opds_library.dart';
import 'package:papyrus/opds/opds_models.dart';
import 'package:papyrus/opds/opds_resource_cache.dart';
import 'package:papyrus/powersync/powersync_service.dart';
import 'package:papyrus/powersync/sync_state.dart';
import 'package:papyrus/providers/auth_provider.dart';
import 'package:papyrus/services/book_import_service_stub.dart';
import 'package:papyrus/services/guest_account_deletion_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../opds/catalog_store_test.dart' show MemorySecrets;
import '../powersync/powersync_service_test.dart' show OfflineConnector;
import '../providers/auth_provider_test.dart' show FakeAuthRepository;

class _Paths extends Fake with MockPlatformInterfaceMixin implements PathProviderPlatform {
  _Paths(this.directory);
  final Directory directory;

  @override
  Future<String?> getApplicationDocumentsPath() async => directory.path;

  @override
  Future<String?> getApplicationSupportPath() async => directory.path;
}

class _Files extends BookImportService {
  bool failDeletion = false;

  @override
  Future<void> deleteBookFile(String bookId) async {
    if (failDeletion) {
      throw const FileSystemException('Storage unavailable');
    }

    await super.deleteBookFile(bookId);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late SharedPreferences prefs;
  late AuthProvider auth;
  late PapyrusPowerSyncService database;
  late _Files files;
  late OpdsCatalogs catalogs;
  late OpdsCatalogStore catalogStore;
  late MemorySecrets secrets;
  late OpdsResourceCache cache;
  late GuestAccountDeletionService deletion;
  const guest = MediaStorageScope.localGuest;
  final account = MediaStorageScope(profileKey: 'official', userId: 'reader');
  final catalog = OpdsCatalog(id: 'catalog', name: 'Books', uri: Uri.parse('https://catalog.test/feed'));
  final bytes = Uint8List.fromList([1, 2, 3]);

  PapyrusPowerSyncService createDatabase() => PapyrusPowerSyncService(
    connectorFactory: OfflineConnector.new,
    connectAuthenticated: false,
    pathResolver: (mode, profile, user) async =>
        '${directory.path}/${mode == LibraryDatabaseMode.guest ? 'guest' : '$profile-$user'}.db',
  );

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('papyrus-guest-delete-');
    final originalPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(directory);
    addTearDown(() => PathProviderPlatform.instance = originalPaths);
    SharedPreferences.setMockInitialValues({'offline_mode': true, 'bold_interface_text': true});
    prefs = await SharedPreferences.getInstance();
    auth = AuthProvider(prefs, repository: FakeAuthRepository(), bootstrapOnCreate: false);
    await auth.bootstrap();
    database = createDatabase();
    final store = DataStore(bookRepository: database);
    secrets = MemorySecrets();
    catalogStore = OpdsCatalogStore(prefs, secrets: secrets);
    cache = OpdsResourceCache(prefs);
    final provenance = OpdsLibrary(prefs, dataStore: store);
    catalogs = OpdsCatalogs(catalogStore, library: provenance, cache: cache)..setScope(guest.persistenceKey);
    final downloads = OpdsDownloads(captureImport: () => throw StateError('No import expected'), library: provenance);
    files = _Files();
    deletion = GuestAccountDeletionService(
      auth: auth,
      library: database,
      files: files,
      catalogs: catalogs,
      downloads: downloads,
    );

    await database.activateAuthenticated('reader');
    await database.upsert(Book(id: 'account', title: 'Account book', author: 'Reader', addedAt: DateTime.now()));
    await database.activateGuest();
    await database.upsert(Book(id: 'guest', title: 'Guest book', author: 'Reader', addedAt: DateTime.now()));
    await database.bookmarks.upsert(Bookmark(id: 'bookmark', bookId: 'guest', position: .5, createdAt: DateTime.now()));
    await Directory('${directory.path}/books').create();
    await File('${directory.path}/books/guest.epub').writeAsBytes(bytes);
    await File('${directory.path}/books/account.epub').writeAsBytes(bytes);
    await files.storeGuestCoverFile('guest', bytes);
    await files.storeCoverFile(account, 'cover', bytes);

    for (final scope in [guest.persistenceKey, account.persistenceKey]) {
      await catalogStore.save(
        scope,
        catalog,
        credentials: const OpdsCredentials(username: 'user', password: 'secret'),
      );
      cache.setScope(scope);
      await cache.write(
        cache.capture(catalog, catalog.uri)!,
        OpdsResponse(uri: catalog.uri, headers: const {}, bytes: bytes),
      );
    }

    cache.setScope(guest.persistenceKey);
    catalogs.reload();
    await prefs.setString('papyrus.opds.imports.v1.${guest.persistenceKey}', '{}');

    addTearDown(() async {
      downloads.dispose();
      catalogs.dispose();
      provenance.dispose();
      cache.dispose();
      store.dispose();
      auth.dispose();
      await database.close();
      await directory.delete(recursive: true);
    });
  });

  test('deletes persistent guest data and files while preserving other accounts', () async {
    final staleToken = cache.capture(catalog, catalog.uri)!;
    await deletion.delete();
    expect(auth.isOfflineMode, isFalse);
    expect(prefs.getBool('offline_mode'), isFalse);
    expect(await files.getBookFile('guest'), isNull);
    expect(await files.getGuestCoverFile('guest'), isNull);
    expect(await files.getBookFile('account'), bytes);
    expect(await files.getCoverFile(account, 'cover'), bytes);
    expect(catalogStore.load(guest.persistenceKey), isEmpty);
    expect(await catalogStore.credentials(guest.persistenceKey, catalog.id), isNull);
    expect(await catalogStore.credentials(account.persistenceKey, catalog.id), isNotNull);
    expect(prefs.containsKey('papyrus.opds.imports.v1.${guest.persistenceKey}'), isFalse);
    expect(cache.isCurrent(staleToken), isFalse);
    cache.setScope(account.persistenceKey);
    expect(cache.read(cache.capture(catalog, catalog.uri)!), isNotNull);
    final restoredCache = OpdsResourceCache(prefs)..setScope(guest.persistenceKey);
    expect(restoredCache.read(restoredCache.capture(catalog, catalog.uri)!), isNull);
    restoredCache.setScope(account.persistenceKey);
    expect(restoredCache.read(restoredCache.capture(catalog, catalog.uri)!), isNotNull);
    restoredCache.dispose();
    expect(prefs.getBool('bold_interface_text'), isTrue);
    await database.close();
    database = createDatabase();
    await database.activateGuest();
    expect(await database.getById('guest'), isNull);
    expect(await database.bookmarks.getById('bookmark'), isNull);
    await database.activateAuthenticated('reader');
    expect(await database.getById('account'), isNotNull);
  });

  test('failed cleanup keeps guest mode and records available for retry', () async {
    files.failDeletion = true;
    await expectLater(deletion.delete(), throwsA(isA<FileSystemException>()));
    expect(auth.isOfflineMode, isTrue);
    expect(auth.isDeletingGuestAccount, isFalse);
    expect(await database.getById('guest'), isNotNull);
    expect(await files.getBookFile('guest'), bytes);
    files.failDeletion = false;
    await deletion.delete();
    expect(auth.isOfflineMode, isFalse);
    expect(await database.getById('guest'), isNull);
  });

  test('rejects deleting an authenticated library even if guest auth state is stale', () async {
    await database.activateAuthenticated('reader');
    await expectLater(deletion.delete(), throwsStateError);
    expect(await database.getById('account'), isNotNull);
    expect(await files.getBookFile('account'), bytes);
    expect(auth.isOfflineMode, isTrue);
  });
}
