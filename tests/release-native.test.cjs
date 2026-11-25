const { test } = require('node:test');
const assert = require('node:assert/strict');
const { stableVersion } = require('../scripts/release-native.cjs');
test('accepts stable releases, rejects unstable and injected versions', () => {
  assert.equal(stableVersion('v1.104.7'), 'v1.104.7');
  for (const value of ['v1.105.0','v1.104.7-rc1','1.104.7','v1.104.7;whoami','v1.104.7\n']) {
    assert.throws(() => stableVersion(value));
  }
});
