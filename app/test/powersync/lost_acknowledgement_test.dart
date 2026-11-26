import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:papyrus/auth/auth_api_client.dart';
import 'package:papyrus/auth/auth_repository.dart';
import 'package:papyrus/auth/papyrus_api_config.dart';
import 'package:papyrus/auth/token_store.dart';
import 'package:papyrus/models/annotation.dart';
import 'package:papyrus/models/book.dart';
import 'package:papyrus/models/note.dart';
import 'package:papyrus/powersync/papyrus_powersync_connector.dart';
import 'package:papyrus/powersync/powersync_service.dart';
import 'package:uuid/uuid.dart';

import '../auth/auth_repository_powersync_test.dart' show MemoryRefreshTokenStorage;

class _ObservedRepository extends AuthRepository {
  _ObservedRepository({required super.apiClient, required super.tokenStore});

  Future<void> Function()? beforeNextNoteUpload;
  final uploads = <String, int>{};

  @override
  Future<void> uploadPowerSyncBatch(List<Map<String, dynamic>> batch) async {
    if (batch.any((entry) => entry['type'] == 'notes') && beforeNextNoteUpload != null) {
      final inject = beforeNextNoteUpload!;
      beforeNextNoteUpload = null;
      await inject();
    }

    for (final entry in batch) {
      uploads.update(entry['id'] as String, (count) => count + 1, ifAbsent: () => 1);
    }

    return super.uploadPowerSyncBatch(batch);
  }
}

