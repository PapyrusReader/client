import 'package:web/web.dart' as web;

void redirectTo(String url) {
  web.window.location.assign(url);
}

void clearBrowserQuery() {
  web.window.history.replaceState(null, '', web.window.location.pathname);
}
