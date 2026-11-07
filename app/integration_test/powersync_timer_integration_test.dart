import '../test/support/disposable_sync_accounts.dart';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:papyrus/auth/auth_api_client.dart';
import 'package:papyrus/auth/auth_repository.dart';
import 'package:papyrus/auth/papyrus_api_config.dart';
import 'package:papyrus/auth/token_store.dart';
import 'package:papyrus/data/data_store.dart';
import 'package:papyrus/data/repositories/reading_timer_repository.dart';
import 'package:papyrus/models/book.dart';
import 'package:papyrus/powersync/papyrus_powersync_connector.dart';
import 'package:papyrus/powersync/library_database.dart';
import 'package:papyrus/powersync/powersync_service.dart';
import 'package:papyrus/providers/reading_timer_provider.dart';
import 'package:papyrus/timer/reading_timer.dart';
import 'package:uuid/uuid.dart';

import 'powersync_books_integration_test.dart' show MemoryRefreshTokenStorage, waitForBook;

const runIntegration = bool.fromEnvironment('RUN_POWERSYNC_INTEGRATION');

Future<void> waitUntil(Future<bool> Function() condition, String description) async {
  final deadline = DateTime.now().add(const Duration(seconds: 30));

  while (DateTime.now().isBefore(deadline)) {
    if (await condition()) {
      return;
    }

    await Future<void>.delayed(const Duration(milliseconds: 100));
  }

  fail('Timed out: $description');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'PowerSync timer handoff, offline conflicts, save once and isolation',
    (tester) async {
      final config = PapyrusApiConfig.fromEnvironment();
      final root = await Directory.systemTemp.createTemp('papyrus-timer-sync-');
      requireDisposableSyncAccounts();
      const email = syncOwnerEmail;
      const password = syncPassword;
      final accounts = <AuthRepository>[];
      final services = <PapyrusPowerSyncService>[];
      final stores = <DataStore>[];
      final providers = <ReadingTimerProvider>[];

      AuthRepository auth() => AuthRepository(
        apiClient: AuthApiClient(config: config),
        tokenStore: TokenStore(MemoryRefreshTokenStorage()),
      );

      Future<PapyrusPowerSyncService> device(AuthRepository account, String user, String label) async {
        final service = PapyrusPowerSyncService(
          connectorFactory: () => PapyrusPowerSyncConnector(authRepository: account, config: config),
          trackingCapability: () async => 2,
          pathResolver: (mode, profile, user) async => '${root.path}/$label-${mode.name}-$user.db',
        );

        services.add(service);
        await service.activateAuthenticated(user);
        await waitUntil(() async => service.syncState.connected, '$label connects');
        return service;
      }

      Future<ReadingTimerProvider> watch(PapyrusPowerSyncService service) async {
        final store = DataStore();
        stores.add(store);
        await store.attachBookRepository(service);
        final provider = ReadingTimerProvider(store, tick: false);
        providers.add(provider);
        await waitUntil(() async => provider.available, 'timer repository loads');
        return provider;
      }

      ReadingTimerRepository timers(PapyrusPowerSyncService service) =>
          service.trackingRepository as ReadingTimerRepository;

      try {
        final browserAuth = auth();
        final owner = await browserAuth.login(
          email: email,
          password: password,
          clientType: 'desktop',
        );
        accounts.add(browserAuth);
        final phoneAuth = auth();
        await phoneAuth.login(email: email, password: password, clientType: 'desktop');
        final otherAuth = auth();
        final otherOwner = await otherAuth.login(
          email: syncOtherEmail,
          password: password,
          clientType: 'desktop',
        );
        accounts.add(otherAuth);
        final browser = await device(browserAuth, owner.user.userId, 'browser');
        final phone = await device(phoneAuth, owner.user.userId, 'phone');
        final other = await device(otherAuth, otherOwner.user.userId, 'other');
        final browserTimer = await watch(browser);
        final phoneTimer = await watch(phone);
        final book = Book(
          id: const Uuid().v4(),
          title: 'Synced timer',
          author: 'Papyrus',
          addedAt: DateTime.now().toUtc(),
        );
        await browser.upsert(book);
        await waitForBook(phone, book.id);
        final start = DateTime.now().toUtc().subtract(const Duration(minutes: 2));
        final initial = ReadingTimer.start(book, start, 'browser', [], targetSeconds: 60);
        await timers(browser).writeTimer(initial);
        await waitUntil(() async => phoneTimer.session?.id == initial.id, 'countdown reaches second device');
        expect(phoneTimer.elapsed, const Duration(minutes: 1));
        expect(phoneTimer.goalReached, isTrue);
        expect(await timers(other).loadTimer(), isNull);
        expect(await phoneTimer.resume(), isTrue);
        await waitUntil(
          () async => browserTimer.session?.version == phoneTimer.session?.version,
          'resume reaches first device',
        );
        expect(browserTimer.session!.targetSeconds, isNull);
        expect(browserTimer.running, isTrue);

        await browser.setOnline(false);
        expect(await browserTimer.pause(), isTrue);
        final offlineVersion = browserTimer.session!.version;
        expect(await phoneTimer.pause(), isTrue);
        final acceptedVersion = phoneTimer.session!.version;
        await waitUntil(() async => !phone.syncState.hasPendingWrites, 'online pause uploads');
        await browser.setOnline(true);
        await waitUntil(
          () async => browserTimer.session?.version == acceptedVersion,
          'offline stale branch reconciles',
        );
        expect(browserTimer.session!.version, isNot(offlineVersion));
        expect(browserTimer.elapsed, phoneTimer.elapsed);

        await browser.setOnline(false);
        await phone.setOnline(false);
        expect(await browserTimer.save(currentPage: 12), isTrue);
        expect(await phoneTimer.save(currentPage: 24), isTrue);
        await browser.setOnline(true);
        await waitUntil(() async => !browser.syncState.hasPendingWrites, 'first save uploads');
        await phone.setOnline(true);
        await waitUntil(() async => !phone.syncState.hasPendingWrites, 'second save acknowledged');
        await waitForBook(phone, book.id);
        await waitUntil(() async => (await phone.getById(book.id))?.currentPage == 12, 'accepted progress reconciles');
        await waitUntil(
          () async => (await (phone.trackingRepository as LibraryDatabase).snapshot()).activities.isNotEmpty,
          'saved history replicates',
        );
        final firstHistory = (await (browser.trackingRepository as LibraryDatabase).snapshot()).activities;
        final secondHistory = (await (phone.trackingRepository as LibraryDatabase).snapshot()).activities;
        expect(firstHistory.map((entry) => entry.id).toSet(), secondHistory.map((entry) => entry.id).toSet());
        expect(firstHistory.map((entry) => entry.sessionId).toSet(), {initial.id});
        expect(firstHistory.length, 2);
        expect(browserTimer.session, isNull);
        expect(phoneTimer.session, isNull);
        expect(await timers(other).loadTimer(), isNull);
        expect((await (other.trackingRepository as LibraryDatabase).snapshot()).activities, isEmpty);

        expect(await phoneTimer.start(book), isTrue);
        await waitUntil(() async => browserTimer.session?.id == phoneTimer.session?.id, 'new session syncs');
        expect(await browserTimer.discard(), isTrue);
        await waitUntil(() async => phoneTimer.session == null, 'reset clears both devices');
      } finally {
        for (final provider in providers) {
          provider.dispose();
        }

        for (final store in stores) {
          store.dispose();
        }

        for (final service in services) {
          await service.close();
        }

        for (final account in accounts) {
          await account.deleteAccount();
        }

        await root.delete(recursive: true);
      }
    },
    skip: !runIntegration,
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