void main() {
  test(
    'annotation creation and offline note edits and deletes survive lost acknowledgements',
    () async {
      final directory = await Directory.systemTemp.createTemp('papyrus-lost-ack-');
      addTearDown(() => directory.delete(recursive: true));
      final httpClient = http.Client();
      addTearDown(httpClient.close);
      final config = PapyrusApiConfig.fromEnvironment();
      final control = Uri.parse(Platform.environment['PAPYRUS_TOXIPROXY']!);
      final name = 'upload-${const Uuid().v4()}';
      final proxy = '/proxies/$name';

      Future<http.Response> post(String path, Map<String, Object> body) async {
        final response = await httpClient.post(control.resolve(path), body: jsonEncode(body));
        expect(response.statusCode, inInclusiveRange(200, 299), reason: 'Toxiproxy $path: ${response.body}');
        return response;
      }

      final created = await post('/proxies', {
        'name': name,
        'listen': '127.0.0.1:0',
        'upstream': config.serverBaseUri.authority,
      });

      addTearDown(() async => httpClient.delete(control.resolve(proxy)));
      final listen = jsonDecode(created.body)['listen'] as String;
      final firstConfig = PapyrusApiConfig(serverBaseUri: Uri.parse('http://$listen'));

      _ObservedRepository repository(PapyrusApiConfig api) => _ObservedRepository(
        apiClient: AuthApiClient(config: api, httpClient: httpClient),
        tokenStore: TokenStore(MemoryRefreshTokenStorage()),
      );

      late String userId;

      Future<PapyrusPowerSyncService> open(String label, AuthRepository repository) async {
        final session = await repository.login(
          email: Platform.environment['PAPYRUS_DISPOSABLE_OWNER_EMAIL']!,
          password: Platform.environment['PAPYRUS_DISPOSABLE_PASSWORD']!,
          clientType: 'desktop',
        );

        userId = session.user.userId;

        final service = PapyrusPowerSyncService(
          connectorFactory: () => PapyrusPowerSyncConnector(authRepository: repository, config: config),
          pathResolver: (_, _, _) async => '${directory.path}/$label.db',
        );

        addTearDown(service.close);
        await service.activateAuthenticated(session.user.userId);
        await service.syncStates.firstWhere((state) => state.lastSyncedAt != null).timeout(const Duration(seconds: 60));
        return service;
      }

      final writer = repository(firstConfig);
      final first = await open('writer', writer);
      final second = await open('observer', repository(config));
      final book = Book(
        id: const Uuid().v4(),
        title: 'Lost acknowledgement',
        author: 'Papyrus',
        addedAt: DateTime.now(),
      );
      await first.upsert(book);
      final deadline = const Duration(seconds: 60);
      await second
          .watchLibrary()
          .firstWhere((library) => library.books.any((item) => item.id == book.id))
          .timeout(deadline);

      final annotation = Annotation(
        id: const Uuid().v4(),
        bookId: book.id,
        selectedText: 'This passage survives a retry.',
        location: const BookLocation(pageNumber: 2),
        createdAt: DateTime.now().toUtc(),
      );

      Future<void> withholdResponse() async {
        await post('$proxy/toxics', {
          'name': 'withhold-response',
          'type': 'timeout',
          'stream': 'downstream',
          'attributes': {'timeout': 0},
        });
      }

      await withholdResponse();
      await first.annotations.upsert(annotation);
      await second
          .watchLibrary()
          .firstWhere((library) => library.annotations.any((item) => item.id == annotation.id))
          .timeout(deadline);
      await first.syncStates.firstWhere((state) => state.hasPendingWrites).timeout(deadline);
      Future<void> dropResponseAndRecover() async {
        // Close the stalled socket before allowing any acknowledgement through.
        await post(proxy, {'enabled': false});
        final removed = await httpClient.delete(control.resolve('$proxy/toxics/withhold-response'));
        expect(removed.statusCode, 204);
        await post(proxy, {'enabled': true});
        await first.syncStates
            .firstWhere((state) => !state.hasPendingWrites && state.uploadError == null)
            .timeout(deadline);
      }

      await dropResponseAndRecover();
      expect(writer.uploads[annotation.id], greaterThanOrEqualTo(2));

      for (final device in [first, second]) {
        final snapshot = await device.watchLibrary().firstWhere((value) => value.isLoaded).timeout(deadline);
        final saved = snapshot.annotations.where((item) => item.bookId == book.id).single;
        expect(saved.id, annotation.id);
        expect(saved.selectedText, annotation.selectedText);
      }

      final kept = Note(
        id: const Uuid().v4(),
        bookId: book.id,
        title: 'Margin note',
        content: 'Original',
        createdAt: DateTime.now(),
      );
      final deleted = kept.copyWith(id: const Uuid().v4(), title: 'Second margin note');
      await first.notes.upsert(kept);
      await first.notes.upsert(deleted);
      await second
          .watchLibrary()
          .firstWhere(
            (library) =>
                library.notes.any((note) => note.id == kept.id) && library.notes.any((note) => note.id == deleted.id),
          )
          .timeout(deadline);
      await first.syncStates.firstWhere((state) => !state.hasPendingWrites).timeout(deadline);
      await first.setOnline(false);
      final editAttempts = writer.uploads[kept.id]!;
      final edited = kept.copyWith(content: 'Edited offline', updatedAt: DateTime.now());
      await first.notes.upsert(edited);
      await first.notes.delete(deleted.id);
      final offline = await second.watchLibrary().firstWhere((value) => value.isLoaded).timeout(deadline);
      expect(offline.notes.singleWhere((note) => note.id == kept.id).content, kept.content);
      expect(offline.notes.any((note) => note.id == deleted.id), isTrue);

      writer.beforeNextNoteUpload = withholdResponse;
      await first.setOnline(true);
      await second
          .watchLibrary()
          .firstWhere((library) => library.notes.any((note) => note.id == kept.id && note.content == edited.content))
          .timeout(deadline);
      await first.syncStates.firstWhere((state) => state.hasPendingWrites).timeout(deadline);
      await dropResponseAndRecover();
      expect(writer.uploads[kept.id]! - editAttempts, greaterThanOrEqualTo(2));

      for (final device in [first, second]) {
        await device
            .watchLibrary()
            .firstWhere(
              (library) =>
                  library.isLoaded &&
                  library.notes.every((note) => note.id != deleted.id) &&
                  library.notes.any((note) => note.id == kept.id && note.content == edited.content),
            )
            .timeout(deadline);
        await device.activateGuest();
        await device.activateAuthenticated(userId);
        final reopened = await device
            .watchLibrary()
            .firstWhere((value) => value.isLoaded && value.books.any((item) => item.id == book.id))
            .timeout(deadline);
        final note = reopened.notes.where((item) => item.bookId == book.id).single;
        expect(note.id, kept.id);
        expect(note.content, edited.content);
      }

      await first.delete(book.id);
      await second
          .watchLibrary()
          .firstWhere((library) => library.books.every((item) => item.id != book.id))
          .timeout(deadline);
    },
    skip: Platform.environment['PAPYRUS_TOXIPROXY'] == null,
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
