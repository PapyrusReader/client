import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/services/book_import_service_stub.dart';
import 'package:papyrus/services/pdf_metadata.dart';
import 'package:papyrus/widgets/add_book/book_import_controller.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

class _PdfImportPaths extends Fake with MockPlatformInterfaceMixin implements PathProviderPlatform {
  _PdfImportPaths(this.path);

  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

Future<Uint8List> _pdf({bool metadata = true}) async {
  final document = PdfDocument();

  try {
    document.pages.add();
    document.pages.add();

    if (metadata) {
      document.documentInformation.title = '  A PDF book  ';
      document.documentInformation.author = 'PDF Author';
      document.documentInformation.subject = 'A description';
    }

    return Uint8List.fromList(await document.save());
  } finally {
    document.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('PDF metadata parser reads the same fields on native and web', () async {
    final metadata = extractPdfMetadata(await _pdf());
    expect(metadata.title, 'A PDF book');
    expect(metadata.primaryAuthor, 'PDF Author');
    expect(metadata.description, 'A description');
    expect(metadata.pageCount, 2);
  });

  test('missing PDF metadata remains optional and invalid PDFs are rejected', () async {
    final metadata = extractPdfMetadata(await _pdf(metadata: false));
    expect(metadata.title, isNull);
    expect(metadata.primaryAuthor, isEmpty);
    expect(metadata.pageCount, 2);
    expect(() => extractPdfMetadata(Uint8List.fromList([1, 2, 3])), throwsA(anything));
  });

  test('native PDF import persists original bytes, metadata and filename fallback', () async {
    final root = await Directory.systemTemp.createTemp('papyrus-pdf-import-');
    final previous = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _PdfImportPaths(root.path);

    addTearDown(() async {
      PathProviderPlatform.instance = previous;
      await root.delete(recursive: true);
    });

    final service = BookImportService();
    final bytes = await _pdf();
    final imported = await service.importBook(bytes, 'book.PDF');
    expect(imported.title, 'A PDF book');
    expect(imported.author, 'PDF Author');
    expect(imported.pageCount, 2);
    expect(imported.fileExtension, 'pdf');
    expect(imported.fileHash, sha256.convert(bytes).toString());
    expect(await BookImportService().getBookFile(imported.bookId), bytes);
    final untitled = await service.importBook(await _pdf(metadata: false), 'Untitled book.pdf');
    expect(untitled.title, 'Untitled book');
    await service.deleteBookFile(imported.bookId);
    expect(await service.hasBookFile(imported.bookId), isFalse);
  });

  test('web file selection and catalog imports include PDF', () {
    expect(bookImportWebExtensions, contains('pdf'));
    expect(bookImportWebExtensions, contains('epub'));
  });

  test('web PDF worker hashes and stores bytes and reports storage failures', () async {
    final result = await Process.run('node', const [
      '-e',
      r'''
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const crypto = require('node:crypto');
const messages = [];
const writes = [];
const context = {
  self: {},
  crypto: crypto.webcrypto,
  Uint8Array,
  postMessage(message) { messages.push(message); },
};
vm.createContext(context);
vm.runInContext(fs.readFileSync('web/book_worker.js', 'utf8'), context);
context.opfsWrite = async (id, format, bytes) => writes.push({id, format, bytes});
(async () => {
  const bytes = new TextEncoder().encode('%PDF-1.7\nfixture');
  const metadata = {title: 'PDF title', author: 'PDF author', pageCount: 2};
  const data = {type: 'process', format: 'pdf', bookId: 'pdf-book', fileData: bytes.buffer, metadata};
  await context.self.onmessage({data});
  const response = messages.pop();
  assert.equal(response.type, 'success');
  assert.equal(response.action, 'process');
  assert.equal(response.bookId, data.bookId);
  assert.equal(response.metadata, metadata);
  assert.equal(response.fileSize, bytes.length);
  assert.equal(response.fileHash, crypto.createHash('sha256').update(bytes).digest('hex'));
  assert.equal(writes.length, 1);
  assert.equal(writes[0].format, 'pdf');
  assert.deepEqual(writes[0].bytes, bytes);

  await context.self.onmessage({data: {...data, metadata: {pageCount: 0}}});
  assert.equal(messages.pop().type, 'error');
  assert.equal(writes.length, 1);

  context.opfsWrite = async () => { throw new Error('storage full'); };
  await context.self.onmessage({data});
  const failure = messages.pop();
  assert.equal(failure.type, 'error');
  assert.equal(failure.action, 'process');
  assert.equal(failure.bookId, data.bookId);
  assert.equal(failure.message, 'storage full');
})().catch(error => { console.error(error); process.exitCode = 1; });
''',
    ]);

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  });
}
