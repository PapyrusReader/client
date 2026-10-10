import 'dart:typed_data';

/// Result of extracting metadata from a book file.
class FileMetadataResult {
  final String? title;
  final String? subtitle;
  final List<String>? authors;
  final String? publisher;
  final String? publishedDate;
  final String? description;
  final String? language;
  final String? isbn;
  final String? isbn13;
  final int? pageCount;
  final Uint8List? coverImageBytes;
  final String? coverImageMimeType;
  final List<String> warnings;

  const FileMetadataResult({
    this.title,
    this.subtitle,
    this.authors,
    this.publisher,
    this.publishedDate,
    this.description,
    this.language,
    this.isbn,
    this.isbn13,
    this.pageCount,
    this.coverImageBytes,
    this.coverImageMimeType,
    this.warnings = const [],
  });

  /// Get the primary author or empty string.
  String get primaryAuthor => authors?.isNotEmpty == true ? authors!.first : '';

  /// Get co-authors (all authors except the first).
  List<String> get coAuthors => authors != null && authors!.length > 1 ? authors!.sublist(1) : [];
}
