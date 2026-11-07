import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

class SupportFilePicker extends FilePickerPlatform {
  List<PlatformFile> result = [];

  Uri? savedUri;
  Uint8List? savedBytes;
  String? savedName;

  @override
  Future<Uri?> saveFile({
    required String fileName,
    required Uint8List bytes,
    String mimeType = 'application/octet-stream',
    String? dialogTitle,
    String? initialDirectory,
    Function(FilePickerStatus)? onFileSaving,
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    savedBytes = bytes;
    savedName = fileName;
    return savedUri;
  }

  @override
  Future<List<PlatformFile>> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async => result;

  @override
  Future<PlatformFile?> pickFile({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async => result.firstOrNull;
}

final class SupportPlatformFile extends PlatformFile {
  SupportPlatformFile({required this.name, this.size, this.bytes, this.readStream});

  @override
  final String name;
  final int? size;
  final Uint8List? bytes;
  final Stream<List<int>>? readStream;

  @override
  int? lengthSync() => size;

  @override
  Future<int?> length() async => size;

  @override
  Future<Uint8List> readAsBytes() async {
    if (bytes != null) {
      return bytes!;
    }

    final builder = BytesBuilder(copy: false);

    await for (final chunk in readAsByteStream()) {
      builder.add(chunk);
    }

    return builder.takeBytes();
  }

  @override
  Stream<Uint8List> readAsByteStream() {
    if (readStream != null) {
      return readStream!.map(Uint8List.fromList);
    }

    if (bytes != null) {
      return Stream.value(bytes!);
    }

    return Stream.error(const FormatException('Could not read the selected file.'));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
