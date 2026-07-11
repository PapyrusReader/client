import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/auth/auth_api_client.dart';
import 'package:papyrus/auth/auth_models.dart';
import 'package:papyrus/auth/auth_repository.dart';
import 'package:papyrus/auth/papyrus_api_config.dart';
import 'package:papyrus/auth/token_store.dart';
import 'package:papyrus/media/media_storage_scope.dart';
import 'package:papyrus/providers/auth_provider.dart';
import 'package:papyrus/providers/sync_settings_provider.dart';
import 'package:papyrus/widgets/book/private_book_cover.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MemoryRefreshTokenStorage implements RefreshTokenStorage {
  String? value;

  @override
  Future<void> delete() async => value = null;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String refreshToken) async => value = refreshToken;
}

class _GatedAuthRepository extends AuthRepository {
  _GatedAuthRepository(this.tokens)
    : super(
        apiClient: AuthApiClient(config: PapyrusApiConfig(serverBaseUri: Uri.parse('https://api.test'))),
        tokenStore: TokenStore(_MemoryRefreshTokenStorage()),
      );

  final AuthTokens tokens;
  Completer<AuthTokens>? refreshGate;

  @override
  Future<AuthTokens?> bootstrap() async => tokens;

  @override
  Future<AuthTokens> refresh() => refreshGate?.future ?? Future.value(tokens);
}

