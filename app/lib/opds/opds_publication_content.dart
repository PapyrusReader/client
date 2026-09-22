import 'package:intl/intl.dart';

import 'opds_models.dart';

/// A display projection. The original catalog description remains untouched.
class OpdsPublicationContent {
  OpdsPublicationContent._(this.description, this.information, this.subjects);

  final String? description;
  final Map<String, String> information;
  final List<String> subjects;

  factory OpdsPublicationContent.from(OpdsCatalog catalog, OpdsPublication publication) {
    final information = <String, String>{};
    void add(String label, String? value) {
      if (value != null && value.trim().isNotEmpty) information[label] = value.trim();
    }

    final formats = publication.links
        .where((link) => link.isAcquisition)
        .map((link) => link.supportedExtension?.toUpperCase())
        .whereType<String>()
        .toSet();
    if (formats.isNotEmpty) add('Formats', formats.join(', '));
    if (publication.numberOfPages != null) add('Pages', '${publication.numberOfPages}');
    add('Publisher', publication.publisher);
    add('Published', _date(publication.published));
    add('ISBN', publication.isbn);
    add('Language', publication.language);
    add('Rights', publication.rights);
    final subjects = publication.subjects.where((subject) => subject.trim().isNotEmpty).toSet();
    final original = publication.description?.trim();
    final host = catalog.uri.host.toLowerCase();
    if (original == null || original.isEmpty || !(host == 'gutenberg.org' || host.endsWith('.gutenberg.org'))) {
      return OpdsPublicationContent._(original, information, subjects.toList());
    }

    // Gutenberg puts labeled records inside XHTML paragraphs. Only recognize
    // its known labels; do not infer metadata from arbitrary catalogs or prose.
    final paragraphs = original.split(RegExp(r'\n\s*\n'));
    final labeled = RegExp(r'^([^:\n]{1,30}):\s*([\s\S]+)$');
    final known = {
      'Summary',
      'Title',
      'Author',
      'Subject',
      'EBook No.',
      'Downloads',
      'Language',
      'Published',
      'Rights',
      'Publisher',
      'ISBN',
      'Reading Level',
      'LoCC',
      'Category',
    };
    final recognized = paragraphs.where((paragraph) => known.contains(labeled.firstMatch(paragraph)?[1])).length;
    if (recognized < 2) return OpdsPublicationContent._(original, information, subjects.toList());

    final summary = <String>[];
    final prose = <String>[];
    final extracted = <String, String>{};
    void extract(String label, String value) {
      extracted[label] = _combine(extracted[label], value);
    }

    for (final paragraph in paragraphs) {
      final match = labeled.firstMatch(paragraph);
      if (match == null) {
        prose.add(paragraph);
        continue;
      }
      final label = match[1]!;
      final value = match[2]!.trim();
      switch (label) {
        case 'Summary':
          summary.add(value);
        case 'Title':
          if (value != publication.title) extract('Catalog title', value);
        case 'Author':
          if (!publication.authors.contains(value)) extract('Author', value);
        case 'Subject':
          subjects.add(value);
        case 'EBook No.':
        case 'Downloads':
        case 'Language':
        case 'Published':
        case 'Rights':
        case 'Publisher':
        case 'ISBN':
        case 'Reading Level':
        case 'LoCC':
        case 'Category':
          extract(label, value);
        default:
          prose.add(paragraph);
      }
    }
    for (final entry in extracted.entries) {
      final label = switch (entry.key) {
        'EBook No.' => 'Gutenberg ID',
        'Reading Level' => 'Reading level',
        'LoCC' => 'Classification',
        _ => entry.key,
      };
      final value = label == 'Published' ? _date(entry.value)! : entry.value;
      final existing = information[label];
      if (label == 'Language' && existing != null && existing != value) {
        information[label] = '$value ($existing)';
      } else {
        information[label] = _combine(existing, value);
      }
    }
    // These category labels can also appear among Atom subjects. They now have
    // dedicated metadata rows, so avoid repeating them as subject chips.
    for (final label in ['Classification', 'Category']) {
      subjects.removeAll(information[label]?.split('\n') ?? const []);
    }
    return OpdsPublicationContent._([...summary, ...prose].join('\n\n'), information, subjects.toList());
  }

  static String _combine(String? existing, String value) => existing == null
      ? value
      : existing == value || existing.split('\n').contains(value)
      ? existing
      : '$existing\n$value';

  static String? _date(String? value) {
    if (value == null) return null;
    // Partial dates (e.g. just a year) keep their original precision.
    final date = RegExp(r'^\d{4}-\d{2}-\d{2}(?:T.*)?$').hasMatch(value) ? DateTime.tryParse(value) : null;
    return date == null ? value : DateFormat.yMMMMd().format(date);
  }
}
