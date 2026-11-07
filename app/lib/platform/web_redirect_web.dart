import 'dart:js_interop';
import 'package:web/web.dart' as web;

void redirectTo(String url) {
  web.window.location.assign(url);
}

void clearBrowserQuery() {
  web.window.history.replaceState(null, '', web.window.location.pathname);
}

Uri browserAppBaseUri() => Uri.parse(web.document.baseURI);

@JS('takePapyrusVerificationToken')
external JSString? _takeVerificationToken();

String? takeVerificationToken(String? token) => _takeVerificationToken()?.toDart ?? token;

void rememberOAuthServer(String serverKey) {
  web.window.sessionStorage.setItem('papyrus.oauth.server', serverKey);
}

bool consumeOAuthServer(String serverKey) {
  final expected = web.window.sessionStorage.getItem('papyrus.oauth.server');
  web.window.sessionStorage.removeItem('papyrus.oauth.server');
  return expected == serverKey;
}
