import 'dart:typed_data';

import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:papyrus/services/file_metadata_result.dart';

/// Reads PDF metadata on native and web platforms, releasing parser resources.
FileMetadataResult extractPdfMetadata(Uint8List bytes) {
  final warnings = <String>[];
  final document = PdfDocument(inputBytes: bytes);

  try {
    final info = document.documentInformation;

    String? title;

    try {
      final titleValue = info.title.trim();

      if (titleValue.isNotEmpty) {
        title = titleValue;
      }
    } catch (error) {
      warnings.add('Could not read PDF title: $error');
    }

    List<String>? authors;

    try {
      final authorValue = info.author.trim();

      if (authorValue.isNotEmpty) {
        authors = [authorValue];
      }
    } catch (error) {
      warnings.add('Could not read PDF author: $error');
    }

    String? description;

    try {
      final subject = info.subject.trim();

      if (subject.isNotEmpty) {
        description = subject;
      }
    } catch (error) {
      warnings.add('Could not read PDF subject: $error');
    }

    int? pageCount;

    try {
      pageCount = document.pages.count;
    } catch (error) {
      warnings.add('Could not read PDF page count: $error');
    }

    String? publishedDate;

    try {
      final date = info.creationDate;
      publishedDate = date.toIso8601String().split('T').first;
    } catch (_) {
      // creationDate may not be set
    }

    return FileMetadataResult(
      title: title,
      authors: authors,
      description: description,
      pageCount: pageCount,
      publishedDate: publishedDate,
      warnings: warnings,
    );
  } finally {
    document.dispose();
  }
}
