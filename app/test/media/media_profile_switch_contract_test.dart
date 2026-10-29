import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/auth/auth_models.dart';
import 'package:papyrus/data/repositories/library_repository.dart';
import 'package:papyrus/main.dart';
import 'package:papyrus/models/book.dart';
import 'package:papyrus/media/media_models.dart';
import 'package:papyrus/media/media_storage_scope.dart';
import 'package:papyrus/media/media_upload_queue.dart';
import 'package:papyrus/opds/opds_catalogs.dart';
import 'package:papyrus/powersync/book_metadata_sync_state.dart';
import 'package:papyrus/powersync/powersync_service.dart';
import 'package:papyrus/powersync/sync_state.dart';
import 'package:papyrus/providers/sync_settings_provider.dart';
import 'package:papyrus/services/book_import_service_stub.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/auth_provider_test.dart' show FakeAuthRepository;

class _Database extends Fake implements PapyrusPowerSyncService {
  final activation = Completer<void>();
  final started = Completer<void>();

  @override
  LibraryDatabaseMode? mode;

  @override
  Future<void> activateAuthenticated(String userId, {String? profileKey}) async {
    if (!started.isCompleted) {
      started.complete();
    }

    await activation.future;
    mode = LibraryDatabaseMode.authenticated;
  }

  @override
  Future<void> activateGuest() async {
    if (!started.isCompleted) {
      started.complete();
    }

    await activation.future;
    mode = LibraryDatabaseMode.guest;
  }

  @override
  Future<void> deactivate({bool clearAuthenticated = false}) async => mode = null;
  @override
  Future<void> close() async {}
  @override
  Stream<LibrarySnapshot> watchLibrary() => const Stream.empty();
  @override
  BookMetadataSyncState get bookMetadataSyncState => const BookMetadataSyncState();
  @override
  Stream<BookMetadataSyncState> get bookMetadataSyncStates => const Stream.empty();
  @override
  SyncState get syncState => const SyncState();
  @override
  Stream<SyncState> get syncStates => const Stream.empty();
}

class _Repository extends FakeAuthRepository {
  _Repository(String userId) {
    bootstrapResult = AuthTokens.fromJson({
      'access_token': 'access',
      'refresh_token': 'refresh',
      'expires_in': 3600,
      'user': {'user_id': userId, 'connected_providers': <String>[]},
    });
  }

  final uploadStarted = Completer<void>();
  final finishUpload = Completer<void>();
  final uploaded = <MediaUploadPayload>[];

  @override
  Future<MediaStorageUsage> fetchMediaUsage() async =>
      const MediaStorageUsage(usedBytes: 0, quotaBytes: 1000, availableBytes: 1000);

  @override
  Future<MediaAsset> uploadMedia(MediaUploadPayload payload) async {
    uploaded.add(payload);
    uploadStarted.complete();
    await finishUpload.future;

    return MediaAsset(
      assetId: 'asset',
      ownerUserId: bootstrapResult!.user.userId,
      bookId: payload.bookId,
      kind: payload.kind,
      originalFilename: payload.filename,
      contentType: payload.contentType,
      extension: 'png',
      sizeBytes: payload.bytes.length,
      sha256: 'hash',
      storagePath: 'private',
    );
  }
}

class _Importer extends BookImportService {
  final reads = <MediaStorageScope>[];
  final promotions = <MediaStorageScope>[];

  @override
  Future<Uint8List?> getPendingCoverFile(MediaStorageScope scope, String bookId) async {
    reads.add(scope);
    return Uint8List.fromList([1, 2, 3]);
  }

  @override
  Future<void> promotePendingCoverFile(
    MediaStorageScope scope, {
    required String bookId,
    required String mediaId,
  }) async {
    promotions.add(scope);
  }
}

void main() {
  for (final guest in [false, true]) {
    testWidgets('catalogs wait for the ${guest ? 'guest' : 'account'} database activation', (tester) async {
      SharedPreferences.setMockInitialValues({'offline_mode': guest});
      final prefs = await SharedPreferences.getInstance();
      final database = _Database();
      final uploads = MediaUploadQueue(prefs);
      final repository = _Repository('alice');
      late OpdsCatalogs catalogs;

      await tester.pumpWidget(
        Papyrus.withServices(
          prefs: prefs,
          repositoryFactory: (_, _) => repository,
          database: database,
          uploads: uploads,
          importer: _Importer(),
          child: Builder(
            builder: (context) {
              catalogs = context.read<OpdsCatalogs>();
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      await tester.pump();
      expect(database.started.isCompleted, isTrue);
      expect(catalogs.scope, isNull);
      database.activation.complete();
      await tester.pump();
      expect(
        catalogs.scope,
        guest ? MediaStorageScope.localGuest.persistenceKey : 'official--alice',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      uploads.dispose();
    });
  }

  testWidgets('a profile switch waits for upload and promotes only the captured account cover', (tester) async {
    SharedPreferences.setMockInitialValues({
      'sync_custom_servers': jsonEncode([
        {'id': 'other', 'url': 'https://other.test', 'label': 'Other', 'data_sync_url': 'https://sync.other.test'},
      ]),
    });

    final prefs = await SharedPreferences.getInstance();
    final database = _Database()..activation.complete();
    final uploads = MediaUploadQueue(prefs);
    final oldScope = MediaStorageScope(profileKey: 'official', userId: 'alice');
    await uploads.activateScope(oldScope);
    await uploads.enqueueCover(
      book: Book(id: 'book', title: 'Book', author: 'Author', addedAt: DateTime(2026)),
      filename: 'cover.png',
      contentType: 'image/png',
    );
    final oldRepository = _Repository('alice');
    final newRepository = _Repository('bob');
    final importer = _Importer();
    final repositories = <String>[];
    late SyncSettingsProvider settings;
    late OpdsCatalogs catalogs;

    await tester.pumpWidget(
      Papyrus.withServices(
        prefs: prefs,
        repositoryFactory: (_, profile) {
          repositories.add(profile);
          return profile == 'official' ? oldRepository : newRepository;
        },
        database: database,
        uploads: uploads,
        importer: importer,
        child: Builder(
          builder: (context) {
            settings = context.read<SyncSettingsProvider>();
            catalogs = context.read<OpdsCatalogs>();
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    await tester.pump();
    expect(oldRepository.uploadStarted.isCompleted, isTrue);
    settings.selectServer('other');
    await tester.pump();
    expect(catalogs.scope, isNull);
    expect(repositories, ['official']);
    expect(uploads.activeScope, oldScope);
    oldRepository.finishUpload.complete();
    await tester.pump();
    await tester.pump();
    expect(importer.reads, [oldScope]);
    expect(importer.promotions, [oldScope]);
    expect(newRepository.uploaded, isEmpty);
    expect(uploads.activeScope, MediaStorageScope(profileKey: settings.activeProfileKey, userId: 'bob'));
    expect(catalogs.scope, uploads.activeScope!.persistenceKey);
    expect(uploads.pendingTasks, isEmpty);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    uploads.dispose();
  });
}
