import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

Future<String> hashBookFile(Uint8List bytes) async {
  final digest = await web.window.crypto.subtle.digest('SHA-256'.toJS, bytes.toJS).toDart;
  return (digest as JSArrayBuffer).toDart.asUint8List().map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
}
