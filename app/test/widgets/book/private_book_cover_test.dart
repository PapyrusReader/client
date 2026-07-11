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
