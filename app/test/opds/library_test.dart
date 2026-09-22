import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:papyrus/data/data_store.dart';
import 'package:papyrus/models/book.dart';
import 'package:papyrus/opds/opds_catalog_store.dart';
import 'package:papyrus/opds/opds_catalogs.dart';
import 'package:papyrus/opds/opds_downloads.dart';
import 'package:papyrus/opds/opds_http_client.dart';
import 'package:papyrus/opds/opds_library.dart';
import 'package:papyrus/opds/opds_models.dart';
import 'package:papyrus/services/book_import_result.dart';
import 'package:papyrus/services/book_import_session.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'catalog_store_test.dart' show MemorySecrets;
import 'relay_fixture_client.dart';

final _catalog = OpdsCatalog(id: 'one', name: 'Books', uri: Uri.parse('https://books.test/feed'));
final _epub = OpdsLink(
  uri: Uri.parse('https://books.test/book.epub'),
  type: 'application/epub+zip',
  rels: ['download'],
);
final _pdf = OpdsLink(uri: Uri.parse('https://books.test/book.pdf'), type: 'application/pdf', rels: ['download']);
final _publication = OpdsPublication(id: 'publication', title: 'Book', links: [_epub, _pdf]);
final _book = Book(id: 'local-book', title: 'Book', author: 'Author', addedAt: DateTime(2026));

