import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/services/book_download_service_platform_io.dart';

import '../helpers/support_file_picker.dart';

void main() {
  late SupportFilePicker picker;

  setUp(() {
    picker = SupportFilePicker();
    final previousPicker = FilePickerPlatform.instance;
    FilePickerPlatform.instance = picker;
    addTearDown(() => FilePickerPlatform.instance = previousPicker);
  });

  test('passes bytes to the picker and returns a local path without writing twice', () async {
    picker.savedUri = Uri.file('/unavailable/book.pdf');
    final bytes = Uint8List.fromList([1, 2, 3]);
    final result = await saveBookFileToDevice(bytes: bytes, fileName: 'book.pdf', extension: 'pdf');
    expect(result, '/unavailable/book.pdf');
    expect(picker.savedBytes, same(bytes));
    expect(picker.savedName, 'book.pdf');
  });

  test('preserves Android content URIs', () async {
    picker.savedUri = Uri.parse('content://documents/book.pdf');
    final result = await saveBookFileToDevice(
      bytes: Uint8List.fromList([1]),
      fileName: 'book.pdf',
      extension: 'pdf',
    );

    expect(result, picker.savedUri.toString());
  });

  test('returns null when the save dialog is cancelled', () async {
    final result = await saveBookFileToDevice(
      bytes: Uint8List.fromList([1]),
      fileName: 'book.pdf',
      extension: 'pdf',
    );

    expect(result, isNull);
  });
}
