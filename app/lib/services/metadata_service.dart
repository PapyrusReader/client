import 'dart:convert';
import 'package:http/http.dart' as http;

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

/// Service for fetching book metadata from external APIs.
class MetadataService {
  final http.Client _client;

  MetadataService({http.Client? client}) : _client = client ?? http.Client();

  static Uri _openLibrarySearchUri(String query, {int limit = 10}) {
    return Uri.parse('https://openlibrary.org/search.json?q=${Uri.encodeComponent(query)}&limit=$limit');
  }

  static Uri _openLibraryIsbnUri(String isbn, {int limit = 5}) {
    return Uri.parse('https://openlibrary.org/search.json?isbn=$isbn&limit=$limit');
  }

  static Uri _googleBooksSearchUri(String query, {int limit = 10}) {
    return Uri.parse('https://www.googleapis.com/books/v1/volumes?q=${Uri.encodeComponent(query)}&maxResults=$limit');
  }

  static Uri _googleBooksIsbnUri(String isbn, {int limit = 5}) {
    return Uri.parse('https://www.googleapis.com/books/v1/volumes?q=isbn:$isbn&maxResults=$limit');
  }

  static String _openLibraryCoverUrl(Object coverId) {
    return 'https://covers.openlibrary.org/b/id/$coverId-L.jpg';
  }

  /// Search for books by query (title, author, or general search).
  Future<List<BookMetadataResult>> search(String query, MetadataSource source) async {
    if (query.trim().isEmpty) {
      return [];
    }

    switch (source) {
      case MetadataSource.openLibrary:
        return _searchOpenLibrary(query);
      case MetadataSource.googleBooks:
        return _searchGoogleBooks(query);
    }
  }

  /// Search for a book by ISBN.
  Future<List<BookMetadataResult>> searchByIsbn(String isbn, MetadataSource source) async {
    final cleanIsbn = isbn.replaceAll(RegExp(r'[-\s]'), '');

    if (cleanIsbn.isEmpty) {
      return [];
    }

    switch (source) {
      case MetadataSource.openLibrary:
        return _searchOpenLibraryByIsbn(cleanIsbn);
      case MetadataSource.googleBooks:
        return _searchGoogleBooksByIsbn(cleanIsbn);
    }
  }

  Future<List<BookMetadataResult>> _searchOpenLibrary(String query) async {
    try {
      final uri = _openLibrarySearchUri(query);
      final response = await _client.get(uri);

      if (response.statusCode != 200) {
        return [];
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final docs = data['docs'] as List<dynamic>? ?? [];
      return docs.map((document) => _parseOpenLibraryDoc(document)).toList();
    } catch (error) {
      return [];
    }
  }

  Future<List<BookMetadataResult>> _searchOpenLibraryByIsbn(String isbn) async {
    try {
      final uri = _openLibraryIsbnUri(isbn);
      final response = await _client.get(uri);

      if (response.statusCode != 200) {
        return [];
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final docs = data['docs'] as List<dynamic>? ?? [];
      return docs.map((document) => _parseOpenLibraryDoc(document)).toList();
    } catch (error) {
      return [];
    }
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

  Future<List<BookMetadataResult>> _searchGoogleBooks(String query) async {
    try {
      final uri = _googleBooksSearchUri(query);
      final response = await _client.get(uri);

      if (response.statusCode != 200) {
        return [];
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final items = data['items'] as List<dynamic>? ?? [];
      return items.map((item) => _parseGoogleBooksItem(item)).toList();
    } catch (error) {
      return [];
    }
  }

  Future<List<BookMetadataResult>> _searchGoogleBooksByIsbn(String isbn) async {
    try {
      final uri = _googleBooksIsbnUri(isbn);
      final response = await _client.get(uri);

      if (response.statusCode != 200) {
        return [];
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final items = data['items'] as List<dynamic>? ?? [];
      return items.map((item) => _parseGoogleBooksItem(item)).toList();
    } catch (error) {
      return [];
    }
  }

  BookMetadataResult _parseGoogleBooksItem(Map<String, dynamic> item) {
    final volumeInfo = item['volumeInfo'] as Map<String, dynamic>? ?? {};
    String? coverUrl;
    final imageLinks = volumeInfo['imageLinks'] as Map<String, dynamic>?;

    if (imageLinks != null) {
      coverUrl =
          imageLinks['large'] as String? ?? imageLinks['medium'] as String? ?? imageLinks['thumbnail'] as String?;
      coverUrl = coverUrl?.replaceFirst('http://', 'https://');
    }

    String? isbn;
    String? isbn13;
    final identifiers = volumeInfo['industryIdentifiers'] as List<dynamic>? ?? [];

    for (final id in identifiers) {
      final type = id['type'] as String?;
      final identifier = id['identifier'] as String?;

      if (type == 'ISBN_10') {
        isbn = identifier;
      } else if (type == 'ISBN_13') {
        isbn13 = identifier;
      }
    }

    return BookMetadataResult(
      source: MetadataSource.googleBooks,
      title: volumeInfo['title'] as String?,
      subtitle: volumeInfo['subtitle'] as String?,
      authors: (volumeInfo['authors'] as List<dynamic>?)?.cast<String>(),
      publisher: volumeInfo['publisher'] as String?,
      publishedDate: volumeInfo['publishedDate'] as String?,
      description: volumeInfo['description'] as String?,
      coverUrl: coverUrl,
      language: volumeInfo['language'] as String?,
      isbn: isbn,
      isbn13: isbn13,
      pageCount: volumeInfo['pageCount'] as int?,
    );
  }
}
