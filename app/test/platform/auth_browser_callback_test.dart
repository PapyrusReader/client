@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/platform/web_redirect.dart';
import 'package:web/web.dart' as web;

void main() {
  test('web OAuth return URI preserves a self-hosted app base path', () {
    final base = web.document.createElement('base')..setAttribute('href', '/reader/');
    web.document.head!.prepend(base);
    addTearDown(() => base.remove());
    expect(browserAppBaseUri().resolve('auth/callback').path, '/reader/auth/callback');
  });

  test('web handoffs require the initiating API prefix and server and are consumed once', () {
    rememberOAuthServer('https://one.test/custom/api');
    expect(consumeOAuthServer('https://two.test/custom/api'), isFalse);
    expect(consumeOAuthServer('https://one.test/custom/api'), isFalse);
    rememberOAuthServer('https://one.test/custom/api');
    expect(consumeOAuthServer('https://one.test/v1'), isFalse);
    rememberOAuthServer('https://one.test/custom/api');
    expect(consumeOAuthServer('https://one.test/custom/api'), isTrue);
    expect(consumeOAuthServer('https://one.test/custom/api'), isFalse);
  });
}
