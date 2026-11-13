const assert = require('node:assert/strict');
const {test} = require('node:test');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const source = fs.readFileSync(path.join(__dirname, '../../web/auth_landing.js'), 'utf8');

for (const base of ['/', '/reader/']) {
  test(`verification capture removes secrets before app bootstrap at ${base}`, () => {
    let replaced;
    const window = {
      location: {href: `https://app.test${base}verify-email?token=private&other=value#fragment`},
      history: {replaceState: (_, __, value) => {replaced = value;}},
    };
    vm.runInNewContext(source, {window, URL});
    assert.equal(replaced, `${base}verify-email`);
    assert.equal(window.takePapyrusVerificationToken(), 'private');
    assert.equal(window.takePapyrusVerificationToken(), null);
    assert.equal(Object.values(window).includes('private'), false);
  });
}

test('ordinary routes are not rewritten', () => {
  const window = {location: {href: 'https://app.test/library?search=book'}, history: {replaceState() { assert.fail(); }}};
  vm.runInNewContext(source, {window, URL});
  assert.equal(window.takePapyrusVerificationToken(), null);
});

test('no-referrer and token capture precede all app resources', () => {
  const html = fs.readFileSync(path.join(__dirname, '../../web/index.html'), 'utf8');
  assert.ok(html.indexOf('name="referrer" content="no-referrer"') < html.indexOf('src="auth_landing.js"'));
  assert.ok(html.indexOf('src="auth_landing.js"') < html.indexOf('rel="apple-touch-icon"'));
  assert.ok(html.indexOf('src="auth_landing.js"') < html.indexOf('src="flutter_bootstrap.js"'));
});
