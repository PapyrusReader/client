import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

Future<String> fingerprint(Uint8List bytes) => compute(_hash, bytes);
String _hash(Uint8List bytes) => sha256.convert(bytes).toString();
