import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/folders/directory_access.dart';
import 'package:papyrus/folders/directory_access_native.dart';
import 'package:path/path.dart' as path;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late FolderGrant grant;
  final access = NativeDirectoryAccess(platform: Platform.isWindows ? TargetPlatform.windows : TargetPlatform.linux);

  setUp(() async {
    root = await Directory.systemTemp.createTemp('papyrus-folder-access-');
    // macOS temp locations may contain a parent symlink, unlike picker grants.
    root = Directory(await root.resolveSymbolicLinks());
    grant = FolderGrant(key: root.path, identity: root.path, name: 'Books', location: root.path);
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  test(
    'filesystem scans recurse only when requested and omit hidden and temporary entries',
    () async {
      await File('${root.path}/book.epub').writeAsBytes([1]);
      await Directory('${root.path}/nested').create();
      await File('${root.path}/nested/later.pdf').writeAsBytes([2, 3]);
      await Directory('${root.path}/.hidden').create();
      await File('${root.path}/.hidden/hidden.epub').writeAsBytes([4]);
      await File('${root.path}/unfinished.pdf.part').writeAsBytes([5]);

      final recursive = await access.enumerate(grant, recursive: true).toList();
      expect(recursive.map((file) => file.key), unorderedEquals(['book.epub', path.join('nested', 'later.pdf')]));
      final shallow = await access.enumerate(grant, recursive: false).toList();
      expect(shallow.single.key, 'book.epub');
      expect(await access.read(grant, shallow.single), [1]);
      expect((await access.stat(grant, shallow.single)).size, 1);
      expect(await File('${root.path}/book.epub').readAsBytes(), [1]);
    },
  );

  test(
    'filesystem scans omit linked files and directories',
    () async {
      await File('${root.path}/book.epub').writeAsBytes([1]);
      await Directory('${root.path}/nested').create();
      await Link('${root.path}/linked.epub').create('${root.path}/book.epub');
      await Link('${root.path}/linked-folder').create('${root.path}/nested');
      final files = await access.enumerate(grant, recursive: true).toList();
      expect(files.map((file) => file.key), ['book.epub']);
    },
    skip: Platform.isWindows ? 'Symlink creation requires a separately configured Windows host.' : false,
  );

  test('reads reject traversal outside the selected directory', () async {
    await expectLater(
      access.read(grant, const FolderFile(key: '../outside.epub', name: 'outside.epub', size: 1, modified: 1)),
      throwsA(isA<FolderAccessException>()),
    );
  });

  test('missing folders report unavailability without creating a replacement directory', () async {
    await root.delete();
    await expectLater(
      access.enumerate(grant, recursive: true).toList(),
      throwsA(isA<FolderAccessException>().having((error) => error.code, 'code', 'unavailable')),
    );
    expect(await access.reconnect(grant), isFalse);
    expect(await root.exists(), isFalse);
  });

  test(
    'reads reject sources replaced by symlinks',
    () async {
      await File('${root.path}/book.epub').writeAsBytes([1]);
      final file = (await access.enumerate(grant, recursive: false).toList()).single;
      await File('${root.path}/book.epub').delete();
      await Link('${root.path}/book.epub').create('${root.path}/missing.epub');
      await expectLater(access.read(grant, file), throwsA(isA<FolderAccessException>()));
    },
    skip: Platform.isWindows ? 'Symlink creation requires a separately configured Windows host.' : false,
  );

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS, TargetPlatform.macOS]) {
    test('$platform uses grant operations and closes an enumeration cancelled mid-batch', () async {
      const channel = MethodChannel('papyrus/folders');
      final calls = <MethodCall>[];
      final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return switch (call.method) {
          'start' => 'cursor',
          'next' => [
            {'key': 'provider-document', 'name': 'book.epub', 'size': -1, 'modified': 1},
            {'key': 'another-document', 'name': 'later.pdf', 'size': 2, 'modified': 1},
          ],
          'read' => Uint8List.fromList([1]),
          'restore' => true,
          _ => null,
        };
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final adapter = NativeDirectoryAccess(platform: platform);
      final files = await adapter.enumerate(grant, recursive: true).take(1).toList();
      expect(files.single.size, -1);
      expect(calls.map((call) => call.method), ['start', 'next', 'close']);
      expect(calls.first.arguments, {'grant': grant.key, 'recursive': true});
      expect(await adapter.read(grant, files.single), [1]);
      expect(await adapter.reconnect(grant), isTrue);
      await adapter.release(grant);
      expect(calls.last.method, 'release');
    });
  }
}
