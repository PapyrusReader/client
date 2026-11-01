{{flutter_js}}
{{flutter_build_config}}

(() => {
  let started = false;

  if (typeof navigator !== 'undefined' && 'serviceWorker' in navigator) {
    // Development builds have no offline manifest. Release packaging prepares it.
    fetch('offline-manifest.json', {cache: 'no-store'}).then(response => {
      if (response.ok) return navigator.serviceWorker.register('papyrus_service_worker.js', {updateViaCache: 'none'});
    }).catch(() => {});
  }

  _flutter.loader.load({
    config: {canvasKitBaseUrl: 'canvaskit/'},
    onEntrypointLoaded: async (engineInitializer) => {
      // A web hot restart resets Dart types but leaves browser callbacks alive.
      // Start a new document rather than reusing the old database listeners.
      if (started) {
        window.location.reload();
        return;
      }

      started = true;
      const appRunner = await engineInitializer.initializeEngine();
      await appRunner.runApp();
    },
  });
})();
