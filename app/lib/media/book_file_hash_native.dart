import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

Future<String> hashBookFile(Uint8List bytes) => compute(_hash, bytes, debugLabel: 'book-file-integrity');

String _hash(Uint8List bytes) => sha256.convert(bytes).toString();