void main() {
  late SharedPreferences prefs;
  late DataStore store;
  late OpdsLibrary library;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    store = DataStore();
    await store.waitUntilLoaded();
    library = OpdsLibrary(prefs, dataStore: store)..setScope('guest');
  });
  tearDown(() {
    library.dispose();
    store.dispose();
  });

  test('exact publication and format survive restart and wait for loaded library', () async {
    await library.record(library.capture(_catalog, _publication, _epub)!, _book.id);
    library.dispose();
    library = OpdsLibrary(prefs, dataStore: store)..setScope('guest');
    expect(library.bookId(_catalog, _publication), isNull);
    store.replaceBooksFromSync([_book]);
    expect(library.bookId(_catalog, _publication), _book.id);
    expect(library.bookId(_catalog, _publication, link: _epub), _book.id);
    expect(library.bookId(_catalog, _publication, link: _pdf), isNull);
    expect(library.bookId(_catalog, OpdsPublication(id: 'other-edition', title: 'Book')), isNull);
    expect(library.bookId(OpdsCatalog(id: 'other', name: 'Books', uri: _catalog.uri), _publication), isNull);
    expect(
      library.bookId(OpdsCatalog(id: 'one', name: 'Books', uri: Uri.parse('https://other.test')), _publication),
      isNull,
    );
    store.replaceBooksFromSync([]);
    expect(library.bookId(_catalog, _publication), isNull);
  });

  test('preview import does not mark the full publication as owned', () async {
    store.replaceBooksFromSync([_book]);
    final sample = OpdsLink(uri: Uri.parse('https://books.test/sample.epub'), rels: ['preview']);
    await library.record(library.capture(_catalog, _publication, sample)!, _book.id);
    expect(library.bookId(_catalog, _publication), isNull);
    expect(library.bookId(_catalog, _publication, link: sample), _book.id);
  });

  test('scope switches isolate matches and reject late results even after switching back', () async {
    store.replaceBooksFromSync([_book]);
    final lateImport = library.capture(_catalog, _publication, _epub)!;
    library.setScope('account');
    await library.record(lateImport, _book.id);
    expect(library.bookId(_catalog, _publication), isNull);
    library.setScope('guest');
    await library.record(lateImport, _book.id);
    expect(library.bookId(_catalog, _publication), isNull);
    await library.record(library.capture(_catalog, _publication, _epub)!, _book.id);
    library.setScope('account');
    expect(library.bookId(_catalog, _publication), isNull);
    library.setScope('guest');
    expect(library.bookId(_catalog, _publication), _book.id);
  });

  test('corrupt persisted identities do not break library lookup', () async {
    await prefs.setString('papyrus.opds.imports.v1.account', '{"bad-key":{"book":"local-book","sample":false}}');
    library.setScope('account');
    store.replaceBooksFromSync([_book]);
    expect(library.bookId(_catalog, _publication), isNull);
  });

  test('switching back before a pending persistence write preserves the in-memory identity', () async {
    store.replaceBooksFromSync([_book]);
    final save = library.record(library.capture(_catalog, _publication, _epub)!, _book.id);
    library.setScope('account');
    library.setScope('guest');
    expect(library.bookId(_catalog, _publication), _book.id);
    await save;
    library.setScope('account');
    final remove = library.forgetCatalog(_catalog.id, scope: 'guest');
    library.setScope('guest');
    expect(library.bookId(_catalog, _publication), isNull);
    await remove;
  });

  test('renaming preserves provenance; credentials and removal invalidate it', () async {
    final catalogs = OpdsCatalogs(OpdsCatalogStore(prefs, secrets: MemorySecrets()), library: library)
      ..setScope('guest');
    addTearDown(catalogs.dispose);
    await catalogs.save(_catalog);
    store.replaceBooksFromSync([_book]);
    await library.record(library.capture(_catalog, _publication, _epub)!, _book.id);
    await catalogs.save(OpdsCatalog(id: 'one', name: 'Renamed', uri: _catalog.uri));
    expect(library.bookId(_catalog, _publication), _book.id);
    await catalogs.save(
      _catalog,
      credentials: const OpdsCredentials(username: 'new', password: 'secret'),
    );
    expect(library.bookId(_catalog, _publication), isNull);
    await library.record(library.capture(_catalog, _publication, _epub)!, _book.id);
    await catalogs.remove(_catalog.id);
    expect(library.bookId(_catalog, _publication), isNull);
    expect(store.getBook(_book.id), isNotNull);
  });

  test('successful import is remembered; duplicate acquisition skips network; deletion permits reimport', () async {
    var requests = 0;
    var commits = 0;
    final downloads = OpdsDownloads(
      library: library,
      httpClient: OpdsHttpClient(
        clientFactory: () => MockRelayClient((_) async {
          requests++;
          return http.Response('book', 200);
        }),
      ),
      captureImport: () => BookImportSession(
        process: (_, _) async => const BookImportResult(
          bookId: 'local-book',
          title: 'Book',
          author: 'Author',
          fileSize: 4,
          fileHash: 'hash',
          fileExtension: 'epub',
        ),
        deleteFile: (_) async {},
        isCurrent: () => true,
        commit: (_, _) async {
          commits++;
          store.replaceBooksFromSync([_book]);
          return _book;
        },
      ),
    );
    addTearDown(downloads.dispose);
    await downloads.start(_catalog, _publication, _epub);
    expect(library.bookId(_catalog, _publication), _book.id);
    downloads.reset();
    await downloads.start(_catalog, _publication, _epub);
    expect(requests, 1);
    expect(commits, 1);
    expect(downloads.jobs.single.status, OpdsDownloadStatus.complete);
    store.replaceBooksFromSync([]);
    await downloads.start(_catalog, _publication, _epub);
    expect(requests, 2);
    expect(commits, 2);
  });

  test('commit failure never records ownership', () async {
    final downloads = OpdsDownloads(
      library: library,
      httpClient: OpdsHttpClient(clientFactory: () => MockRelayClient((_) async => http.Response('book', 200))),
      captureImport: () => BookImportSession(
        process: (_, _) async => const BookImportResult(
          bookId: 'local-book',
          title: 'Book',
          author: 'Author',
          fileSize: 4,
          fileHash: 'hash',
          fileExtension: 'epub',
        ),
        deleteFile: (_) async {},
        isCurrent: () => true,
        commit: (_, _) async => throw StateError('Commit failed'),
      ),
    );
    addTearDown(downloads.dispose);
    await downloads.start(_catalog, _publication, _epub);
    store.replaceBooksFromSync([_book]);
    expect(library.bookId(_catalog, _publication), isNull);
    expect(downloads.jobs.single.status, OpdsDownloadStatus.failed);
  });

  test('account switch during commit cannot record in the newly selected library', () async {
    final commitStarted = Completer<void>();
    final committed = Completer<Book>();
    final downloads = OpdsDownloads(
      library: library,
      httpClient: OpdsHttpClient(clientFactory: () => MockRelayClient((_) async => http.Response('book', 200))),
      captureImport: () => BookImportSession(
        process: (_, _) async => const BookImportResult(
          bookId: 'local-book',
          title: 'Book',
          author: 'Author',
          fileSize: 4,
          fileHash: 'hash',
          fileExtension: 'epub',
        ),
        deleteFile: (_) async {},
        isCurrent: () => true,
        commit: (_, _) {
          commitStarted.complete();
          return committed.future;
        },
      ),
    );
    addTearDown(downloads.dispose);
    final operation = downloads.start(_catalog, _publication, _epub);
    await commitStarted.future;
    library.setScope('other');
    downloads.reset();
    store.replaceBooksFromSync([_book]);
    committed.complete(_book);
    await operation;
    expect(library.bookId(_catalog, _publication), isNull);
    library.setScope('guest');
    expect(library.bookId(_catalog, _publication), isNull);
  });
}
