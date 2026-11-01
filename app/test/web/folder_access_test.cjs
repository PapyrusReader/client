const assert = require('node:assert/strict');
const {readFileSync} = require('node:fs');
const {join} = require('node:path');
const test = require('node:test');
const {runInNewContext} = require('node:vm');
const {randomUUID} = require('node:crypto');
const source = readFileSync(join(__dirname, '../../web/folder_access.js'), 'utf8');

function environment(handle, files = []) {
  const records = new Map();
  let picks = 0;
  const store = {
    get: key => ({result: records.get(key)}),
    getAll: () => ({result: [...records.values()]}),
    put(value, key) { records.set(key, value); return {result: key}; },
    delete(key) { records.delete(key); return {}; },
  };
  const database = {
    close() {}, createObjectStore() {},
    transaction() {
      const transaction = {objectStore: () => store};
      queueMicrotask(() => transaction.oncomplete());
      return transaction;
    },
  };
  const window = {};
  if (handle) window.showDirectoryPicker = async options => {
    assert.equal(options.mode, 'read');
    picks++;
    return handle;
  };
  runInNewContext(source, {
    window, DOMException, ArrayBuffer, crypto: {randomUUID},
    indexedDB: {
      open() {
        const request = {result: database};
        queueMicrotask(() => request.onsuccess());
        return request;
      },
    },
    document: {
      createElement() {
        return {files, click() { queueMicrotask(() => files.length ? this.onchange() : this.oncancel()); }};
      },
    },
  });
  return {
    records, get picks() { return picks; }, canWatch: window.papyrusFolders.canWatch,
    async call(method, args = {}) {
      const response = await window.papyrusFolders.call(method, JSON.stringify(args));
      return typeof response === 'string' ? JSON.parse(response) : response;
    },
  };
}

function file(name, content = [1], relative = '') {
  return {name, size: content.length, lastModified: 1, webkitRelativePath: relative,
    async arrayBuffer() { return Uint8Array.from(content).buffer; }};
}

function directory(name, entries = []) {
  const handle = {
    name, kind: 'directory', permission: 'granted', requests: 0,
    async queryPermission() { return this.permission; },
    async requestPermission() { this.requests++; return this.permission; },
    async isSameEntry(other) { return this === other; },
    async *entries() { yield* entries; },
    async getDirectoryHandle(name) { return entries.find(entry => entry[0] === name)[1]; },
    async getFileHandle(name) { return entries.find(entry => entry[0] === name)[1]; },
  };
  return handle;
}
const entry = value => [value.name, {kind: 'file', async getFile() { return value; }}];

test('picker starts on the original gesture and duplicate selections share identity only', async () => {
  const root = directory('Books');
  const browser = environment(root);
  const picking = browser.call('pick');
  assert.equal(browser.picks, 1);
  const first = (await picking).value;
  const second = (await browser.call('pick')).value;
  assert.equal(first.identity, second.identity);
  assert.notEqual(first.key, second.key);
  await browser.call('release', {grant: second.key});
  assert.ok(browser.records.has(first.key));
});

test('scanning streams entries, skips temporary files and continues after an inaccessible subfolder', async () => {
  const bad = directory('blocked');
  bad.entries = async function* () { throw new Error('Offline provider'); };
  const nested = directory('Nested', [entry(file('later.pdf', [2]))]);
  const root = directory('Books', [entry(file('.hidden.epub')), ['blocked', bad],
    ['Nested', nested], entry(file('book.epub')), entry(file('book.epub.part'))]);
  const browser = environment(root);
  const grant = (await browser.call('pick')).value.key;
  const cursor = (await browser.call('start', {grant, recursive: true})).value;
  const batch = (await browser.call('next', {cursor})).value;
  assert.deepEqual(batch.map(value => value.key), ['blocked', 'Nested/later.pdf', 'book.epub']);
  assert.equal(batch[0].error, 'Offline provider');
  assert.equal((await browser.call('read', {grant, key: 'book.epub'})).byteLength, 1);
  await browser.call('close', {cursor});
  assert.deepEqual((await browser.call('next', {cursor})).value, []);
});

test('restoration requires explicit permission and automatic scans never prompt', async () => {
  const root = directory('Books');
  const browser = environment(root);
  const grant = (await browser.call('pick')).value.key;
  root.permission = 'denied';
  assert.equal((await browser.call('start', {grant, recursive: true})).code, 'access');
  assert.equal(root.requests, 0);
  assert.equal((await browser.call('restore', {grant})).value, false);
  assert.equal(root.requests, 1);
});

test('fallback folder selection retains relative paths and cancellation creates no grant', async () => {
  const browser = environment(null, [file('book.epub', [1], 'Books/book.epub'),
    file('later.pdf', [2], 'Books/Nested/later.pdf')]);
  assert.equal(browser.canWatch, false);
  const grant = (await browser.call('pick')).value;
  assert.equal(grant.persistent, false);
  const cursor = (await browser.call('start', {grant: grant.key, recursive: false})).value;
  assert.deepEqual((await browser.call('next', {cursor})).value.map(value => value.key), ['book.epub']);
  assert.equal((await environment(null).call('pick')).value, null);
});
