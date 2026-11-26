import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:papyrus/auth/auth_api_client.dart';
import 'package:papyrus/auth/auth_repository.dart';
import 'package:papyrus/auth/papyrus_api_config.dart';
import 'package:papyrus/auth/token_store.dart';
import 'package:papyrus/data/data_store.dart';
import 'package:papyrus/main.dart';
import 'package:papyrus/media/media_upload_queue.dart';
import 'package:papyrus/models/book.dart';
import 'package:papyrus/models/note.dart';
import 'package:papyrus/pages/notes_page.dart';
import 'package:papyrus/powersync/papyrus_powersync_connector.dart';
import 'package:papyrus/powersync/powersync_service.dart';
import 'package:papyrus/providers/auth_provider.dart';
import 'package:papyrus/providers/sync_settings_provider.dart';
import 'package:papyrus/services/book_import_service_stub.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../auth/auth_repository_powersync_test.dart' show MemoryRefreshTokenStorage;

class _LocalServerBinding extends LiveTestWidgetsFlutterBinding {
  @override
  bool get overrideHttpClient => false;
}

class _JourneyPaths extends PathProviderPlatform {
  _JourneyPaths(this.directory);
  final Directory directory;

  @override
  Future<String?> getApplicationSupportPath() async => directory.path;

  @override
  Future<String?> getApplicationDocumentsPath() async => directory.path;
}

void main() {
  final enabled = Platform.environment.containsKey('PAPYRUS_DISPOSABLE_OTHER_EMAIL');

  if (enabled) {
    _LocalServerBinding();
  }

  testWidgets(
    'switching profiles isolates an offline note in the Notes page and after reconnect',
    (tester) async {
      final config = PapyrusApiConfig.fromEnvironment();
      final directory = await Directory.systemTemp.createTemp('papyrus-note-profiles-');
      addTearDown(() => directory.delete(recursive: true));
      final previousPaths = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _JourneyPaths(directory);
      addTearDown(() => PathProviderPlatform.instance = previousPaths);
      final client = http.Client();
      addTearDown(client.close);
      final accounts = <String, AuthRepository>{};
      final ids = <String, String>{};

      const emails = {'official': 'PAPYRUS_DISPOSABLE_OWNER_EMAIL', 'other': 'PAPYRUS_DISPOSABLE_OTHER_EMAIL'};

      for (final MapEntry(key: profile, value: emailKey) in emails.entries) {
        final repository = AuthRepository(
          apiClient: AuthApiClient(config: config, httpClient: client),
          tokenStore: TokenStore(MemoryRefreshTokenStorage()),
        );

        final session = await repository.login(
          email: Platform.environment[emailKey]!,
          password: Platform.environment['PAPYRUS_DISPOSABLE_PASSWORD']!,
          clientType: 'desktop',
        );

        accounts[profile] = repository;
        ids[profile] = session.user.userId;
      }

      expect(ids['official'], isNot(ids['other']));
      SharedPreferences.setMockInitialValues({
        'sync_custom_servers': jsonEncode([
          {
            'id': 'other',
            'url': config.serverBaseUri.toString(),
            'label': 'Other',
            'data_sync_url': config.powerSyncServiceUri.toString(),
          },
        ]),
      });
      final prefs = await SharedPreferences.getInstance();
      late AuthRepository active;
      final database = PapyrusPowerSyncService(
        connectorFactory: () => PapyrusPowerSyncConnector(authRepository: active, config: config),
      );

      await tester.pumpWidget(
        Papyrus.withServices(
          prefs: prefs,
          repositoryFactory: (_, profile) => active = accounts[profile == 'official' ? 'official' : 'other']!,
          database: database,
          uploads: MediaUploadQueue(prefs),
          importer: BookImportService(),
          child: const MaterialApp(home: NotesPage()),
        ),
      );

      final closed = database.syncStates.drain<void>();
      final context = tester.element(find.byType(NotesPage));
      final store = context.read<DataStore>();
      final settings = context.read<SyncSettingsProvider>();
      final auth = context.read<AuthProvider>();
      const privateText = 'Private offline observations';
      const deadline = Duration(seconds: 45);

      Future<void> until(String description, bool Function() condition) async {
        final timer = Stopwatch()..start();

        do {
          await tester.pump(const Duration(milliseconds: 50));

          if (auth.user?.userId == ids['other']) {
            expect(find.text(privateText), findsNothing);
            expect(store.notes.any((note) => note.content == privateText), isFalse);
          }

          if (condition()) {
            return;
          }
        } while (timer.elapsed < deadline);

        fail('Timed out waiting for $description');
      }

      Future<void> ready(String profile) => until(
        '$profile library',
        () => auth.user?.userId == ids[profile] && store.isLoaded && database.syncState.lastSyncedAt != null,
      );

      Future<Note> seed(String title) async {
        final book = Book(id: const Uuid().v4(), title: 'Same field guide', author: 'Papyrus', addedAt: DateTime.now());
        final note = Note(
          id: const Uuid().v4(),
          bookId: book.id,
          title: title,
          content: 'Original text',
          createdAt: DateTime.now(),
        );
        await store.addBookAndWait(book);
        await store.addNote(note);
        await until(
          'synced $title',
          () => find.text(title).evaluate().isNotEmpty && !database.syncState.hasPendingWrites,
        );
        return note;
      }

      try {
        await ready('official');
        final original = await seed('Field notes');
        settings.selectServer('other');
        await ready('other');
        final other = await seed('Other reader notes');
        settings.selectServer('official');
        await ready('official');
        await database.setOnline(false);
        await tester.tap(find.text(original.title));
        await tester.pumpAndSettle();
        final content = find.byWidgetPredicate(
          (widget) => widget is TextField && widget.decoration?.labelText == 'Content',
        );
        await tester.ensureVisible(content);
        await tester.enterText(content, privateText);
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save'));
        await until(
          'offline edit',
          () =>
              content.evaluate().isEmpty &&
              find.text(privateText).evaluate().length == 1 &&
              database.syncState.hasPendingWrites,
        );

        settings.selectServer('other');
        await ready('other');
        expect(find.text(other.title), findsOneWidget);
        expect(find.text(original.title), findsNothing);
        expect(store.getBook(other.bookId)?.title, 'Same field guide');
        expect(store.getBook(original.bookId), isNull);
        settings.selectServer('official');
        await ready('official');
        await until(
          'reconnected edit',
          () => find.text(privateText).evaluate().length == 1 && !database.syncState.hasPendingWrites,
        );
        expect(store.notes.where((note) => note.bookId == original.bookId).single.id, original.id);

        // A fresh database per identity proves the server received only its owner's note.
        for (final profile in ['official', 'other']) {
          final observer = PapyrusPowerSyncService(
            connectorFactory: () => PapyrusPowerSyncConnector(authRepository: accounts[profile]!, config: config),
            pathResolver: (_, _, _) async => '${directory.path}/observer-$profile.db',
          );

          try {
            await observer.activateAuthenticated(ids[profile]!);
            final expected = profile == 'official' ? original : other;
            final snapshot = await observer
                .watchLibrary()
                .firstWhere((snapshot) => snapshot.notes.any((note) => note.id == expected.id))
                .timeout(deadline);
            final saved = snapshot.notes.where((note) => note.bookId == expected.bookId).single;
            expect(saved.content, profile == 'official' ? privateText : other.content);
            expect(snapshot.notes.any((note) => note.id == (profile == 'official' ? other.id : original.id)), isFalse);
          } finally {
            await observer.close();
          }
        }
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await closed.timeout(deadline);
      }
    },
    skip: !enabled,
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