void main() {
  final pngBytes = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('private cover renders lazily loaded bytes', (tester) async {
    var loads = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: PrivateBookCover(
          mediaId: 'asset-1',
          loadPrivateCover: (_) async {
            loads++;
            return Uint8List.fromList(pngBytes);
          },
          placeholder: const SizedBox(key: Key('placeholder')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Image), findsOneWidget);
    expect(find.byKey(const Key('placeholder')), findsNothing);
    expect(loads, 1);
  });

  testWidgets('private cover renders a local cover loaded by book id', (tester) async {
    final loadedBookIds = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        home: PrivateBookCover(
          bookId: 'book-1',
          loadLocalBookCover: (bookId) async {
            loadedBookIds.add(bookId);
            return Uint8List.fromList(pngBytes);
          },
          placeholder: const SizedBox(key: Key('placeholder')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Image), findsOneWidget);
    expect(find.byKey(const Key('placeholder')), findsNothing);
    expect(loadedBookIds, ['book-1']);
  });

  testWidgets('media id takes priority over a local book cover', (tester) async {
    var privateLoads = 0;
    var localLoads = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: PrivateBookCover(
          bookId: 'book-1',
          mediaId: 'asset-1',
          loadPrivateCover: (_) async {
            privateLoads++;
            return Uint8List.fromList(pngBytes);
          },
          loadLocalBookCover: (_) async {
            localLoads++;
            return Uint8List.fromList(pngBytes);
          },
          placeholder: const SizedBox(key: Key('placeholder')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(privateLoads, 1);
    expect(localLoads, 0);
  });

  testWidgets('local cover keeps one load future across rebuilds', (tester) async {
    var loads = 0;
    Future<Uint8List?> loader(String _) async {
      loads++;
      return Uint8List.fromList(pngBytes);
    }

    Widget build(String bookId) {
      return MaterialApp(
        home: PrivateBookCover(
          bookId: bookId,
          loadLocalBookCover: loader,
          placeholder: const SizedBox(key: Key('placeholder')),
        ),
      );
    }

    await tester.pumpWidget(build('book-1'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(build('book-1'));
    await tester.pumpAndSettle();

    expect(loads, 1);
  });

  testWidgets('local cover reloads when book id changes', (tester) async {
    final loadedBookIds = <String>[];
    Future<Uint8List?> loader(String bookId) async {
      loadedBookIds.add(bookId);
      return Uint8List.fromList(pngBytes);
    }

    Widget build(String bookId) {
      return MaterialApp(
        home: PrivateBookCover(
          bookId: bookId,
          loadLocalBookCover: loader,
          placeholder: const SizedBox(key: Key('placeholder')),
        ),
      );
    }

    await tester.pumpWidget(build('book-1'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(build('book-2'));
    await tester.pumpAndSettle();

    expect(loadedBookIds, ['book-1', 'book-2']);
  });

  testWidgets('local cover reloads when a non-null loader is replaced', (tester) async {
    final firstBytes = Uint8List.fromList(pngBytes);
    final secondBytes = Uint8List.fromList(pngBytes);
    Future<Uint8List?> firstLoader(String _) async => firstBytes;
    Future<Uint8List?> secondLoader(String _) async => secondBytes;

    Widget build(LocalBookCoverLoader loader) {
      return MaterialApp(
        home: PrivateBookCover(
          bookId: 'book-1',
          loadLocalBookCover: loader,
          placeholder: const SizedBox(key: Key('placeholder')),
        ),
      );
    }

    await tester.pumpWidget(build(firstLoader));
    await tester.pumpAndSettle();
    await tester.pumpWidget(build(secondLoader));
    await tester.pumpAndSettle();

    final image = tester.widget<Image>(find.byType(Image));
    expect(identical((image.image as MemoryImage).bytes, secondBytes), isTrue);
  });

  testWidgets('private cover reloads when a non-null loader is replaced', (tester) async {
    final firstBytes = Uint8List.fromList(pngBytes);
    final secondBytes = Uint8List.fromList(pngBytes);
    Future<Uint8List?> firstLoader(String _) async => firstBytes;
    Future<Uint8List?> secondLoader(String _) async => secondBytes;

    Widget build(PrivateCoverLoader loader) {
      return MaterialApp(
        home: PrivateBookCover(
          mediaId: 'asset-1',
          loadPrivateCover: loader,
          placeholder: const SizedBox(key: Key('placeholder')),
        ),
      );
    }

    await tester.pumpWidget(build(firstLoader));
    await tester.pumpAndSettle();
    await tester.pumpWidget(build(secondLoader));
    await tester.pumpAndSettle();

    final image = tester.widget<Image>(find.byType(Image));
    expect(identical((image.image as MemoryImage).bytes, secondBytes), isTrue);
  });

  testWidgets('refreshing account reads pending cover and never guest cover', (tester) async {
    final harness = await _buildProviderHarness();
    final refreshGate = Completer<AuthTokens>();
    harness.repository.refreshGate = refreshGate;
    final refresh = harness.authProvider.refresh();
    await tester.pump();
    expect(harness.authProvider.user, isNotNull);
    expect(harness.authProvider.isSignedIn, isFalse);
    var pendingLoads = 0;
    var guestLoads = 0;

    await tester.pumpWidget(
      harness.wrap(
        PrivateBookCover(
          bookId: 'book-1',
          loadPendingBookCover: (_, _) async {
            pendingLoads++;
            return Uint8List.fromList(pngBytes);
          },
          loadGuestBookCover: (_) async {
            guestLoads++;
            return Uint8List.fromList(pngBytes);
          },
          placeholder: const SizedBox(key: Key('placeholder')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(pendingLoads, 1);
    expect(guestLoads, 0);
    refreshGate.complete(harness.repository.tokens);
    await refresh;
  });

  testWidgets('mode changes reload guest and account local covers', (tester) async {
    final harness = await _buildProviderHarness(offline: true);
    final guestBytes = Uint8List.fromList(pngBytes);
    final accountBytes = Uint8List.fromList(pngBytes);
    var guestLoads = 0;
    var pendingLoads = 0;

    await tester.pumpWidget(
      harness.wrap(
        PrivateBookCover(
          bookId: 'book-1',
          loadPendingBookCover: (_, _) async {
            pendingLoads++;
            return accountBytes;
          },
          loadGuestBookCover: (_) async {
            guestLoads++;
            return guestBytes;
          },
          placeholder: const SizedBox(key: Key('placeholder')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(guestLoads, 1);
    expect(pendingLoads, 0);
    expect(identical((tester.widget<Image>(find.byType(Image)).image as MemoryImage).bytes, guestBytes), isTrue);

    harness.authProvider.setOfflineMode(false);
    await harness.authProvider.bootstrap();
    await tester.pumpAndSettle();
    expect(guestLoads, 1);
    expect(pendingLoads, 1);
    expect(identical((tester.widget<Image>(find.byType(Image)).image as MemoryImage).bytes, accountBytes), isTrue);

    harness.authProvider.setOfflineMode(true);
    await tester.pumpAndSettle();
    expect(guestLoads, 2);
    expect(pendingLoads, 1);
    expect(identical((tester.widget<Image>(find.byType(Image)).image as MemoryImage).bytes, guestBytes), isTrue);
  });

  testWidgets('profile changes reload pending cover in the new scope', (tester) async {
    final harness = await _buildProviderHarness();
    final officialBytes = Uint8List.fromList(pngBytes);
    final customBytes = Uint8List.fromList(pngBytes);
    final scopes = <MediaStorageScope>[];

    await tester.pumpWidget(
      harness.wrap(
        PrivateBookCover(
          bookId: 'book-1',
          loadPendingBookCover: (scope, _) async {
            scopes.add(scope);
            return scope.profileKey == SyncSettingsProvider.officialServerId ? officialBytes : customBytes;
          },
          loadGuestBookCover: (_) async => null,
          placeholder: const SizedBox(key: Key('placeholder')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    harness.syncSettings.setCustomServerUrls(apiUrl: 'https://custom.test', powerSyncUrl: 'https://sync.custom.test');
    await tester.pumpAndSettle();

    expect(scopes.map((scope) => scope.profileKey), [SyncSettingsProvider.officialServerId, startsWith('custom-')]);
    expect(identical((tester.widget<Image>(find.byType(Image)).image as MemoryImage).bytes, customBytes), isTrue);
  });

  testWidgets('injected to provider transition subscribes to later profile changes', (tester) async {
    final harness = await _buildProviderHarness();
    final injectedBytes = Uint8List.fromList(pngBytes);
    final officialBytes = Uint8List.fromList(pngBytes);
    final customBytes = Uint8List.fromList(pngBytes);
    final scopes = <MediaStorageScope>[];

    Future<Uint8List?> localLoader(String _) async => injectedBytes;
    Future<Uint8List?> pendingLoader(MediaStorageScope scope, String _) async {
      scopes.add(scope);
      return scope.profileKey == SyncSettingsProvider.officialServerId ? officialBytes : customBytes;
    }

    Widget build({required bool injected}) {
      return harness.wrap(
        PrivateBookCover(
          bookId: 'book-1',
          loadLocalBookCover: injected ? localLoader : null,
          loadPendingBookCover: pendingLoader,
          loadGuestBookCover: (_) async => null,
          placeholder: const SizedBox(key: Key('placeholder')),
        ),
      );
    }

    await tester.pumpWidget(build(injected: true));
    await tester.pumpAndSettle();
    expect(scopes, isEmpty);
    expect(identical((tester.widget<Image>(find.byType(Image)).image as MemoryImage).bytes, injectedBytes), isTrue);

    await tester.pumpWidget(build(injected: false));
    await tester.pumpAndSettle();
    expect(scopes.map((scope) => scope.profileKey), [SyncSettingsProvider.officialServerId]);
    expect(identical((tester.widget<Image>(find.byType(Image)).image as MemoryImage).bytes, officialBytes), isTrue);

    harness.syncSettings.setCustomServerUrls(apiUrl: 'https://custom.test', powerSyncUrl: 'https://sync.custom.test');
    await tester.pumpAndSettle();

    expect(scopes.map((scope) => scope.profileKey), [SyncSettingsProvider.officialServerId, startsWith('custom-')]);
    expect(identical((tester.widget<Image>(find.byType(Image)).image as MemoryImage).bytes, customBytes), isTrue);
  });

  testWidgets('local cover falls back to placeholder when there are no bytes', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PrivateBookCover(
          bookId: 'book-1',
          loadLocalBookCover: (_) async => null,
          placeholder: const SizedBox(key: Key('placeholder')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('placeholder')), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('book id without providers keeps the standalone placeholder', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: PrivateBookCover(
          bookId: 'book-1',
          placeholder: SizedBox(key: Key('placeholder')),
        ),
      ),
    );

    expect(find.byKey(const Key('placeholder')), findsOneWidget);
  });

  testWidgets('inline imported cover renders from memory instead of the network cache', (tester) async {
    final dataUri = Uri.dataFromBytes(pngBytes, mimeType: 'image/png').toString();

    await tester.pumpWidget(
      MaterialApp(
        home: PrivateBookCover(
          imageUrl: dataUri,
          placeholder: const SizedBox(key: Key('placeholder')),
        ),
      ),
    );

    final image = tester.widget<Image>(find.byType(Image));
    expect(image.image, isA<MemoryImage>());
    expect(find.byKey(const Key('placeholder')), findsNothing);
  });

  testWidgets('malformed inline imported cover renders the placeholder', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PrivateBookCover(
          imageUrl: 'data:not-valid',
          placeholder: const SizedBox(key: Key('placeholder')),
        ),
      ),
    );

    expect(find.byKey(const Key('placeholder')), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('private cover keeps one load future across rebuilds', (tester) async {
    var loads = 0;
    Future<Uint8List?> loader(String _) async {
      loads++;
      return Uint8List.fromList(pngBytes);
    }

    Widget build() {
      return MaterialApp(
        home: PrivateBookCover(
          mediaId: 'asset-1',
          loadPrivateCover: loader,
          placeholder: const SizedBox(key: Key('placeholder')),
        ),
      );
    }

    await tester.pumpWidget(build());
    await tester.pumpAndSettle();
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();

    expect(loads, 1);
  });

  testWidgets('private cover falls back to placeholder when the loader has no bytes', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PrivateBookCover(
          mediaId: 'asset-1',
          loadPrivateCover: (_) async => null,
          placeholder: const SizedBox(key: Key('placeholder')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('placeholder')), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('private cover falls back to placeholder after a load error', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PrivateBookCover(
          mediaId: 'asset-1',
          loadPrivateCover: (_) async => throw StateError('offline'),
          placeholder: const SizedBox(key: Key('placeholder')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('placeholder')), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });
}

class _ProviderHarness {
  const _ProviderHarness({required this.repository, required this.authProvider, required this.syncSettings});

  final _GatedAuthRepository repository;
  final AuthProvider authProvider;
  final SyncSettingsProvider syncSettings;

  Widget wrap(Widget child) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
        ChangeNotifierProvider<SyncSettingsProvider>.value(value: syncSettings),
      ],
      child: MaterialApp(home: child),
    );
  }
}

Future<_ProviderHarness> _buildProviderHarness({bool offline = false}) async {
  final prefs = await SharedPreferences.getInstance();
  final tokens = AuthTokens(
    accessToken: 'access-token',
    refreshToken: 'refresh-token',
    tokenType: 'Bearer',
    expiresIn: 3600,
    user: PapyrusUser(
      userId: 'user-1',
      email: 'reader@example.com',
      displayName: 'Reader',
      avatarUrl: null,
      emailVerified: true,
      createdAt: null,
      lastLoginAt: null,
    ),
  );
  final repository = _GatedAuthRepository(tokens);
  final authProvider = AuthProvider(prefs, repository: repository, bootstrapOnCreate: false);
  if (offline) {
    authProvider.setOfflineMode(true);
  } else {
    await authProvider.bootstrap();
  }
  final syncSettings = SyncSettingsProvider(
    prefs,
    officialConfig: PapyrusApiConfig(
      serverBaseUri: Uri.parse('https://api.test'),
      powerSyncServiceUri: Uri.parse('https://sync.test'),
    ),
  );
  return _ProviderHarness(repository: repository, authProvider: authProvider, syncSettings: syncSettings);
}
