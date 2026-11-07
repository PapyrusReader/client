import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/models/book.dart';
import 'package:papyrus/powersync/powersync_service.dart';
import 'package:papyrus/providers/auth_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/pending_verification_test.dart' show repository, response, tokens, verificationRequired;
import 'powersync_service_test.dart' show OfflineConnector;

void main() {
  test(
    'denied refresh retains offline books and queued writes through guest, server and restart transitions',
    () async {
      SharedPreferences.setMockInitialValues({});
      final root = await Directory.systemTemp.createTemp('papyrus-verification-');
      addTearDown(() => root.delete(recursive: true));
      PapyrusPowerSyncService database() => PapyrusPowerSyncService(
        connectorFactory: OfflineConnector.new,
        connectAuthenticated: false,
        pathResolver: (mode, profile, user) async => '${root.path}/${mode.name}-${profile ?? ''}-${user ?? ''}.db',
      );
      var denied = false;
      final repo = repository((_) async => denied ? verificationRequired() : response(tokens()));
      final auth = AuthProvider(await SharedPreferences.getInstance(), repository: repo, bootstrapOnCreate: false);
      addTearDown(auth.dispose);
      await auth.login(email: 'alice@example.com', password: 'password');
      final db = database();
      await db.activateAuthenticated(auth.user!.userId, profileKey: 'one');
      await db.upsert(Book(id: 'offline-book', title: 'Keep this book', author: 'Reader', addedAt: DateTime.utc(2026)));
      expect(db.syncState.hasPendingWrites, isTrue);
      denied = true;
      expect(await auth.refresh(), isFalse);
      await db.setOnline(false);
      expect(auth.hasOfflineAccount, isTrue);
      expect((await db.getById('offline-book'))?.title, 'Keep this book');
      expect(db.syncState.hasPendingWrites, isTrue);
      await db.deactivate(clearAuthenticated: false);
      await db.activateGuest();
      expect(await db.getById('offline-book'), isNull);
      await db.upsert(Book(id: 'guest-book', title: 'Guest only', author: 'Guest', addedAt: DateTime.utc(2026)));
      await db.activateAuthenticated('bob', profileKey: 'one');
      expect(await db.getById('offline-book'), isNull);
      expect(await db.getById('guest-book'), isNull);
      await db.activateAuthenticated('alice', profileKey: 'two');
      expect(await db.getById('offline-book'), isNull);
      await db.close();
      final restarted = database();
      await restarted.activateAuthenticated('alice', profileKey: 'one');
      expect((await restarted.getById('offline-book'))?.title, 'Keep this book');
      expect(restarted.syncState.hasPendingWrites, isTrue);
      expect(await restarted.getById('guest-book'), isNull);
      await restarted.close();
    },
  );
}
