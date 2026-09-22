const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const test = require('node:test');
const { runInNewContext } = require('node:vm');

const bootstrap = readFileSync(join(__dirname, '../../web/flutter_bootstrap.js'), 'utf8')
  .replace('{{flutter_js}}', '')
  .replace('{{flutter_build_config}}', '');

function browserDocument() {
  const events = [];
  let onEntrypointLoaded;
  runInNewContext(bootstrap, {
    _flutter: {
      loader: {
        load: (options) => { onEntrypointLoaded = options.onEntrypointLoaded; },
      },
    },
    window: { location: { reload: () => events.push('reload') } },
  });
  const engine = {
    initializeEngine: async () => {
      events.push('initialize');
      return { runApp: async () => { events.push('run'); } };
    },
  };
  return { events, start: () => onEntrypointLoaded(engine) };
}

test('cold startup initializes and runs the app without reloading', async () => {
  const page = browserDocument();
  await page.start();
  assert.deepEqual(page.events, ['initialize', 'run']);
});

test('hot restart reloads the document without invoking a second Dart runtime', async () => {
  const page = browserDocument();
  await page.start();
  await page.start();
  assert.deepEqual(page.events, ['initialize', 'run', 'reload']);
});

test('the refreshed document boots normally and handles another restart', async () => {
  const first = browserDocument();
  await first.start();
  await first.start();
  const next = browserDocument();
  await next.start();
  assert.deepEqual(next.events, ['initialize', 'run']);
  await next.start();
  assert.deepEqual(next.events, ['initialize', 'run', 'reload']);
});

test('a restart during initialization does not initialize a second engine', async () => {
  const page = browserDocument();
  await Promise.all([page.start(), page.start()]);
  assert.equal(page.events.filter((event) => event === 'initialize').length, 1);
  assert.equal(page.events.filter((event) => event === 'reload').length, 1);
});
