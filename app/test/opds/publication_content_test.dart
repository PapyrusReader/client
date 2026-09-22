import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/opds/opds_models.dart';
import 'package:papyrus/opds/opds_parser.dart';
import 'package:papyrus/opds/opds_publication_content.dart';

void main() {
  final gutenberg = OpdsCatalog(
    id: 'g',
    name: 'Renamed catalog',
    uri: Uri.parse('https://www.gutenberg.org/ebooks.opds'),
  );
  const description = '''This edition has images.

Title: A book

Summary: A story about a reader.

Author: Writer, A., 1800–1850

Language: English

Subject: Fiction

Subject: Fiction

Published: Oct 1, 1994

Downloads: 123

EBook No.: 174

Credits: Someone helpful.

Note: https://example.test/a-very-long-link

Unfamiliar field: Preserve this.

Another paragraph of prose.''';

  test('Gutenberg presentation separates summary and keeps all extra information', () {
    final publication = OpdsPublication(
      id: '174',
      title: 'A book',
      authors: ['Writer, A.'],
      description: description,
      language: 'en',
      subjects: ['Fiction'],
    );
    final content = OpdsPublicationContent.from(gutenberg, publication);
    expect(content.description, startsWith('A story about a reader.\n\nThis edition has images.'));
    expect(content.description, endsWith('Another paragraph of prose.'));
    expect(content.information['Language'], 'English (en)');
    expect(content.information['Gutenberg ID'], '174');
    expect(content.information['Downloads'], '123');
    expect(content.information['Published'], 'Oct 1, 1994');
    expect(content.subjects, ['Fiction']);
    expect(content.description, contains('Credits: Someone helpful.'));
    expect(content.information['Author'], 'Writer, A., 1800–1850');
    expect(content.description, contains('Unfamiliar field: Preserve this.'));
    expect(content.description, contains('https://example.test/a-very-long-link'));
    expect(content.description, isNot(contains('Title: A book')));
    expect(publication.description, description);
  });

  test('other catalogs and unrecognized Gutenberg prose remain unchanged', () {
    for (final host in ['books.test', 'gutenberg.org.example.test']) {
      final catalog = OpdsCatalog(id: 'other', name: 'Project Gutenberg', uri: Uri.parse('https://$host/feed'));
      final result = OpdsPublicationContent.from(
        catalog,
        OpdsPublication(id: '1', title: 'A book', description: description),
      );
      expect(result.description, description);
    }
    const prose = 'Summary: A single ordinary paragraph.\n\nNothing to extract.';
    expect(
      OpdsPublicationContent.from(gutenberg, OpdsPublication(id: '1', title: 'Book', description: prose)).description,
      prose,
    );
  });

  test('conflicting or repeated metadata is preserved in its information row', () {
    final result = OpdsPublicationContent.from(
      gutenberg,
      OpdsPublication(
        id: '1',
        title: 'Book',
        publisher: 'Structured publisher',
        description:
            'Title: Another title\n\nPublisher: First publisher\n\nPublisher: Second publisher\n\nSummary: Story.',
      ),
    );
    expect(result.information['Publisher'], 'Structured publisher\nFirst publisher\nSecond publisher');
    expect(result.information['Catalog title'], 'Another title');
    expect(result.description, 'Story.');
  });

  test('reading level and classification belong to information rather than subject chips', () {
    final result = OpdsPublicationContent.from(
      gutenberg,
      OpdsPublication(
        id: '1',
        title: 'Book',
        subjects: ['Fiction', 'English literature', 'Text'],
        description:
            'Summary: Story.\n\nReading Level: Reading ease score: 84.0\n\nLoCC: English literature\n\nCategory: Text',
      ),
    );
    expect(result.information['Reading level'], 'Reading ease score: 84.0');
    expect(result.information['Classification'], 'English literature');
    expect(result.information['Category'], 'Text');
    expect(result.subjects, ['Fiction']);
    expect(result.description, 'Story.');
  });

  test('Atom metadata retains subjects and rights without confusing entry timestamps with publication dates', () {
    final publication = OpdsParser.parse('''
      <entry xmlns="http://www.w3.org/2005/Atom" xmlns:dc="http://purl.org/dc/terms/">
        <id>book</id><title>Book</title><published>2026-09-23T00:00:00Z</published>
        <dc:issued>1900</dc:issued><rights>Public domain</rights>
        <category term="fiction" label="Fiction"/><category term="Fiction"/>
        <category term="History"/><category term=""/>
      </entry>''', gutenberg.uri).publications.single;
    expect(publication.published, '1900');
    expect(publication.rights, 'Public domain');
    expect(publication.subjects, ['Fiction', 'History']);
    final onlyTimestamp = OpdsParser.parse('''
      <entry xmlns="http://www.w3.org/2005/Atom"><title>Book</title><published>2026-09-23</published></entry>
      ''', gutenberg.uri).publications.single;
    expect(onlyTimestamp.published, isNull);
  });

  test('JSON publication metadata accepts string and named subjects and positive page counts', () {
    final publication = OpdsParser.parse(
      jsonEncode({
        'metadata': {'title': 'Catalog'},
        'publications': [
          {
            'metadata': {
              'title': 'Book',
              'published': '1900-06-01',
              'numberOfPages': 240,
              'subject': [
                'Fiction',
                {'name': 'History'},
                {'name': 'Fiction'},
              ],
            },
          },
        ],
      }),
      gutenberg.uri,
    ).publications.single;
    expect(publication.numberOfPages, 240);
    expect(publication.subjects, ['Fiction', 'History']);
    expect(OpdsPublicationContent.from(gutenberg, publication).information['Published'], 'June 1, 1900');
  });

  test('missing metadata produces no empty rows or invented values', () {
    final result = OpdsPublicationContent.from(gutenberg, OpdsPublication(id: 'empty', title: 'Book', publisher: '  '));
    expect(result.information, isEmpty);
    expect(result.subjects, isEmpty);
    expect(result.description, isNull);
  });
}
