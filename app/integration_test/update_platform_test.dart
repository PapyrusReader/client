import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:papyrus/updates/update_platform.dart' as platform;
import 'package:papyrus/updates/update_release.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Android selects its signing channel and rejects invalid APK handoff', (tester) async {
    const expected = String.fromEnvironment('PAPYRUS_TEST_UPDATE_CHANNEL', defaultValue: 'direct');
    expect(await platform.updateChannel(), expected == 'direct' ? UpdateChannel.apk : UpdateChannel.play);
    const bridge = MethodChannel('com.papyrus.reader/updates');
    final cache = await getTemporaryDirectory();
    final directory = await Directory('${cache.path}/papyrus-updates/contract-test').create(recursive: true);

    try {
      final invalid = await File('${directory.path}/invalid.apk').writeAsString('not an Android package');
      await expectLater(
        bridge.invokeMethod<void>('installApk', {'path': invalid.path}),
        throwsA(isA<PlatformException>()),
      );
      await expectLater(
        bridge.invokeMethod<void>('installApk', {'path': '${cache.path}/outside.apk'}),
        throwsA(isA<PlatformException>()),
      );
    } finally {
      await directory.delete(recursive: true);
    }
  });
}
