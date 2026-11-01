const assert = require('node:assert/strict');
const {readFileSync} = require('node:fs');
const {join} = require('node:path');
const {runInNewContext} = require('node:vm');
const test = require('node:test');
const source = readFileSync(join(__dirname, '../../web/app_updates.js'), 'utf8');

function page({waiting = false, otherTabs = false} = {}) {
  let reloaded = false;
  let activated;
  let checked = false;
  const registration = {
    async update() { checked = true; },
    waiting: waiting ? {postMessage(message, ports) {
      assert.equal(message, 'activate-update');
      if (otherTabs) ports[0].reply('other-tabs'); else activated();
    }} : null,
  };
  const window = {location: {reload() { reloaded = true; }}};
  runInNewContext(source, {
    window, document: {baseURI: 'https://papyrus.test/reader/'}, setTimeout, clearTimeout,
    navigator: {serviceWorker: {
      async getRegistration(scope) { assert.equal(scope, 'https://papyrus.test/reader/'); return registration; },
      addEventListener(_, handler) { activated = handler; },
      removeEventListener() {},
    }},
    MessageChannel: class {
      constructor() { this.port1 = {close() {}}; this.port2 = {reply: data => this.port1.onmessage({data})}; }
    },
  });
  return {apply: window.papyrusApplyUpdate, reloaded: () => reloaded, checked: () => checked};
}

test('explicit reload activates the waiting worker first', async () => {
  const app = page({waiting: true});
  await app.apply();
  assert.ok(app.checked());
  assert.ok(app.reloaded());
});

test('other reading tabs prevent activation and receive an actionable message', async () => {
  const app = page({waiting: true, otherTabs: true});
  assert.match(await app.apply(), /Close other Papyrus tabs/);
  assert.equal(app.reloaded(), false);
});

test('no waiting worker reloads the current deployment', async () => {
  const app = page();
  await app.apply();
  assert.ok(app.reloaded());
});
