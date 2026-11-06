void redirectTo(String url) {
  throw UnsupportedError('Browser redirects are only available on web');
}

void clearBrowserQuery() {}

Uri browserAppBaseUri() => Uri.base;

String? takeVerificationToken(String? token) => token;

void rememberOAuthServer(String serverKey) {}

bool consumeOAuthServer(String serverKey) => true;
