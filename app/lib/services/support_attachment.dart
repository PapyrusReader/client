import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

class SupportAttachment {
  const SupportAttachment({required this.name, required this.bytes, required this.contentType});

  static const maxCount = 5;
  static const maxBytes = 10 * 1024 * 1024;
  static const mediaTypes = {
    'png': 'image/png',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'gif': 'image/gif',
    'webp': 'image/webp',
    'mp4': 'video/mp4',
    'mov': 'video/quicktime',
    'webm': 'video/webm',
  };

  final String name;
  final Uint8List bytes;
  final String contentType;

  bool get isVideo => contentType.startsWith('video/');
  String get sizeLabel {
    if (bytes.length < 1024) {
      return '${bytes.length} B';
    }

    if (bytes.length < 1024 * 1024) {
      return '${(bytes.length / 1024).toStringAsFixed(1)} KB';
    }

    return '${(bytes.length / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  static Future<List<SupportAttachment>> pick(int remaining) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: mediaTypes.keys.toList(),
      allowMultiple: true,
      allowCompression: false,
      withData: false,
      withReadStream: true,
    );

    if (result == null) {
      return [];
    }

    if (result.files.length > remaining) {
      throw const FormatException('Attach up to five files.');
    }

    final attachments = <SupportAttachment>[];

    for (final file in result.files) {
      final contentType = mediaTypes[file.extension?.toLowerCase()];

      if (contentType == null) {
        throw const FormatException('Choose a PNG, JPG, GIF, WebP, MP4, MOV, or WebM file.');
      }

      if (file.size <= 0 || file.size > maxBytes) {
        throw const FormatException('Each attachment must be no larger than 10 MB and cannot be empty.');
      }

      final builder = BytesBuilder(copy: false);
      final stream = file.readStream;

      if (stream != null) {
        await for (final chunk in stream) {
          if (builder.length + chunk.length > maxBytes) {
            throw const FormatException('Each attachment must be no larger than 10 MB.');
          }

          builder.add(chunk);
        }
      } else if (file.bytes != null) {
        builder.add(file.bytes!);
      } else {
        throw const FormatException('Could not read the selected file.');
      }

      if (builder.isEmpty || builder.length > maxBytes) {
        throw const FormatException('Each attachment must be no larger than 10 MB and cannot be empty.');
      }

      attachments.add(SupportAttachment(name: file.name, bytes: builder.takeBytes(), contentType: contentType));
    }

    return attachments;
  }
}
