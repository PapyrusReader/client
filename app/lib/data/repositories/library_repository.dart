import 'package:papyrus/data/repositories/book_repository.dart';
import 'package:papyrus/models/annotation.dart';
import 'package:papyrus/models/book.dart';
import 'package:papyrus/models/bookmark.dart';
import 'package:papyrus/models/book_shelf_relation.dart';
import 'package:papyrus/models/book_tag_relation.dart';
import 'package:papyrus/models/note.dart';
import 'package:papyrus/models/shelf.dart';
import 'package:papyrus/models/tag.dart';
import 'package:papyrus/models/reading_goal.dart';
import 'package:papyrus/models/reading_activity.dart';
import 'package:papyrus/models/goal_period_record.dart';

abstract interface class EntityRepository<T> {
  Future<T?> getById(String id);
  Future<void> upsert(T value, {T? previous});
  Future<void> delete(String id);
}

abstract interface class EditableBookRepository implements BookRepository {
  bool get isCurrent;
  Future<void> update(Book book, {required Book previous});
}

abstract interface class LibraryRepository {
  Stream<LibrarySnapshot> watchLibrary();
  EditableBookRepository get scopedBooks;
  EntityRepository<Shelf> get shelves;
  EntityRepository<Tag> get tags;
  EntityRepository<Note> get notes;
  EntityRepository<Annotation> get annotations;
  EntityRepository<Bookmark> get bookmarks;
  EntityRepository<BookShelfRelation> get bookShelves;
  EntityRepository<BookTagRelation> get bookTags;
  LibraryMembershipWriter get memberships;
}

abstract interface class LibraryMembershipWriter {
  Future<void> updateMemberships({
    required Set<String> bookIds,
    List<String>? shelfIds,
    List<String>? tagIds,
    Set<String>? previousShelfIds,
    Set<String>? previousTagIds,
    bool additive = false,
  });
}

class LibrarySnapshot {
  /// False while opening storage, switching profiles, or awaiting the first sync of an empty account cache.
  final bool isLoaded;
  final Object? loadError;
  final List<ReadingGoal> goals;
  final List<ReadingActivity> activities;
  final List<GoalPeriodRecord> goalPeriods;
  final List<Book> books;
  final List<Shelf> shelves;
  final List<Tag> tags;
  final List<Note> notes;
  final List<Annotation> annotations;
  final List<Bookmark> bookmarks;
  final List<BookShelfRelation> bookShelves;
  final List<BookTagRelation> bookTags;

  const LibrarySnapshot({
    this.isLoaded = true,
    this.loadError,
    this.goals = const [],
    this.activities = const [],
    this.goalPeriods = const [],
    this.books = const [],
    this.shelves = const [],
    this.tags = const [],
    this.notes = const [],
    this.annotations = const [],
    this.bookmarks = const [],
    this.bookShelves = const [],
    this.bookTags = const [],
  });

  LibrarySnapshot withLoadState({required bool isLoaded, Object? error}) => LibrarySnapshot(
    isLoaded: isLoaded,
    loadError: error,
    goals: goals,
    activities: activities,
    goalPeriods: goalPeriods,
    books: books,
    shelves: shelves,
    tags: tags,
    notes: notes,
    annotations: annotations,
    bookmarks: bookmarks,
    bookShelves: bookShelves,
    bookTags: bookTags,
  );
}
