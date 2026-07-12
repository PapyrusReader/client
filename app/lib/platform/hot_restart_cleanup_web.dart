import 'dart:js_interop';

typedef HotRestartCleanup = Future<void> Function();

@JS('__papyrusHotRestartCleanup')
external JSFunction? get _registeredCleanup;

@JS('__papyrusHotRestartCleanup')
external set _registeredCleanup(JSFunction? cleanup);

Future<void> runPreviousHotRestartCleanup() async {
  final cleanup = _registeredCleanup;
  _registeredCleanup = null;
  if (cleanup == null) return;

  final result = cleanup.callAsFunction();
  if (result != null) {
    await (result as JSPromise).toDart;
  }
}

void registerHotRestartCleanup(HotRestartCleanup cleanup) {
  _registeredCleanup = (() => cleanup().toJS).toJS;
}
