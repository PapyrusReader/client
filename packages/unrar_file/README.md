# unrar_file

flutter wrapper around [junrar](https://github.com/junrar/junrar) library for extracting RAR files.

It additionally supports **RAR5** which junrar don't.




## Usage

```dart
  Future<void> extract_file(input_file_path,destination_path, {password=""}) async {
    // Extraction may fail, so we use a try/catch PlatformException.
    try {
      await UnrarFile.extract_rar(input_file_path,  destination_path, password: password);
    } catch(e) {
      print("extraction failed $e");
    }
    return;
  }

```

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://flutter.dev/docs/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://flutter.dev/docs/cookbook)

For help getting started with Flutter, view our
[online documentation](https://flutter.dev/docs), which offers tutorials,
samples, guidance on mobile development, and a full API reference.


## Contributing
Pull requests are welcome. For major changes, please open an issue first to discuss what you would like to change.


## License
[Apache-2.0 License](https://github.com/syedecryptr/unrar_file/blob/master/LICENSE)
