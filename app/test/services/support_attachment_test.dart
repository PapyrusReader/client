import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/services/support_attachment.dart';

import '../helpers/support_file_picker.dart';

void main() {
  late SupportFilePicker picker;

  setUp(() {
    picker = SupportFilePicker();
    FilePicker.platform = picker;
  });

  test('cancelling selection leaves attachments unchanged', () async {
    expect(await SupportAttachment.pick(5), isEmpty);
  });

  test('reads images and videos from streams for retryable submissions', () async {
    picker.result = FilePickerResult([
      PlatformFile(name: 'screenshot.PNG', size: 3, readStream: Stream.value([1, 2, 3])),
      PlatformFile(name: 'recording.mp4', size: 2, readStream: Stream.value([4, 5])),
    ]);
    final attachments = await SupportAttachment.pick(5);
    expect(attachments.first.contentType, 'image/png');
    expect(attachments.first.bytes, [1, 2, 3]);
    expect(attachments.last.isVideo, isTrue);
    expect(attachments.last.bytes, [4, 5]);
  });

  test('rejects excess count and oversized files before reading bytes', () async {
    picker.result = FilePickerResult([PlatformFile(name: 'large.png', size: SupportAttachment.maxBytes + 1)]);
    await expectLater(SupportAttachment.pick(0), throwsFormatException);
    await expectLater(SupportAttachment.pick(5), throwsFormatException);
  });

  test('rejects unsupported types, empty files, and a stream larger than declared', () async {
    for (final file in [
      PlatformFile(name: 'document.pdf', size: 1),
      PlatformFile(name: 'empty.png', size: 0),
      PlatformFile(
        name: 'large.png',
        size: 1,
        readStream: Stream.value(List.filled(SupportAttachment.maxBytes + 1, 0)),
      ),
    ]) {
      picker.result = FilePickerResult([file]);
      await expectLater(SupportAttachment.pick(5), throwsFormatException);
    }
  });
}
