import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:papyrus/updates/update_download.dart';
import 'package:papyrus/updates/update_release.dart';

void main() {
  late Directory temporary;
  late File destination;
  final bytes = [1, 2, 3, 4];
  final asset = UpdateAsset(
    name: 'update.exe',
    sha256: sha256.convert(bytes).toString(),
    uri: Uri.https('github.com', '/update'),
  );

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('papyrus-update-test');
    destination = File('${temporary.path}/update.exe');
  });
  tearDown(() => temporary.delete(recursive: true));

  test('verified bytes are retained and progress reaches completion', () async {
    final progress = <double?>[];
    await downloadUpdate(
      asset,
      destination,
      progress.add,
      client: MockClient((_) async => http.Response.bytes(bytes, 200)),
    );
    expect(await destination.readAsBytes(), bytes);
    expect(progress.last, 1);
  });

  test('corrupt and unavailable downloads leave no executable', () async {
    for (final response in [http.Response('corrupted', 200), http.Response('missing', 404)]) {
      await expectLater(
        downloadUpdate(asset, destination, (_) {}, client: MockClient((_) async => response)),
        throwsA(anything),
      );
      expect(await destination.exists(), isFalse);
    }
  });

  test('interrupted streams remove partial downloads', () async {
    final client = MockClient.streaming(
      (_, _) async => http.StreamedResponse(
        Stream<List<int>>.fromIterable([bytes]).asyncExpand((chunk) async* {
          yield chunk;
          throw const SocketException('connection lost');
        }),
        200,
      ),
    );
    await expectLater(downloadUpdate(asset, destination, (_) {}, client: client), throwsA(isA<SocketException>()));
    expect(await destination.exists(), isFalse);
  });
}
