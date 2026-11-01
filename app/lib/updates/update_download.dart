import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:papyrus/updates/update_release.dart';

// Release metadata and bytes are authenticated by HTTPS to the fixed Papyrus
// GitHub repository. Hashes bind downloaded bytes to that release's manifest.
Future<void> downloadUpdate(
  UpdateAsset asset,
  File destination,
  void Function(double?) progress, {
  http.Client? client,
}) async {
  final transport = client ?? http.Client();
  IOSink? sink;
  const maximumBytes = 2 * 1024 * 1024 * 1024;

  try {
    final response = await transport.send(http.Request('GET', asset.uri)).timeout(const Duration(seconds: 30));

    if (response.statusCode != 200 || (response.contentLength ?? 0) > maximumBytes) {
      throw const HttpException('Update download is unavailable');
    }

    sink = destination.openWrite();
    var received = 0;
    final total = response.contentLength;

    await sink.addStream(
      response.stream.timeout(const Duration(seconds: 30)).map((bytes) {
        received += bytes.length;

        if (received > maximumBytes) {
          throw const HttpException('Update exceeds download limit');
        }

        progress(total == null || total == 0 ? null : received / total);
        return bytes;
      }),
    );

    await sink.flush();
    await sink.close();
    sink = null;

    if (received == 0 || (total != null && received != total)) {
      throw const HttpException('Incomplete update download');
    }

    final digest = await sha256.bind(destination.openRead()).first;

    if (digest.toString() != asset.sha256) {
      throw const FormatException('Update checksum mismatch');
    }
  } catch (_) {
    try {
      await sink?.close();
    } catch (_) {
      // addStream can close the sink itself when the network stream fails.
    }

    if (await destination.exists()) {
      await destination.delete();
    }

    rethrow;
  } finally {
    if (client == null) {
      transport.close();
    }
  }
}
