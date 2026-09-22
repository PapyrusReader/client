{{flutter_js}}
{{flutter_build_config}}

(() => {
  let started = false;

  _flutter.loader.load({
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
