import 'package:flutter/material.dart';
import 'package:papyrus/data/data_store.dart';
import 'package:papyrus/data/repositories/book_repository.dart';
import 'package:papyrus/data/repositories/library_repository.dart';
import 'package:papyrus/models/annotation.dart';
import 'package:papyrus/models/bookmark.dart';
import 'package:papyrus/models/note.dart';
import 'package:papyrus/widgets/book_details/annotation_dialog.dart';
import 'package:papyrus/widgets/book_details/bookmark_dialog.dart';
import 'package:papyrus/widgets/book_details/note_dialog.dart';
import 'package:papyrus_reader/papyrus_reader.dart';
import 'package:uuid/uuid.dart';

/// Captures the library that opened the book, including editors left open during a profile switch.
class ReaderLibrary {
  ReaderLibrary({required this.store, required this.bookId})
    : books = store.requireBookRepository(),
      bookmarks = store.libraryRepository?.bookmarks,
      annotations = store.libraryRepository?.annotations,
      notes = store.libraryRepository?.notes;

  final DataStore store;
  final String bookId;
  final BookRepository books;
  final EntityRepository<Bookmark>? bookmarks;
  final EntityRepository<Annotation>? annotations;
  final EntityRepository<Note>? notes;
  bool _changingBookmark = false;

  bool get isCurrent => store.isBookRepositoryCurrent(books);

  void _requireCurrent() {
    if (!isCurrent) {
      throw StateError('Your library changed. Reopen this book from the library.');
    }
  }

  List<ReaderHighlight> get highlights {
    if (!isCurrent) {
      return const [];
    }

    final result = <ReaderHighlight>[];

    for (final annotation in store.getAnnotationsForBook(bookId)) {
      final selection = annotation.location.selection;

      if (selection == null) {
        continue;
      }

      try {
        result.add(
          ReaderHighlight(
            id: annotation.id,
            selection: ReaderSelection.fromJson(selection),
            color: annotation.color.accentColor,
          ),
        );
      } on Object {
        // A malformed anchor must not prevent opening the book or viewing its annotation.
      }
    }

    return result;
  }

  BookLocation location(ReaderSnapshot snapshot, {ReaderSelection? selection}) {
    final locator = selection?.start ?? snapshot.locator!;
    final progression = switch (locator) {
      EpubReaderLocator() => locator.totalProgression,
      PdfReaderLocator() => locator.totalProgression,
    };
    String? chapterTitle;

    void findTitle(List<ReaderTocEntry> entries) {
      for (final entry in entries) {
        if (locator is EpubReaderLocator &&
            entry.locator is EpubReaderLocator &&
            (entry.locator as EpubReaderLocator).spineIndex == locator.spineIndex) {
          chapterTitle = entry.title;
        }

        findTitle(entry.children);
      }
    }

    findTitle(snapshot.toc);

    return BookLocation(
      chapter: locator is EpubReaderLocator ? locator.spineIndex + 1 : null,
      chapterTitle: chapterTitle,
      pageNumber: locator is PdfReaderLocator ? locator.pageIndex + 1 : 1,
      percentage: progression,
      readerLocator: locator.toJson(),
      selection: selection?.toJson(),
    );
  }

  Bookmark? bookmarkAt(ReaderSnapshot snapshot) {
    if (!isCurrent || snapshot.locator == null) {
      return null;
    }

    final current = snapshot.locator!;

    for (final bookmark in store.getBookmarksForBook(bookId)) {
      final anchor = bookmark.readerLocator;

      if (anchor == null) {
        continue;
      }

      final ReaderLocator saved;

      try {
        saved = ReaderLocator.fromJson(anchor);
      } on FormatException {
        continue;
      }

      if (saved is PdfReaderLocator && current is PdfReaderLocator) {
        final pageIndex = saved.pageIndex;

        if (saved.pageIndex == current.pageIndex ||
            snapshot.coverage.any((coverage) => coverage.pdfPageIndex == pageIndex)) {
          return bookmark;
        }
      } else if (saved is EpubReaderLocator && current is EpubReaderLocator && saved.spineIndex == current.spineIndex) {
        if (saved.textOffset != null && saved.textOffset == current.textOffset) {
          return bookmark;
        }

        if (saved.textOffset == null &&
            current.textOffset == null &&
            saved.localProgression == current.localProgression) {
          return bookmark;
        }

        for (final coverage in snapshot.coverage) {
          if (!coverage.key.startsWith('epub:${saved.spineIndex}:') || saved.textOffset == null) {
            continue;
          }

          final length = int.tryParse(coverage.key.split(':').last);

          if (length != null && length > 0) {
            final position = saved.textOffset! / length;

            if (position >= coverage.start && position < coverage.end) {
              return bookmark;
            }
          }
        }
      }
    }

    return null;
  }

