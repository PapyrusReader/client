import 'package:powersync/powersync.dart';

const papyrusPowerSyncSchema = Schema([
  Table(
    'books',
    [
      Column.text('owner_user_id'),
      Column.text('title'),
      Column.text('subtitle'),
      Column.text('author'),
      Column.text('co_authors'),
      Column.text('isbn'),
      Column.text('isbn13'),
      Column.text('publisher'),
      Column.text('language'),
      Column.integer('page_count'),
      Column.text('description'),
      Column.text('cover_image_url'),
      Column.text('reading_status'),
      Column.integer('current_page'),
      Column.real('current_position'),
      Column.text('current_cfi'),
      Column.integer('is_favorite'),
      Column.integer('rating'),
      Column.text('custom_metadata'),
      Column.text('added_at'),
      Column.text('updated_at'),
    ],
    indexes: [
      Index('books_added_at', [IndexedColumn('added_at')]),
      Index('books_title', [IndexedColumn('title')]),
    ],
  ),
]);
