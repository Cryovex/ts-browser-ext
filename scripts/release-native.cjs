// Build on Windows CI. Publishing is a separate step after all checks pass.
const fs = require('node:fs');
const crypto = require('node:crypto');
const { execFileSync } = require('node:child_process');

function stableVersion(value) {
  const match = /^v(\d+)\.(\d+)\.(\d+)$/.exec(value);
  if (!match || match[0] !== value || Number(match[2]) % 2 !== 0) throw Error('Expected a stable Tailscale release');
  return value;
}
function run(command, args) {
  return execFileSync(command, args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'inherit'], windowsHide: true }).trim();
}
async function getJSON(url) {
  const response = await fetch(url, { signal: AbortSignal.timeout(30000) });
  if (!response.ok) throw Error(`GET ${url}: ${response.status}`);
  return response.json();
}
async function main() {
  const upstream = await getJSON('https://api.github.com/repos/tailscale/tailscale/releases/latest');
  if (upstream.draft || upstream.prerelease) throw Error('Upstream release is not stable');
  const version = stableVersion(upstream.tag_name);
  const source = run('git', ['rev-parse', 'HEAD']);
  if (!/^[0-9a-f]{40}$/.test(source)) throw Error('Invalid source commit');
  const goVersion = run('go', ['env', 'GOVERSION']);
  if (!/^go\d+\.\d+\.\d+$/.test(goVersion)) throw Error('Use a stable Go toolchain');
  const tag = `native-${version}-${goVersion}-${source.slice(0, 12)}`;

  // A release is immutable after publication. A daily check is a no-op unless
  // Tailscale, Go, or this fork's source has changed.
  if (process.env.NATIVE_PUBLISH === 'true') {
    const existing = await fetch(`https://api.github.com/repos/Cryovex/ts-browser-ext/releases/tags/${tag}`, {signal: AbortSignal.timeout(30000)});
    if (existing.ok) { console.log(`Already published: ${tag}`); return; }
    if (existing.status !== 404) throw Error(`Release lookup failed: ${existing.status}`);
  }
  run('go', ['get', `tailscale.com@${version}`]);
  run('go', ['mod', 'tidy']);
  run('go', ['mod', 'verify']);
  if (run('go', ['list', '-m', '-f', '{{.Version}}', 'tailscale.com']) !== version) throw Error('Resolved version differs from release');
  run('go', ['test', './...']);
  run('node', ['--test', 'tests/browser.test.cjs', 'tests/release-native.test.cjs']);
  run('pwsh', ['-NoProfile', '-File', 'tests/update-native.tests.ps1']);
  fs.mkdirSync('dist', {recursive:true});
  const binary = 'dist/ts-browser-ext-cryovex.exe';
  const short = version.slice(1);
  const flags = `-X main.releaseID=${tag} -X main.sourceCommit=${source} -X tailscale.com/version.shortStamp=${short} -X tailscale.com/version.longStamp=${short}-cryovex-${source.slice(0, 12)}`;
  run('go', ['build', '-trimpath', '-ldflags', flags, '-o', binary, '.']);
  const built = JSON.parse(run(binary, ['--version-json']));
  if (built.tailscaleVersion !== version || built.release !== tag || built.sourceCommit !== source) throw Error('Binary build information mismatch');
  run('pwsh', ['-NoProfile', '-File', 'tests/native-smoke.ps1', '-Binary', binary]);
  const bytes = fs.readFileSync(binary);
  const manifest = {schemaVersion:1, release:tag, tailscaleVersion:version, sourceCommit:source,
    goVersion:built.goVersion, platform:'windows-amd64', filename:'ts-browser-ext-cryovex.exe',
    size:bytes.length, sha256:crypto.createHash('sha256').update(bytes).digest('hex')};
  fs.writeFileSync('dist/native-update.json', JSON.stringify(manifest, null, 2)+'\n');
  // Retain the resolved dependency graph for reproducibility and auditing.
  fs.copyFileSync('go.mod', 'dist/go.mod');
  fs.copyFileSync('go.sum', 'dist/go.sum');
  if (process.env.GITHUB_OUTPUT) fs.appendFileSync(process.env.GITHUB_OUTPUT, `tag=${tag}\nbuilt=true\n`);
  console.log(JSON.stringify(manifest, null, 2));
}
module.exports = {stableVersion};
if (require.main === module) main().catch(error => {console.error(error); process.exitCode=1;});