  Future<void> addBookmark(BuildContext context, ReaderSnapshot snapshot) async {
    if (_changingBookmark || snapshot.locator == null || bookmarkAt(snapshot) != null) {
      return;
    }

    _changingBookmark = true;

    try {
      _requireCurrent();
      final at = location(snapshot);

      await store.addBookmark(
        Bookmark(
          id: const Uuid().v4(),
          bookId: bookId,
          position: at.percentage!,
          pageNumber: snapshot.locator is PdfReaderLocator ? at.pageNumber : null,
          chapterTitle: at.chapterTitle,
          readerLocator: at.readerLocator,
          createdAt: DateTime.now(),
        ),
        repository: bookmarks,
      );
    } on Object {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Could not save bookmark. Try again.')));
      }
    } finally {
      _changingBookmark = false;
    }
  }

  Future<void> toggleBookmark(BuildContext context, ReaderSnapshot snapshot) async {
    if (_changingBookmark || snapshot.locator == null) {
      return;
    }

    final bookmark = bookmarkAt(snapshot);

    if (bookmark == null) {
      await addBookmark(context, snapshot);
      return;
    }

    _changingBookmark = true;

    try {
      _requireCurrent();
      await store.deleteBookmark(bookmark.id, repository: bookmarks);
    } on Object {
      if (context.mounted && isCurrent) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(const SnackBar(content: Text('Could not remove bookmark. Try again.')));
      }
    } finally {
      _changingBookmark = false;
    }
  }

  Future<void> editBookmark(BuildContext context, Bookmark bookmark) => BookmarkDialog.show(
    context,
    bookId: bookId,
    existingBookmark: bookmark,
    onSave: (updated) {
      _requireCurrent();
      return store.updateBookmark(updated, previous: bookmark, repository: bookmarks);
    },
  );

  Future<void> annotate(BuildContext context, ReaderSnapshot snapshot, ReaderSelection selection) =>
      AnnotationDialog.show(
        context,
        bookId: bookId,
        initialText: selection.text,
        initialLocation: location(snapshot, selection: selection),
        onSave: (annotation) {
          _requireCurrent();
          return store.addAnnotation(annotation, repository: annotations);
        },
      );

  Future<void> editAnnotation(BuildContext context, Annotation annotation) => AnnotationDialog.show(
    context,
    bookId: bookId,
    existingAnnotation: annotation,
    onSave: (updated) {
      _requireCurrent();
      return store.updateAnnotation(updated, previous: annotation, repository: annotations);
    },
  );

  Future<void> editHighlight(BuildContext context, ReaderHighlight highlight) async {
    if (!isCurrent) {
      return;
    }

    final annotation = store.getAnnotation(highlight.id);

    if (annotation != null && annotation.bookId == bookId) {
      await editAnnotation(context, annotation);
    }
  }

  Future<void> removeHighlight(BuildContext context, ReaderHighlight highlight) async {
    if (!isCurrent) {
      return;
    }

    final annotation = store.getAnnotation(highlight.id);

    if (annotation == null || annotation.bookId != bookId) {
      return;
    }

    await confirmDelete(context, annotation);
  }

  Future<void> confirmDelete(BuildContext context, Object item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(item is Annotation ? 'Remove annotation?' : 'Delete this item?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(item is Annotation ? 'Remove' : 'Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    try {
      await delete(item);
    } on Object {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('Could not delete item. Try again.')));
      }
    }
  }

  Future<void> addNote(BuildContext context) => NoteDialog.show(
    context,
    bookId: bookId,
    onSave: (note) {
      _requireCurrent();
      return store.addNote(note, repository: notes);
    },
  );

  Future<void> editNote(BuildContext context, Note note) => NoteDialog.show(
    context,
    bookId: bookId,
    existingNote: note,
    onSave: (updated) {
      _requireCurrent();
      return store.updateNote(updated, previous: note, repository: notes);
    },
  );

  Future<void> delete(Object item) {
    _requireCurrent();

    return switch (item) {
      Bookmark() => store.deleteBookmark(item.id, repository: bookmarks),
      Annotation() => store.deleteAnnotation(item.id, repository: annotations),
      Note() => store.deleteNote(item.id, repository: notes),
      _ => throw ArgumentError.value(item),
    };
  }
}
