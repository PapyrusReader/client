import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:papyrus/auth/token_store.dart';
import 'package:papyrus/models/book.dart';
import 'package:papyrus/services/book_import_service_stub.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'desktop_package_fixtures.dart';

Future<void> runPersistenceProbe() async {
  WidgetsFlutterBinding.ensureInitialized();
  final report = Platform.environment['PAPYRUS_SMOKE_REPORT']!;
  final phase = Platform.environment['PAPYRUS_PERSISTENCE_PHASE']!;
  final session = Platform.environment['PAPYRUS_PERSISTENCE_SESSION']!;
  var passed = false;
  var result = 'not completed';

  try {
    if (Platform.environment['RUNNER_ENVIRONMENT'] != 'github-hosted' ||
        !RegExp(r'^[a-f0-9-]{36}$').hasMatch(session) ||
        !['seed', 'verify', 'verify-and-clean'].contains(phase)) {
      throw StateError('Persistence probes require an isolated hosted runner and a unique session');
    }

    final support = await getApplicationSupportDirectory();
    final root = Directory('${support.path}/packaging-validation/$session');

    if (phase == 'seed') {
      if (await root.exists()) {
        throw StateError('Persistence fixture already exists');
      }

      await root.create(recursive: true);
    } else if (!await root.exists()) {
      throw StateError('Installer removed the application support fixture');
    }

    final database = createDatabase(root);
    final importer = BookImportService();
    final preferences = await SharedPreferences.getInstance();
    final key = 'packaging-validation-$session';
    final credentials = SecureRefreshTokenStorage.scoped(key);
    final stateFile = File('${root.path}/state.json');

    try {
      await database.activateGuest();

      if (phase == 'seed') {
        final bytes = createEpub();
        final imported = await importer.importBook(bytes, 'Installer preservation.epub');
        final book = Book(
          id: imported.bookId,
          title: imported.title,
          author: imported.author,
          addedAt: DateTime.now().toUtc(),
          fileFormat: BookFormat.epub,
          currentPage: 17,
          currentPosition: 0.25,
        );
        await database.upsert(book);
        await preferences.setString(key, 'saved-settings');
        if (Platform.isWindows) {
          await credentials.write('synthetic-test-credential');
        }

        await stateFile.writeAsString(
          jsonEncode({
            'book': (await database.getById(book.id))!.toJson(),
            'bytes': base64Encode(bytes),
          }),
        );
      } else {
        final state = jsonDecode(await stateFile.readAsString()) as Map<String, dynamic>;
        final expected = Book.fromJson(state['book'] as Map<String, dynamic>);
        final stored = await database.getById(expected.id);

        if (stored == null || jsonEncode(stored.toJson()) != jsonEncode(state['book'])) {
          throw StateError('Installer changed the persisted library or reading position');
        }

        if (!listEquals(await importer.getBookFile(expected.id), base64Decode(state['bytes'] as String))) {
          throw StateError('Installer changed imported book bytes');
        }

        if (preferences.getString(key) != 'saved-settings') {
          throw StateError('Installer changed saved preferences');
        }

        if (Platform.isWindows && await credentials.read() != 'synthetic-test-credential') {
          throw StateError('Installer changed the stored credential');
        }

        if (phase == 'verify-and-clean') {
          await importer.deleteBookFile(expected.id);
          await preferences.remove(key);
          if (Platform.isWindows) {
            await credentials.delete();
          }
        }
      }
    } finally {
      await database.close();
    }

    if (phase == 'verify-and-clean') {
      await root.delete(recursive: true);
    }

    passed = true;
    result = 'success';
  } catch (error, stack) {
    result = error.toString();
    stderr.writeln('$error\n$stack');
  }

  await File(report).writeAsString(
    jsonEncode({
      'passed': passed,
      'platform': Platform.operatingSystem,
      'credential_check': Platform.isWindows,
      'results': {'persistence-$phase': result},
    }),
  );
  exit(passed ? 0 : 1);
}
