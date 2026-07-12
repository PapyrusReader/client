import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/powersync/sync_profile_switch_queue.dart';

void main() {
  test('rapid switch away and back preserves the final requested profile', () async {
    final errors = <Object>[];
    final queue = SyncProfileSwitchQueue(initialProfileKey: 'profile-a', onError: (error, _) => errors.add(error));
    final firstStarted = Completer<void>();
    final releaseFirst = Completer<void>();
    final applied = <String>[];

    expect(
      queue.request('profile-b', () async {
        firstStarted.complete();
        await releaseFirst.future;
        applied.add('profile-b');
      }),
      isTrue,
    );
    await firstStarted.future;
    expect(queue.requestedProfileKey, 'profile-b');

    expect(queue.request('profile-a', () async => applied.add('profile-a')), isTrue);
    expect(queue.requestedProfileKey, 'profile-a');
    releaseFirst.complete();
    await queue.waitUntilIdle();

    expect(applied, ['profile-b', 'profile-a']);
    expect(errors, isEmpty);
  });

  test('failed switch does not prevent the next request', () async {
    final errors = <Object>[];
    final queue = SyncProfileSwitchQueue(initialProfileKey: 'profile-a', onError: (error, _) => errors.add(error));

    queue.request('profile-b', () async => throw StateError('unavailable'));
    queue.request('profile-c', () async {});
    await queue.waitUntilIdle();

    expect(queue.requestedProfileKey, 'profile-c');
    expect(errors, hasLength(1));
  });
}
