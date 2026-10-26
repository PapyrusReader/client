import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:papyrus/data/data_store.dart';
import 'package:papyrus/models/annotation.dart';
import 'package:papyrus/models/book.dart';
import 'package:papyrus/models/bookmark.dart';
import 'package:papyrus/models/note.dart';
import 'package:papyrus/pages/annotations_page.dart';
import 'package:papyrus/pages/bookmarks_page.dart';
import 'package:papyrus/pages/notes_page.dart';
import 'package:papyrus_reader/papyrus_reader.dart';
import 'package:provider/provider.dart';

import '../helpers/test_helpers.dart';

void main() {
  for (final width in [400.0, 1280.0]) {
    for (final format in [BookFormat.epub, BookFormat.pdf]) {
      testWidgets('dedicated saved items open exact $format locations at width $width', (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final book = buildTestBook(id: 'saved-book', fileFormat: format);
        final ReaderLocator bookmarkLocator = format == BookFormat.epub
            ? EpubReaderLocator(spineIndex: 3, textOffset: 456, localProgression: .25, totalProgression: .4)
            : PdfReaderLocator(pageIndex: 7, pageOffset: .35, totalProgression: .4);
        final ReaderLocator annotationLocator = format == BookFormat.epub
            ? EpubReaderLocator(spineIndex: 4, textOffset: 789, localProgression: .5, totalProgression: .6)
            : PdfReaderLocator(pageIndex: 12, pageOffset: .65, totalProgression: .6);
        final store = DataStore()
          ..loadData(
            books: [book],
            bookmarks: [
              Bookmark(
                id: 'bookmark',
                bookId: book.id,
                position: .4,
                readerLocator: bookmarkLocator.toJson(),
                note: 'Saved target',
                createdAt: DateTime(2026),
              ),
            ],
            annotations: [
              Annotation(
                id: 'annotation',
                bookId: book.id,
                selectedText: 'Selected target',
                location: BookLocation(pageNumber: 13, readerLocator: annotationLocator.toJson()),
                createdAt: DateTime(2026),
              ),
            ],
          );
        addTearDown(store.dispose);
        String? routedLocation;
        final router = GoRouter(
          initialLocation: '/bookmarks',
          routes: [
            GoRoute(path: '/bookmarks', builder: (_, _) => const BookmarksPage()),
            GoRoute(path: '/annotations', builder: (_, _) => const AnnotationsPage()),
            GoRoute(
              name: 'BOOK_READER',
              path: '/read/:bookId',
              builder: (_, state) {
                expect(state.pathParameters['bookId'], book.id);
                routedLocation = state.uri.queryParameters['location'];
                return const Scaffold(body: Text('Reader destination'));
              },
            ),
          ],
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(
          ChangeNotifierProvider.value(
            value: store,
            child: MaterialApp.router(routerConfig: router),
          ),
        );
        await tester.pumpAndSettle();
        for (final (path, label, locator) in [
          ('/bookmarks', 'Saved target', bookmarkLocator),
          ('/annotations', '"Selected target"', annotationLocator),
        ]) {
          router.go(path);
          await tester.pumpAndSettle();
          await tester.tap(find.text(label));
          await tester.pumpAndSettle();
          expect(find.text('Reader destination'), findsOneWidget);
          expect(ReaderLocator.fromJson(Map<String, Object?>.from(jsonDecode(routedLocation!) as Map)), locator);
          router.pop();
          await tester.pumpAndSettle();
          expect(find.text(label), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('dedicated notes open an editor without reader navigation at width $width', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final book = buildTestBook();
      final store = DataStore()
        ..loadData(
          books: [book],
          notes: [
            Note(
              id: 'note',
              bookId: book.id,
              title: 'Freehand thoughts',
              content: 'Remember this idea',
              location: const BookLocation(pageNumber: 15),
              createdAt: DateTime(2026),
            ),
          ],
        );
      addTearDown(store.dispose);
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: store,
          child: const MaterialApp(home: NotesPage()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Freehand thoughts'));
      await tester.pumpAndSettle();
      final contentField = find.byKey(const Key('note-content-field'));
      expect(contentField, findsOneWidget);
      await tester.enterText(contentField, 'Updated independent thought');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(store.notes.single.content, 'Updated independent thought');
      expect(store.notes.single.location, isNull);
      expect(tester.takeException(), isNull);
    });
  }
}
