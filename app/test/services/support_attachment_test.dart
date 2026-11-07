import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/services/support_attachment.dart';

import '../helpers/support_file_picker.dart';

void main() {
  late SupportFilePicker picker;

  setUp(() {
    picker = SupportFilePicker();
    final previousPicker = FilePickerPlatform.instance;
    FilePickerPlatform.instance = picker;
    addTearDown(() => FilePickerPlatform.instance = previousPicker);
  });

  test('cancelling selection leaves attachments unchanged', () async {
    expect(await SupportAttachment.pick(5), isEmpty);
  });

  test('reads images and videos from streams for retryable submissions', () async {
    picker.result = [
      SupportPlatformFile(name: 'screenshot.PNG', size: 3, readStream: Stream.value([1, 2, 3])),
      SupportPlatformFile(name: 'recording.mp4', size: 2, readStream: Stream.value([4, 5])),
    ];
    final attachments = await SupportAttachment.pick(5);
    expect(attachments.first.contentType, 'image/png');
    expect(attachments.first.bytes, [1, 2, 3]);
    expect(attachments.last.isVideo, isTrue);
    expect(attachments.last.bytes, [4, 5]);
  });

  test('rejects excess count and oversized files before reading bytes', () async {
    picker.result = [SupportPlatformFile(name: 'large.png', size: SupportAttachment.maxBytes + 1)];
    await expectLater(SupportAttachment.pick(0), throwsFormatException);
    await expectLater(SupportAttachment.pick(5), throwsFormatException);
  });

  test('streams files with unknown length and still enforces the size limit', () async {
    picker.result = [
      SupportPlatformFile(name: 'photo.png', readStream: Stream.value([1, 2, 3])),
    ];
    expect((await SupportAttachment.pick(5)).single.bytes, [1, 2, 3]);

    picker.result = [
      SupportPlatformFile(
        name: 'large.png',
        readStream: Stream.value(List.filled(SupportAttachment.maxBytes + 1, 0)),
      ),
    ];

    await expectLater(SupportAttachment.pick(5), throwsFormatException);
  });

  test('rejects unsupported types, empty files, and a stream larger than declared', () async {
    for (final file in [
      SupportPlatformFile(name: 'document.pdf', size: 1),
      SupportPlatformFile(name: 'empty.png', size: 0),
      SupportPlatformFile(
        name: 'large.png',
        size: 1,
        readStream: Stream.value(List.filled(SupportAttachment.maxBytes + 1, 0)),
      ),
    ]) {
      picker.result = [file];
      await expectLater(SupportAttachment.pick(5), throwsFormatException);
    }
  });
}
