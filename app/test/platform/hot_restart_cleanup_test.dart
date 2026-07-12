import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/platform/hot_restart_cleanup.dart';

void main() {
  setUp(runPreviousHotRestartCleanup);

  test('registered web cleanup runs once before the next app starts', () async {
    var calls = 0;
    registerHotRestartCleanup(() async => calls++);

    await runPreviousHotRestartCleanup();
    await runPreviousHotRestartCleanup();

    expect(calls, 1);
  }, skip: !kIsWeb);
}
