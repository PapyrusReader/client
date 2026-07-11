import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/media/media_storage_scope.dart';

void main() {
  test('scope key isolates server and user', () {
    final first = MediaStorageScope(profileKey: 'official', userId: 'user-1');
    final second = MediaStorageScope(profileKey: 'custom-deadbeef', userId: 'user-1');

    expect(first.persistenceKey, isNot(second.persistenceKey));
    expect(first.persistenceKey, 'official--user-1');
  });

  test('scope equality uses server and user', () {
    final first = MediaStorageScope(profileKey: 'official', userId: 'user-1');
    final same = MediaStorageScope(profileKey: 'official', userId: 'user-1');
    final otherUser = MediaStorageScope(profileKey: 'official', userId: 'user-2');

    expect(first, same);
    expect(first.hashCode, same.hashCode);
    expect(first, isNot(otherUser));
  });

  test('scope rejects path separators', () {
    expect(
      () => MediaStorageScope(profileKey: '../official', userId: 'user-1'),
      throwsArgumentError,
    );
    expect(
      () => MediaStorageScope(profileKey: 'official', userId: r'user\1'),
      throwsArgumentError,
    );
  });
}
