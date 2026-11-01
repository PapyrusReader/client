const assert = require('node:assert/strict');
const {readFileSync} = require('node:fs');
const {join} = require('node:path');
const test = require('node:test');
const {runInNewContext} = require('node:vm');

const source = readFileSync(join(__dirname, '../../web/papyrus_service_worker.js'), 'utf8')
  .replace("const applicationRevision = 'unprepared';", "const applicationRevision = 'test';");
const origin = 'https://papyrus.test';
const scope = `${origin}/reader/`;

function worker({failAsset = false} = {}) {
  const handlers = {};
  const stores = new Map([['unrelated-cache', new Map()], ['papyrus-offline-old', new Map()]]);
  const requests = [];
  let offline = false;
  const key = request => new URL(typeof request === 'string' ? request : request.href || request.url, scope).href;
  const manifest = {revision: 'test', assets: ['index.html', 'main.dart.js', 'book_worker.js', 'canvaskit/canvaskit.wasm']};
  const fetch = async request => {
    requests.push(key(request));
    if (offline) throw new Error('Offline');
    if (key(request).endsWith('offline-manifest.json')) return new Response(JSON.stringify(manifest));
    return new Response('network');
  };
  class ScopedRequest extends Request {
    constructor(url, options) { super(new URL(url, scope), options); }
  }
  runInNewContext(source, {
    URL, Set, JSON, Response, Request: ScopedRequest, fetch,
    caches: {
      async open(name) {
        if (!stores.has(name)) stores.set(name, new Map());
        const entries = stores.get(name);
        return {
          async match(request) { return entries.get(key(request))?.clone(); },
          async put(request, response) { entries.set(key(request), response); },
          async addAll(batch) {
            if (failAsset) throw new Error('Download interrupted');
            for (const request of batch) entries.set(key(request), new Response(`cached:${key(request)}`));
          },
        };
      },
      async keys() { return [...stores.keys()]; },
      async delete(name) { return stores.delete(name); },
    },
    self: {
      registration: {scope}, location: {origin}, clients: {async claim() {}},
      addEventListener(name, handler) { handlers[name] = handler; },
    },
  });
  return {
    stores, requests,
    offline() { offline = true; },
    lifecycle(name) {
      let operation;
      handlers[name]({waitUntil(value) { operation = value; }});
      return operation;
    },
    fetch(url, {method = 'GET', mode = 'cors'} = {}) {
      let response;
      handlers.fetch({request: {url, method, mode}, respondWith(value) { response = value; }});
      return response;
    },
  };
}

test('cached application, reader and import runtime reopen offline under a subpath', async () => {
  const runtime = worker();
  await runtime.lifecycle('install');
  await runtime.lifecycle('activate');
  runtime.offline();
  for (const name of ['main.dart.js', 'book_worker.js', 'canvaskit/canvaskit.wasm']) {
    assert.equal(await (await runtime.fetch(scope + name)).text(), `cached:${scope + name}`);
  }
  const page = await runtime.fetch(scope + 'library/folders', {mode: 'navigate'});
  assert.equal(await page.text(), `cached:${scope}index.html`);
  assert.ok(runtime.stores.has('unrelated-cache'));
  assert.ok(!runtime.stores.has('papyrus-offline-old'));
});

test('API, private media, cross-origin requests and writes are never cached', async () => {
  const runtime = worker();
  await runtime.lifecycle('install');
  assert.equal(runtime.fetch(`${origin}/v1/media/private`), undefined);
  assert.equal(runtime.fetch(`${origin}/api/books`), undefined);
  assert.equal(runtime.fetch('https://api.test/v1/books'), undefined);
  assert.equal(runtime.fetch(scope + 'main.dart.js', {method: 'POST'}), undefined);
  assert.equal(await (await runtime.fetch(scope + 'user-book.epub')).text(), 'network');
});

test('failed preparation removes the partial cache and leaves the existing release', async () => {
  const runtime = worker({failAsset: true});
  await assert.rejects(runtime.lifecycle('install'), /Download interrupted/);
  assert.ok(!runtime.stores.has('papyrus-offline-test'));
  assert.ok(runtime.stores.has('papyrus-offline-old'));
});
