typedef HotRestartCleanup = Future<void> Function();

Future<void> runPreviousHotRestartCleanup() async {}

void registerHotRestartCleanup(HotRestartCleanup cleanup) {}
