import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/providers/book_edit_provider.dart';
import 'package:papyrus/services/metadata_service.dart';

class _Request {
  final String query;
  final MetadataSource source;
  final int page;
  final bool isIsbn;
  final completer = Completer<MetadataSearchPage>();

  _Request(this.query, this.source, this.page, this.isIsbn);
}

class _MetadataService extends MetadataService {
  final requests = <_Request>[];

  @override
  Future<MetadataSearchPage> search(String query, MetadataSource source, {int page = 1}) {
    final request = _Request(query, source, page, false);
    requests.add(request);
    return request.completer.future;
  }

  @override
  Future<MetadataSearchPage> searchByIsbn(String isbn, MetadataSource source, {int page = 1}) {
    final request = _Request(isbn, source, page, true);
    requests.add(request);
    return request.completer.future;
  }
}

MetadataSearchPage _page({int count = 10, int? total = 23, String title = 'Book'}) => MetadataSearchPage(
  results: List.generate(
    count,
    (index) => BookMetadataResult(source: MetadataSource.openLibrary, title: '$title $index'),
  ),
  totalResults: total,
);

void main() {
  for (final isIsbn in [false, true]) {
    test('pages forward and backward with the original ${isIsbn ? 'ISBN' : 'text'} search', () async {
      final service = _MetadataService();
      final provider = BookEditProvider(metadataService: service);
      addTearDown(provider.dispose);
      final search = isIsbn
          ? provider.searchMetadataByIsbn('9780141439518', source: MetadataSource.googleBooks)
          : provider.searchMetadata('Alice', source: MetadataSource.googleBooks);
      service.requests.last.completer.complete(_page());
      await search;
      expect(provider.hasPreviousMetadataPage, isFalse);
      expect(provider.hasNextMetadataPage, isTrue);

      for (final page in [2, 3, 2, 1]) {
        final load = provider.loadMetadataPage(page);
        expect(provider.isFetching, isTrue);
        expect(provider.fetchedResults, isNotEmpty);
        final request = service.requests.last;
        expect(request.page, page);
        expect(request.query, isIsbn ? '9780141439518' : 'Alice');
        expect(request.isIsbn, isIsbn);
        expect(request.source, MetadataSource.googleBooks);
        request.completer.complete(_page(count: page == 3 ? 3 : 10));
        await load;
        expect(provider.metadataPage, page);
        expect(provider.metadataResultStart, (page - 1) * 10 + 1);
        expect(provider.metadataResultEnd, page == 3 ? 23 : page * 10);
        expect(provider.hasNextMetadataPage, page < 3);
      }
    });
  }

  test('failed page keeps results and supports retry without duplicate requests', () async {
    final service = _MetadataService();
    final provider = BookEditProvider(metadataService: service);
    addTearDown(provider.dispose);
    final search = provider.searchMetadata('Alice', source: MetadataSource.openLibrary);
    service.requests.last.completer.complete(_page());
    await search;
    final original = provider.fetchedResults;
    final next = provider.loadMetadataPage(2);
    await provider.loadMetadataPage(2);
    expect(service.requests, hasLength(2));
    service.requests.last.completer.completeError(Exception('offline'));
    await next;
    expect(provider.fetchedResults, same(original));
    expect(provider.metadataPage, 1);
    expect(provider.fetchState, MetadataFetchState.error);
    expect(provider.hasNextMetadataPage, isTrue);
    final retry = provider.loadMetadataPage(2);
    service.requests.last.completer.complete(_page());
    await retry;
    expect(provider.metadataPage, 2);
    expect(provider.fetchError, isNull);
  });

  test('new searches reset pages and ignore stale results and errors', () async {
    final service = _MetadataService();
    final provider = BookEditProvider(metadataService: service);
    addTearDown(provider.dispose);
    final first = provider.searchMetadata('Alice', source: MetadataSource.openLibrary);
    service.requests.last.completer.complete(_page());
    await first;
    final next = provider.loadMetadataPage(2);
    final pendingPage = service.requests.last;
    final replacement = provider.searchMetadata('Dune', source: MetadataSource.googleBooks);
    expect(provider.metadataPage, 1);
    expect(provider.fetchedResults, isEmpty);
    expect(provider.metadataTotalResults, isNull);
    pendingPage.completer.complete(_page(title: 'Old'));
    await next;
    expect(provider.isFetching, isTrue);
    expect(provider.fetchedResults, isEmpty);
    service.requests.last.completer.complete(_page(count: 2, total: 2, title: 'Dune'));
    await replacement;
    expect(provider.fetchedResults.first.title, 'Dune 0');
    final outdated = provider.searchMetadata('Old query', source: MetadataSource.openLibrary);
    final oldRequest = service.requests.last;
    final latest = provider.searchMetadata('Latest query', source: MetadataSource.googleBooks);
    service.requests.last.completer.complete(_page(count: 1, total: 1, title: 'Latest'));
    await latest;
    oldRequest.completer.completeError(Exception('old failure'));
    await outdated;
    expect(provider.fetchedResults.single.title, 'Latest 0');
    expect(provider.fetchError, isNull);
  });

  for (final total in [null, 100]) {
    test('empty next page stops pagination without losing the last results, total $total', () async {
      final service = _MetadataService();
      final provider = BookEditProvider(metadataService: service);
      addTearDown(provider.dispose);
      final search = provider.searchMetadata('Alice', source: MetadataSource.openLibrary);
      service.requests.last.completer.complete(_page(total: total));
      await search;
      final next = provider.loadMetadataPage(2);
      service.requests.last.completer.complete(_page(count: 0, total: total));
      await next;
      expect(provider.metadataPage, 1);
      expect(provider.fetchedResults, hasLength(10));
      expect(provider.hasNextMetadataPage, isFalse);
      expect(provider.metadataTotalResults, 10);
    });
  }

  for (final dispose in [false, true]) {
    test('pending results are ignored after ${dispose ? 'disposal' : 'clearing'}', () async {
      final service = _MetadataService();
      final provider = BookEditProvider(metadataService: service);
      final search = provider.searchMetadata('Alice', source: MetadataSource.openLibrary);

      if (dispose) {
        provider.dispose();
      } else {
        provider.clearFetchedResults();
        addTearDown(provider.dispose);
      }

      service.requests.last.completer.complete(_page());
      await search;
      expect(provider.fetchedResults, isEmpty);
    });
  }
}
