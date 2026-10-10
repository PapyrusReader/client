import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:papyrus/powersync/powersync_service.dart';
import 'package:powersync/powersync.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

PapyrusPowerSyncService createDatabase(Directory root) => PapyrusPowerSyncService(
  connectorFactory: OfflineConnector.new,
  connectAuthenticated: false,
  pathResolver: (mode, profile, user) async => '${root.path}/${mode.name}-${profile ?? 'guest'}-${user ?? 'guest'}.db',
);

class OfflineConnector extends PowerSyncBackendConnector {
  @override
  Future<PowerSyncCredentials?> fetchCredentials() async => throw StateError('Smoke test must remain offline');

  @override
  Future<void> uploadData(PowerSyncDatabase database) async => throw StateError('Smoke test must remain offline');
}

Uint8List createEpub() {
  final archive = Archive();

  void add(String name, String contents) {
    final bytes = utf8.encode(contents);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  add('mimetype', 'application/epub+zip');
  add('META-INF/container.xml', '''<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
<rootfiles><rootfile full-path="content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>''');
  add('content.opf', '''<?xml version="1.0"?>
<package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="book-id">
<metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="book-id">package-smoke</dc:identifier>
<dc:title>Offline packaging book</dc:title><dc:creator>Papyrus</dc:creator><dc:language>en</dc:language></metadata>
<manifest><item id="chapter" href="chapter.xhtml" media-type="application/xhtml+xml"/>
<item id="toc" href="toc.ncx" media-type="application/x-dtbncx+xml"/></manifest>
<spine toc="toc"><itemref idref="chapter"/></spine></package>''');
  add('toc.ncx', '''<?xml version="1.0"?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
<head><meta name="dtb:uid" content="package-smoke"/></head><docTitle><text>Offline book</text></docTitle>
<navMap><navPoint id="chapter" playOrder="1"><navLabel><text>Chapter</text></navLabel>
<content src="chapter.xhtml"/></navPoint></navMap></ncx>''');
  add('chapter.xhtml', '''<html xmlns="http://www.w3.org/1999/xhtml"><head><title>Chapter</title></head><body>
${List.generate(120, (index) => '<p>Paragraph $index. Papyrus reads this book offline and preserves the reading position after reopening.</p>').join()}
</body></html>''');
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

Future<Uint8List> createPdf() async {
  final document = PdfDocument();

  try {
    for (var page = 1; page <= 3; page++) {
      document.pages.add().graphics.drawString(
        'Papyrus offline PDF page $page',
        PdfStandardFont(PdfFontFamily.helvetica, 20),
      );
    }

    document.documentInformation.title = 'Offline PDF';
    return Uint8List.fromList(await document.save());
  } finally {
    document.dispose();
  }
}
