import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/updates/update_release.dart';
import 'package:papyrus/updates/update_windows.dart';

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('papyrus setup test ');
  });

  tearDown(() async => directory.delete(recursive: true));

  test('failure to launch Setup propagates instead of claiming installation', () async {
    await expectLater(
      installWindowsUpdate(File('${directory.path}/missing.exe'), directory.path),
      throwsA(isA<ProcessException>()),
    );
  });

  final fixture = Platform.environment['PAPYRUS_TEST_INSTALLER'];

  for (final code in [0, 2, 5]) {
    test('Setup exit $code and paths with spaces cross the native process boundary', () async {
      await File('${directory.path}/exit-code').writeAsString('$code');
      final installation = installWindowsUpdate(File(fixture!), directory.path);

      if (code == 0) {
        await installation;
      } else {
        await expectLater(
          installation,
          throwsA(
            isA<UpdateInstallException>().having(
              (error) => error.message,
              'message',
              contains(code == 2 ? 'cancelled' : 'code 5'),
            ),
          ),
        );
      }

      final arguments = jsonDecode(await File('${directory.path}/arguments.json').readAsString());
      expect(arguments, ['/SP-', '/NORESTART', '/NOFORCECLOSEAPPLICATIONS', '/DIR=${directory.path}']);
    }, skip: fixture == null ? 'Compile test/fixtures/update_installer.dart and set PAPYRUS_TEST_INSTALLER.' : false);
  }
}
