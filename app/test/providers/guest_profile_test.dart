import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/auth/auth_models.dart';
import 'package:papyrus/providers/auth_provider.dart';
import 'package:papyrus/services/guest_profile_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_provider_test.dart' show FakeAuthRepository;

class _Store extends GuestProfileStore {
  _Store(super.prefs);

  bool fail = false;
  Completer<void>? saving;

  @override
  Future<void> save({required String displayName, Uint8List? photoBytes}) async {
    await saving?.future;

    if (fail) {
      throw StateError('Storage unavailable');
    }

    await super.save(displayName: displayName, photoBytes: photoBytes);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences prefs;
  late AuthProvider auth;
  late _Store store;
  final photo = Uint8List.fromList([1, 2, 3]);

  setUp(() async {
    SharedPreferences.setMockInitialValues({'offline_mode': true});
    prefs = await SharedPreferences.getInstance();
    store = _Store(prefs);
    auth = AuthProvider(prefs, repository: FakeAuthRepository(), guestProfileStore: store, bootstrapOnCreate: false);
    addTearDown(auth.dispose);
  });

  test('local name and photo persist together, including name-only updates', () async {
    expect(auth.canEditProfile, isTrue);
    expect(auth.profileDisplayName, 'Anonymous User');
    expect(await auth.updateProfile(displayName: 'Local Reader', photoBytes: photo), isTrue);
    expect(await auth.updateProfile(displayName: 'New Name'), isTrue);
    await prefs.reload();
    final restarted = AuthProvider(prefs, repository: FakeAuthRepository(), bootstrapOnCreate: false);
    addTearDown(restarted.dispose);
    await restarted.bootstrap();
    expect(restarted.profileDisplayName, 'New Name');
    expect(restarted.profilePhotoBytes, photo);
    expect(restarted.user, isNull);
    expect(restarted.isOfflineMode, isTrue);
  });

  test('signed-in profiles do not inherit or overwrite the local profile', () async {
    await auth.updateProfile(displayName: 'Local Reader', photoBytes: photo);
    auth.setOfflineMode(false);
    final repository = FakeAuthRepository()
      ..bootstrapResult = AuthTokens(
        accessToken: 'access',
        refreshToken: 'refresh',
        tokenType: 'Bearer',
        expiresIn: 3600,
        user: const PapyrusUser(
          userId: 'account',
          email: 'reader@example.com',
          displayName: 'Server Reader',
          avatarUrl: null,
          emailVerified: true,
          createdAt: null,
          lastLoginAt: null,
        ),
      );

    await auth.replaceRepository(repository);
    expect(auth.profileDisplayName, 'Server Reader');
    expect(auth.profilePhotoBytes, isNull);
    auth.setOfflineMode(true);
    expect(auth.profileDisplayName, 'Local Reader');
    expect(auth.profilePhotoBytes, photo);
  });

  test('failed local save keeps the previous profile and allows retry', () async {
    await auth.updateProfile(displayName: 'Original', photoBytes: photo);
    store.fail = true;
    expect(await auth.updateProfile(displayName: 'Updated', photoBytes: Uint8List.fromList([4])), isFalse);
    expect(auth.profileDisplayName, 'Original');
    expect(auth.profilePhotoBytes, photo);
    expect(auth.error, contains('on this device'));
    store.fail = false;
    expect(await auth.updateProfile(displayName: 'Updated'), isTrue);
    expect(auth.profileDisplayName, 'Updated');
    expect(auth.error, isNull);
  });

  test('deletion waits for a pending save and then removes the entire local profile', () async {
    store.saving = Completer<void>();
    final saved = auth.updateProfile(displayName: 'Local Reader', photoBytes: photo);
    var cleared = false;
    final deleted = auth.deleteGuestAccount(() async => cleared = true);
    expect(auth.canEditProfile, isFalse);
    expect(await auth.updateProfile(displayName: 'Too late'), isFalse);
    expect(cleared, isFalse);
    store.saving!.complete();
    await saved;
    await deleted;
    expect(cleared, isTrue);
    await prefs.reload();
    expect(prefs.containsKey(GuestProfileStore.preferenceKey), isFalse);
    auth.setOfflineMode(true);
    expect(auth.profileDisplayName, 'Anonymous User');
    expect(auth.profilePhotoBytes, isNull);
  });

  test('failed account cleanup retains the local profile for retry', () async {
    await auth.updateProfile(displayName: 'Local Reader', photoBytes: photo);
    await expectLater(auth.deleteGuestAccount(() async => throw StateError('Disk unavailable')), throwsStateError);
    expect(auth.profileDisplayName, 'Local Reader');
    expect(auth.profilePhotoBytes, photo);
    expect(auth.canEditProfile, isTrue);
  });

  test('malformed stored profile falls back without preventing startup', () async {
    await prefs.setString(GuestProfileStore.preferenceKey, '{"display_name":"Reader","photo":"bad base64"}');
    final restarted = AuthProvider(prefs, repository: FakeAuthRepository(), bootstrapOnCreate: false);
    addTearDown(restarted.dispose);
    expect(restarted.profileDisplayName, 'Anonymous User');
    expect(restarted.profilePhotoBytes, isNull);
  });
}
