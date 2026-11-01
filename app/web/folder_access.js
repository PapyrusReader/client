/* Device folder permissions stay in this origin and never enter library sync. */
(() => {
  'use strict';
  const transient = new Map();
  const cursors = new Map();
  const canWatch = typeof window.showDirectoryPicker === 'function';
  const included = name => !name.startsWith('.') && !name.startsWith('~') &&
    !/\.(tmp|part|partial|crdownload|download)$/i.test(name);

  async function database() {
    return new Promise((resolve, reject) => {
      const request = indexedDB.open('papyrus-folder-grants', 1);
      request.onupgradeneeded = () => request.result.createObjectStore('grants');
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error);
    });
  }

  async function stored(mode, operation) {
    const db = await database();
    try {
      return await new Promise((resolve, reject) => {
        const transaction = db.transaction('grants', mode);
        const request = operation(transaction.objectStore('grants'));
        transaction.oncomplete = () => resolve(request.result);
        transaction.onerror = () => reject(transaction.error);
        transaction.onabort = () => reject(transaction.error);
      });
    } finally {
      db.close();
    }
  }

  async function grant(key) {
    if (transient.has(key)) return transient.get(key);
    const value = await stored('readonly', store => store.get(key));
    if (!value) throw new DOMException('Select this folder again to restore access.', 'NotAllowedError');
    if (await value.handle.queryPermission({mode: 'read'}) !== 'granted') {
      throw new DOMException('Reconnect this folder to allow access.', 'NotAllowedError');
    }
    return value;
  }

  function metadata(file, key) {
    return {key, name: file.name, size: file.size, modified: file.lastModified};
  }

  async function source(key, relative) {
    const value = await grant(key);
    if (value.files) {
      const file = value.files.get(relative);
      if (!file) throw new DOMException('Select the folder again.', 'NotFoundError');
      return file;
    }
    const parts = relative.split('/');
    if (parts.some(part => !part || part === '.' || part === '..')) throw new Error('Invalid source path.');
    let directory = value.handle;
    for (const part of parts.slice(0, -1)) directory = await directory.getDirectoryHandle(part);
    return (await directory.getFileHandle(parts.at(-1))).getFile();
  }

  async function* walk(value, recursive) {
    if (value.files) {
      for (const [key, file] of value.files) {
        const parts = key.split('/');
        if (parts.every(included) && (recursive || parts.length === 1)) yield metadata(file, key);
      }
      return;
    }
    async function* visit(directory, prefix) {
      for await (const [name, handle] of directory.entries()) {
        if (!included(name)) continue;
        const key = prefix + name;
        if (handle.kind === 'directory') {
          if (recursive) {
            try {
              yield* visit(handle, key + '/');
            } catch (error) {
              yield {key, name, size: 0, modified: 0, error: error.message};
            }
          }
        } else {
          try {
            yield metadata(await handle.getFile(), key);
          } catch (error) {
            yield {key, name, size: 0, modified: 0, error: error.message};
          }
        }
      }
    }
    yield* visit(value.handle, '');
  }

  async function pick() {
    if (canWatch) {
      const handle = await window.showDirectoryPicker({mode: 'read'});
      const existing = await stored('readonly', store => store.getAll());
      let identity = crypto.randomUUID();
      for (const value of existing) {
        try {
          if (await handle.isSameEntry(value.handle)) {
            identity = value.identity;
            break;
          }
        } catch (_) {
          // A disconnected old grant does not prevent choosing a new folder.
        }
      }
      const key = crypto.randomUUID();
      await stored('readwrite', store => store.put({handle, identity}, key));
      return {key, identity, name: handle.name, location: handle.name, persistent: true};
    }
    const input = document.createElement('input');
    input.type = 'file';
    input.multiple = true;
    input.webkitdirectory = true;
    const files = await new Promise(resolve => {
      input.onchange = () => resolve(Array.from(input.files || []));
      input.oncancel = () => resolve([]);
      input.click();
    });
    if (!files.length) return null;
    const key = crypto.randomUUID();
    const name = files[0].webkitRelativePath.split('/')[0] || 'Selected files';
    const entries = new Map(files.map(file => [file.webkitRelativePath.split('/').slice(1).join('/') || file.name, file]));
    transient.set(key, {files: entries});
    return {key, identity: key, name, location: name, persistent: false};
  }

  const actions = {
    pick,
    async restore({grant: key}) {
      if (transient.has(key)) return true;
      const value = await stored('readonly', store => store.get(key));
      return !!value && await value.handle.requestPermission({mode: 'read'}) === 'granted';
    },
    async start({grant: key, recursive}) {
      const cursor = crypto.randomUUID();
      cursors.set(cursor, walk(await grant(key), recursive));
      return cursor;
    },
    async next({cursor}) {
      const iterator = cursors.get(cursor);
      if (!iterator) return [];
      const batch = [];
      for (let count = 0; count < 128; count++) {
        const item = await iterator.next();
        if (item.done) break;
        batch.push(item.value);
      }
      return batch;
    },
    async close({cursor}) {
      await cursors.get(cursor)?.return();
      cursors.delete(cursor);
    },
    async stat({grant: key, key: relative}) { return metadata(await source(key, relative), relative); },
    async read({grant: key, key: relative}) { return (await source(key, relative)).arrayBuffer(); },
    async release({grant: key}) {
      transient.delete(key);
      await stored('readwrite', store => store.delete(key));
    },
  };

  window.papyrusFolders = {
    canWatch,
    async call(method, argumentsJson) {
      try {
        const value = await actions[method](JSON.parse(argumentsJson));
        return value instanceof ArrayBuffer ? value : JSON.stringify({value: value ?? null});
      } catch (error) {
        if (error.name === 'AbortError' && method === 'pick') return JSON.stringify({value: null});
        const code = error.name === 'NotAllowedError' ? 'access' : 'unavailable';
        return JSON.stringify({code, error: error.message || 'Could not access the source folder.'});
      }
    },
  };
})();
