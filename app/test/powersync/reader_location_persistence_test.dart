import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/data/data_store.dart';
import 'package:papyrus/models/annotation.dart';
import 'package:papyrus/models/bookmark.dart';
import 'package:papyrus/models/note.dart';
import 'package:papyrus/powersync/library_row_mapper.dart';
import 'package:papyrus/powersync/powersync_service.dart';
import 'package:papyrus/powersync/sync_state.dart';
import 'package:papyrus/reader/reader_library.dart';
import 'package:papyrus_reader/papyrus_reader.dart';

import '../helpers/test_helpers.dart';
import 'powersync_service_test.dart' show OfflineConnector;

void main() {
  for (final guest in [true, false]) {
    test('reader anchors and highlights survive reopening ${guest ? 'guest' : 'account'} storage', () async {
      final directory = await Directory.systemTemp.createTemp('papyrus-reader-locations-');
      PapyrusPowerSyncService open() => PapyrusPowerSyncService(
        connectorFactory: OfflineConnector.new,
        connectAuthenticated: false,
        pathResolver: (mode, profile, user) async =>
            '${directory.path}/${mode == LibraryDatabaseMode.guest ? 'guest' : '$profile-$user'}.db',
      );
      Future<void> activate(PapyrusPowerSyncService db) => guest ? db.activateGuest() : db.activateAuthenticated('one');
      var db = open();
      await activate(db);
      await db.upsert(buildTestBook(id: 'book'));
      final start = EpubReaderLocator(spineIndex: 2, textOffset: 42, localProgression: .1, totalProgression: .25);
      final end = EpubReaderLocator(spineIndex: 2, textOffset: 47, localProgression: .2, totalProgression: .25);
      final selection = ReaderSelection(text: 'Quote', start: start, end: end);
      final location = BookLocation(pageNumber: 1, readerLocator: start.toJson(), selection: selection.toJson());
      final bookmark = Bookmark(
        id: 'bookmark',
        bookId: 'book',
        position: .25,
        readerLocator: start.toJson(),
        createdAt: DateTime.utc(2026),
      );
      final annotation = Annotation(
        id: 'annotation',
        bookId: 'book',
        selectedText: 'Quote',
        location: location,
        createdAt: DateTime.utc(2026),
      );
      final note = Note(
        id: 'note',
        bookId: 'book',
        title: 'Thought',
        content: 'Remember',
        createdAt: DateTime.utc(2026),
      );
      await db.bookmarks.upsert(bookmark);
      await db.annotations.upsert(annotation);
      await db.notes.upsert(note);
      expect(decodeLibraryRow(bookmarkRowMapper.toRow(bookmark))['reader_locator'], start.toJson());
      expect(
        (decodeLibraryRow(annotationRowMapper.toRow(annotation))['location'] as Map)['selection'],
        selection.toJson(),
      );
      await db.close();
      db = open();
      await activate(db);
      expect((await db.bookmarks.getById('bookmark'))!.readerLocator, start.toJson());
      expect((await db.annotations.getById('annotation'))!.location.selection, selection.toJson());
      expect((await db.notes.getById('note'))!.location, isNull);
      expect((await db.notes.getById('note'))!.content, 'Remember');
      final store = DataStore(bookRepository: db);
      await store.waitUntilLoaded();
      final library = ReaderLibrary(store: store, bookId: 'book');
      expect(library.highlights.single.selection.start, start);
      await db.activateAuthenticated('other');
      expect(library.isCurrent, isFalse);
      expect(library.highlights, isEmpty);
      expect(() => library.delete(annotation), throwsStateError);
      expect(await db.notes.getById('note'), isNull);
      await store.disposeBookRepository();
      await db.close();
      await directory.delete(recursive: true);
    });
  }
}
