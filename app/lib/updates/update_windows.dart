import 'dart:io';
import 'dart:isolate';

import 'package:papyrus/updates/update_release.dart';

/// Runs the verified installer interactively so cancellation and errors are visible.
/// Setup owns the request to close Papyrus; starting it does not mean it installed.
Future<void> installWindowsUpdate(File installer, String installDirectory) =>
    Isolate.run(() => _runInstaller(installer, installDirectory));

Future<void> _runInstaller(File installer, String installDirectory) async {
  final process = await Process.start(
    installer.path,
    ['/SP-', '/NORESTART', '/NOFORCECLOSEAPPLICATIONS', '/DIR=$installDirectory'],
    workingDirectory: installer.parent.path,
  );

  final output = process.stdout.drain<void>();
  final errors = process.stderr.drain<void>();
  final exitCode = await process.exitCode;
  await Future.wait([output, errors]);

  if (exitCode != 0) {
    throw UpdateInstallException(
      exitCode == 2 ? 'Update cancelled.' : 'Installation failed (code $exitCode). Try again.',
    );
  }
}
