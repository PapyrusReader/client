import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/models/book.dart';
import 'package:papyrus/powersync/powersync_book_mapper.dart';

void main() {
  test('maps Book to synced row without file path or embedded cover bytes', () {
    final book = Book(
      id: '11111111-1111-1111-1111-111111111111',
      title: 'Synced Book',
      author: 'Author',
      coAuthors: const ['Co Author'],
      coverUrl: 'data:image/png;base64,abc',
      filePath: '/local/book.epub',
      fileFormat: BookFormat.epub,
      fileSize: 1024,
      fileHash: 'hash',
      isPhysical: true,
      physicalLocation: 'Shelf',
      readingStatus: ReadingStatus.inProgress,
      currentPosition: 0.4,
      isFavorite: true,
      addedAt: DateTime.parse('2026-05-09T12:00:00Z'),
    );

    final row = PowerSyncBookMapper.toRow(book);
    final metadata = jsonDecode(row['custom_metadata']! as String) as Map<String, dynamic>;

    expect(row['cover_image_url'], isNull);
    expect(row.containsKey('file_path'), isFalse);
    expect(row['co_authors'], jsonEncode(['Co Author']));
    expect(row['reading_status'], 'inProgress');
    expect(row['is_favorite'], 1);
    expect(metadata['file_format'], 'epub');
    expect(metadata['file_size'], 1024);
    expect(metadata['file_hash'], 'hash');
    expect(metadata['is_physical'], true);
    expect(metadata['physical_location'], 'Shelf');
  });

  test('maps synced row to Book', () {
    final book = PowerSyncBookMapper.fromRow({
      'id': '11111111-1111-1111-1111-111111111111',
      'title': 'Synced Book',
      'author': 'Author',
      'co_authors': jsonEncode(['Co Author']),
      'reading_status': 'in_progress',
      'current_position': 0.5,
      'is_favorite': 1,
      'custom_metadata': jsonEncode({'file_format': 'epub', 'is_physical': false}),
      'added_at': '2026-05-09T12:00:00Z',
    });

    expect(book.title, 'Synced Book');
    expect(book.coAuthors, ['Co Author']);
    expect(book.readingStatus, ReadingStatus.inProgress);
    expect(book.currentPosition, 0.5);
    expect(book.isFavorite, isTrue);
    expect(book.fileFormat, BookFormat.epub);
  });
}
