import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/widgets/book/private_book_cover.dart';

void main() {
  final pngBytes = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  );

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
