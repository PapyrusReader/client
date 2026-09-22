import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/opds/opds_http_client.dart';
import 'package:papyrus/opds/opds_models.dart';
import 'package:papyrus/opds/opds_resource_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

class _FailingPreferences extends InMemorySharedPreferencesStore {
  _FailingPreferences({this.throwsOnWrite = true}) : super.empty();
  final bool throwsOnWrite;
  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (throwsOnWrite) throw StateError('Quota exceeded');
    return false;
  }
}

class _DelayedPreferences extends InMemorySharedPreferencesStore {
  _DelayedPreferences() : super.empty();
  final firstWrite = Completer<void>();
  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    await firstWrite.future;
    return super.setValue(valueType, key, value);
  }
}

void main() {
  final catalog = OpdsCatalog(id: 'one', name: 'Books', uri: Uri.parse('https://books.test/root'));
  final resource = Uri.parse('https://books.test/feed');
  OpdsResponse response([String body = 'feed']) => OpdsResponse(
    uri: Uri.parse('https://cdn.test/redirected/feed'),
    bytes: Uint8List.fromList(utf8.encode(body)),
    headers: {'content-type': 'application/opds+json', 'authorization': 'secret', 'set-cookie': 'secret'},
  );
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('cold cache persists bytes, redirect URI and only content type', () async {
    final prefs = await SharedPreferences.getInstance();
    final cache = OpdsResourceCache(prefs)..setScope('alice');
    final token = cache.capture(catalog, resource)!;
    expect(cache.read(token), isNull);
    await cache.write(token, response());
    final stored = prefs.getKeys().map(prefs.get).join();
    expect(stored, isNot(contains('secret')));
    final restarted = OpdsResourceCache(prefs)..setScope('alice');
    final warm = restarted.read(restarted.capture(catalog, resource)!)!;
    expect(warm.response.text, 'feed');
    expect(warm.response.uri.host, 'cdn.test');
    expect(warm.response.headers, {'content-type': 'application/opds+json'});
    expect(warm.fetchedAt.isAfter(DateTime.now().subtract(const Duration(minutes: 1))), isTrue);
  });

  test('scope switching and catalog invalidation reject obsolete writes', () async {
    final cache = OpdsResourceCache(await SharedPreferences.getInstance())..setScope('alice');
    final old = cache.capture(catalog, resource)!;
    await cache.write(old, response());
    cache.setScope('bob');
    expect(cache.read(cache.capture(catalog, resource)!), isNull);
    cache.setScope('alice');
    expect(cache.isCurrent(old), isFalse);
    await cache.write(old, response('obsolete'));
    expect(cache.read(cache.capture(catalog, resource)!)!.response.text, 'feed');
    final beforeEdit = cache.capture(catalog, resource)!;
    await cache.invalidateCatalog(catalog);
    await cache.write(beforeEdit, response('obsolete'));
    expect(cache.read(cache.capture(catalog, resource)!), isNull);
    cache.setScope(null);
    expect(cache.capture(catalog, resource), isNull);
  });

  test('LRU entry cap applies across accounts and survives restart', () async {
    final prefs = await SharedPreferences.getInstance();
    final cache = OpdsResourceCache(prefs, maxEntries: 2)..setScope('alice');
    final first = cache.capture(catalog, resource)!;
    final second = cache.capture(catalog, resource.resolve('second'))!;
    await cache.write(first, response('first'));
    await cache.write(second, response('second'));
    cache.read(first);
    cache.setScope('bob');
    await cache.write(cache.capture(catalog, resource)!, response('bob'));
    final restarted = OpdsResourceCache(prefs, maxEntries: 2)..setScope('alice');
    expect(restarted.read(restarted.capture(catalog, resource)!)!.response.text, 'first');
    expect(restarted.read(restarted.capture(catalog, resource.resolve('second'))!), isNull);
  });

  test('an edit finishing in an inactive scope invalidates only that account', () async {
    final cache = OpdsResourceCache(await SharedPreferences.getInstance())..setScope('alice');
    await cache.write(cache.capture(catalog, resource)!, response('alice'));
    cache.setScope('bob');
    final bob = cache.capture(catalog, resource)!;
    await cache.write(bob, response('bob'));
    await cache.invalidateCatalog(catalog, scope: 'alice');
    expect(cache.read(bob)!.response.text, 'bob');
    cache.setScope('alice');
    expect(cache.read(cache.capture(catalog, resource)!), isNull);
  });

  test('invalidation wins over an already pending persistent write', () async {
    final platform = _DelayedPreferences();
    SharedPreferencesStorePlatform.instance = platform;
    final prefs = await SharedPreferences.getInstance();
    final cache = OpdsResourceCache(prefs)..setScope('alice');
    final token = cache.capture(catalog, resource)!;
    final writing = cache.write(token, response());
    await Future<void>.delayed(Duration.zero);
    final invalidating = cache.invalidateCatalog(catalog);
    platform.firstWrite.complete();
    await Future.wait([writing, invalidating]);
    final restarted = OpdsResourceCache(prefs)..setScope('alice');
    expect(restarted.read(restarted.capture(catalog, resource)!), isNull);
    expect((await platform.getAll()).values.join(), isNot(contains('redirected')));
  });

  test('a rejected preference write remains usable in memory', () async {
    SharedPreferencesStorePlatform.instance = _FailingPreferences(throwsOnWrite: false);
    final cache = OpdsResourceCache(await SharedPreferences.getInstance())..setScope('alice');
    final token = cache.capture(catalog, resource)!;
    await cache.write(token, response());
    expect(cache.read(token)!.response.text, 'feed');
    await cache.remove(token);
    expect(cache.read(token), isNull);
  });

  test('only scope switches and catalog invalidation notify listeners', () async {
    final cache = OpdsResourceCache(await SharedPreferences.getInstance());
    var notifications = 0;
    cache.addListener(() => notifications++);
    cache.setScope('alice');
    expect(notifications, 1);
    cache.setScope('alice');
    final token = cache.capture(catalog, resource)!;
    await cache.write(token, response());
    cache.read(token);
    await cache.remove(token);
    expect(notifications, 1);
    await cache.invalidateCatalog(catalog);
    expect(notifications, 2);
    cache.setScope(null);
    expect(notifications, 3);
    cache.dispose();
  });

  test('bounds serialized bytes and rejects oversized resources', () async {
    final prefs = await SharedPreferences.getInstance();
    final cache = OpdsResourceCache(prefs, maxBytes: 900, maxEntryBytes: 500)..setScope('alice');
    for (var i = 0; i < 10; i++) {
      await cache.write(cache.capture(catalog, resource.resolve('$i'))!, response('x' * 100));
    }
    expect(utf8.encode(prefs.getKeys().map(prefs.get).join()).length, lessThanOrEqualTo(900));
    final big = cache.capture(catalog, resource)!;
    await cache.write(big, response('x' * 1000));
    expect(cache.read(big), isNull);
  });

  test('corrupt persistence and quota failures do not break callers', () async {
    final prefs = await SharedPreferences.getInstance();
    final cache = OpdsResourceCache(prefs)..setScope('alice');
    await cache.write(cache.capture(catalog, resource)!, response());
    final key = prefs.getKeys().single;
    await prefs.setString(key, '{corrupt');
    final corrupted = OpdsResourceCache(prefs)..setScope('alice');
    expect(corrupted.read(corrupted.capture(catalog, resource)!), isNull);
    SharedPreferences.setMockInitialValues({});
    SharedPreferencesStorePlatform.instance = _FailingPreferences();
    final failing = OpdsResourceCache(await SharedPreferences.getInstance())..setScope('alice');
    final token = failing.capture(catalog, resource)!;
    await failing.write(token, response());
    expect(failing.read(token)!.response.text, 'feed');
    await failing.invalidateCatalog(catalog);
    expect(failing.read(failing.capture(catalog, resource)!), isNull);
  });
}
