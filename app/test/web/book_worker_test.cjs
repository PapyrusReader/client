const assert = require('node:assert/strict');
const {readFileSync} = require('node:fs');
const {resolve} = require('node:path');
const {test} = require('node:test');
const vm = require('node:vm');

function directory() {
  const entries = new Map();
  const missing = () => Object.assign(new Error('missing'), {name: 'NotFoundError'});
  return {
    async getDirectoryHandle(name, {create}) {
      if (!entries.has(name)) {
        if (!create) throw missing();
        entries.set(name, directory());
      }
      return entries.get(name);
    },
    async getFileHandle(name, {create}) {
      if (!entries.has(name)) {
        if (!create) throw missing();
        let contents = new Uint8Array();
        entries.set(name, {
          async createWritable() {
            let pending;
            return {async write(bytes) {pending = new Uint8Array(bytes);}, async close() {contents = pending;}};
          },
          async getFile() {return {async arrayBuffer() {return contents.slice().buffer;}};},
        });
      }
      return entries.get(name);
    },
    async removeEntry(name) {
      if (!entries.delete(name)) throw missing();
    },
  };
}

test('cover worker dispatches scoped storage, promotion, deletion and rejects unsafe buckets', async () => {
  const root = directory();
  const responses = [];
  const locks = [];
  const context = vm.createContext({
    self: {}, Uint8Array,
    postMessage: message => responses.push(message),
    navigator: {
      storage: {getDirectory: async () => root},
      locks: {async request(name, callback) {locks.push(name); return callback();}},
    },
  });
  vm.runInContext(readFileSync(resolve(__dirname, '../../web/book_worker.js'), 'utf8'), context);
  const send = async (type, fields = {}) => {
    await context.self.onmessage({data: {
      type, requestId: String(responses.length), scopeKey: 'alice', bucket: 'pending', mediaId: 'book', ...fields,
    }});
    return responses.at(-1);
  };
  const bytes = new Uint8Array([1, 2, 3]);
  assert.equal((await send('storeCover', {fileData: bytes.buffer})).type, 'success');
  assert.deepEqual(new Uint8Array((await send('getCover')).fileData), bytes);
  assert.equal((await send('getCover', {scopeKey: 'bob'})).fileData, null);
  assert.equal((await send('getCover', {bucket: 'cached'})).fileData, null);
  assert.equal((await send('promoteCover', {targetMediaId: 'asset'})).promoted, true);
  assert.equal((await send('getCover')).fileData, null);
  assert.deepEqual(new Uint8Array((await send('getCover', {bucket: 'cached', mediaId: 'asset'})).fileData), bytes);
  assert.equal((await send('deleteCover', {bucket: 'cached', mediaId: 'asset'})).type, 'success');
  assert.equal((await send('getCover', {bucket: 'cached', mediaId: 'asset'})).fileData, null);
  for (const bucket of ['pending', 'cached', 'books']) {
    assert.equal((await send('storeCover', {bucket, fileData: bytes.buffer})).type, 'success');
  }
  await send('storeCover', {scopeKey: 'bob', fileData: bytes.buffer});
  assert.equal((await send('clearCovers')).type, 'success');
  assert.deepEqual(new Uint8Array((await send('getCover', {scopeKey: 'bob'})).fileData), bytes);
  for (const bucket of ['pending', 'cached', 'books']) {
    assert.equal((await send('getCover', {bucket})).fileData, null);
  }
  assert.equal((await send('storeCover', {bucket: '../other', fileData: bytes.buffer})).type, 'error');
  assert.equal((await send('getCover', {scopeKey: '../bob'})).type, 'error');
  assert.ok(locks.length > 0);
});
