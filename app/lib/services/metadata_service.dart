import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:papyrus/auth/auth_api_client.dart';
import 'package:papyrus/auth/papyrus_api_config.dart';

/// Source for fetching book metadata.
enum MetadataSource { openLibrary, googleBooks }

/// Result from a metadata search.
class BookMetadataResult {
  final MetadataSource source;
  final String? title;
  final String? subtitle;
  final List<String>? authors;
  final String? publisher;
  final String? publishedDate;
  final String? description;
  final String? coverUrl;
  final String? language;
  final String? isbn;
  final String? isbn13;
  final int? pageCount;

  const BookMetadataResult({
    required this.source,
    this.title,
    this.subtitle,
    this.authors,
    this.publisher,
    this.publishedDate,
    this.description,
    this.coverUrl,
    this.language,
    this.isbn,
    this.isbn13,
    this.pageCount,
  });

  /// Get the primary author or empty string.
  String get primaryAuthor => authors?.isNotEmpty == true ? authors!.first : '';

  /// Get co-authors (all authors except the first).
  List<String> get coAuthors => authors != null && authors!.length > 1 ? authors!.sublist(1) : [];

  /// Source display name.
  String get sourceLabel {
    switch (source) {
      case MetadataSource.openLibrary:
        return 'Open Library';
      case MetadataSource.googleBooks:
        return 'Google Books';
    }
  }
}

class MetadataSearchPage {
  final List<BookMetadataResult> results;
  final int? totalResults;

  const MetadataSearchPage({required this.results, this.totalResults});
}

class MetadataSearchException implements Exception {
  const MetadataSearchException(this.message);

  final String message;

  @override
  String toString() => message;
}

typedef MetadataAuthorization = Future<http.Response> Function(Future<http.Response> Function(String token) request);

class MetadataServer {
  const MetadataServer({required this.config, this.authorize});

  final PapyrusApiConfig config;
  final MetadataAuthorization? authorize;
}

/// Service for fetching book metadata from external APIs.
class MetadataService {
  static const pageSize = 10;
  final http.Client _client;
  final MetadataServer Function() _server;

  MetadataService({http.Client? client, MetadataServer Function()? server})
    : _client = client ?? http.Client(),
      _server = server ?? (() => MetadataServer(config: PapyrusApiConfig.fromEnvironment()));

  void close() => _client.close();

  static String _openLibraryCoverUrl(Object coverId) {
    return 'https://covers.openlibrary.org/b/id/$coverId-L.jpg';
  }

  Future<MetadataSearchPage> search(String query, MetadataSource source, {int page = 1}) {
    return _search(query.trim(), source, page: page, isIsbn: false);
  }

  Future<MetadataSearchPage> searchByIsbn(String isbn, MetadataSource source, {int page = 1}) {
    return _search(isbn.replaceAll(RegExp(r'[-\s]'), ''), source, page: page, isIsbn: true);
  }

  Future<MetadataSearchPage> _search(
    String query,
    MetadataSource source, {
    required int page,
    required bool isIsbn,
  }) async {
    if (page < 1) {
      throw RangeError.range(page, 1, null, 'page');
    }

    if (query.isEmpty) {
      return const MetadataSearchPage(results: [], totalResults: 0);
    }

    if (source == MetadataSource.googleBooks) {
      return _searchGoogleBooks(query, page: page, isIsbn: isIsbn);
    }

    final uri = Uri.https('openlibrary.org', '/search.json', {
      isIsbn ? 'isbn' : 'q': query,
      'limit': '$pageSize',
      'offset': '${(page - 1) * pageSize}',
    });

    final response = await _client.get(uri).timeout(const Duration(seconds: 20));

    if (response.statusCode != 200) {
      throw http.ClientException('Metadata search failed (${response.statusCode})', uri);
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final items = data['docs'] as List<dynamic>? ?? [];
    final count = data['numFound'] ?? data['num_found'];
    final results = items.map((item) => _parseOpenLibraryDoc(item as Map<String, dynamic>)).toList();
    return MetadataSearchPage(results: results, totalResults: count is int && count >= 0 ? count : null);
  }

  Future<MetadataSearchPage> _searchGoogleBooks(String query, {required int page, required bool isIsbn}) async {
    final server = _server();
    final authorize = server.authorize;
    final path = authorize == null ? '/metadata/google-books' : '/metadata/google-books/authenticated';
    final uri = server.config.endpoint(path, {'q': query, 'page': '$page', 'isbn': '$isIsbn'});

    Future<http.Response> request(String token) async {
      final response = await _client.get(uri, headers: {'Authorization': 'Bearer $token'});

      if (response.statusCode == 401) {
        throw const AuthApiException(statusCode: 401, message: 'Sign in again to search Google Books.');
      }

      return response;
    }

    final response = await (authorize == null ? _client.get(uri) : authorize(request)).timeout(
      const Duration(seconds: 20),
    );

    if (response.statusCode != 200) {
      final message = switch (response.statusCode) {
        429 => 'Too many metadata searches. Please try again later.',
        503 => 'Google Books is unavailable on this server. Try Open Library or retry later.',
        404 => 'This server does not support Google Books searches yet. Try Open Library.',
        401 || 403 => 'Sign in again to search Google Books.',
        _ => 'Could not fetch Google Books metadata. Please try again.',
      };

      throw MetadataSearchException(message);
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final items = data['results'] as List<dynamic>;

    return MetadataSearchPage(
      results: items.map((item) => _parseGoogleBooksResult(item as Map<String, dynamic>)).toList(),
      totalResults: data['total_results'] as int?,
    );
  }

  BookMetadataResult _parseOpenLibraryDoc(Map<String, dynamic> document) {
    String? coverUrl;
    final coverId = document['cover_i'];

    if (coverId != null) {
      coverUrl = _openLibraryCoverUrl(coverId);
    }

    final isbns = document['isbn'] as List<dynamic>?;
    String? isbn;
    String? isbn13;

    if (isbns != null && isbns.isNotEmpty) {
      for (final identifier in isbns) {
        final isbnValue = identifier.toString();

        if (isbnValue.length == 10 && isbn == null) {
          isbn = isbnValue;
        } else if (isbnValue.length == 13 && isbn13 == null) {
          isbn13 = isbnValue;
        }
      }
    }

    return BookMetadataResult(
      source: MetadataSource.openLibrary,
      title: document['title'] as String?,
      subtitle: document['subtitle'] as String?,
      authors: (document['author_name'] as List<dynamic>?)?.cast<String>(),
      publisher: (document['publisher'] as List<dynamic>?)?.firstOrNull as String?,
      publishedDate: document['first_publish_year']?.toString(),
      description: null, // Open Library search doesn't include description
      coverUrl: coverUrl,
      language: (document['language'] as List<dynamic>?)?.firstOrNull as String?,
      isbn: isbn,
      isbn13: isbn13,
      pageCount: document['number_of_pages_median'] as int?,
    );
  }

  BookMetadataResult _parseGoogleBooksResult(Map<String, dynamic> item) {
    return BookMetadataResult(
      source: MetadataSource.googleBooks,
      title: item['title'] as String?,
      subtitle: item['subtitle'] as String?,
      authors: (item['authors'] as List<dynamic>?)?.cast<String>(),
      publisher: item['publisher'] as String?,
      publishedDate: item['published_date'] as String?,
      description: item['description'] as String?,
      coverUrl: item['cover_url'] as String?,
      language: item['language'] as String?,
      isbn: item['isbn'] as String?,
      isbn13: item['isbn13'] as String?,
      pageCount: item['page_count'] as int?,
    );
  }
}
