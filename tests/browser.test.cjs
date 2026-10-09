const assert = require('node:assert/strict');
const test = require('node:test');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const root = path.join(__dirname, '..');
const quiet = { log() {}, error() {} };
function event() {
  const listeners = [];
  return { listeners,
    addListener(fn) { if (!listeners.includes(fn)) listeners.push(fn); },
    removeListener(fn) { const i = listeners.indexOf(fn); if (i >= 0) listeners.splice(i, 1); },
    emit(...args) { return [...listeners].map(fn => fn(...args)); }
  };
}
async function background(name, start = true) {
  const ports = [], timers = [], configurations = [];
  const proxyRequests = event();
  const api = {
    runtime: { id: 'abcdefghijklmnopabcdefghijklmnop', onConnect: event(), onMessage: event(), lastError: null,
      connectNative() { const port = {onMessage: event(), onDisconnect: event(), sent: [], postMessage(msg) { this.sent.push(msg); }}; ports.push(port); return port; }
    },
    action: { setIcon(_icon, cb) { if (cb) cb(); return Promise.resolve(); } },
    extension: { isAllowedIncognitoAccess: () => Promise.resolve(true) },
    storage: { local: {
      get(_key, cb) { const result = {profileId: 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'}; if (cb) cb(result); return Promise.resolve(result); },
      set(_value, cb) { if (cb) cb(); return Promise.resolve(); }
    } },
    proxy: { onRequest: proxyRequests, settings: {
      set(config, cb) { configurations.push(config); if (cb) cb(); return Promise.resolve(); },
      clear(_details, cb) { configurations.push({cleared: true}); if (cb) cb(); return Promise.resolve(); }
    } }
  };
  const context = vm.createContext({chrome: api, browser: api, console: quiet, URL,
    setTimeout: fn => timers.push(fn), crypto: require('node:crypto').webcrypto});
  vm.runInContext(fs.readFileSync(path.join(root, name === 'Chrome' ? 'background.js' : 'firefox/background.js'), 'utf8'), context);
  await Promise.resolve();
  ports[0].onMessage.emit({procRunning: {port: 41001, pid: 1}});
  assert.equal(ports[0].sent.filter(x => x.cmd === 'init').length, 1);
  if (start) {
    ports[0].onMessage.emit({init: {error: ''}});
    ports[0].onMessage.emit({status: {running: true, tailnet: 'example.ts.net'}});
  }
  return {api, context, ports, timers, configurations, proxyRequests};
}
function assertRoute(b, name, port) {
  if (name === 'Chrome') {
    const config = b.configurations.at(-1);
    if (port) assert.equal(config.value.rules.singleProxy.port, port);
    else assert.ok(!config || config.cleared);
  } else {
    assert.equal(b.proxyRequests.listeners.length, port ? 1 : 0);
    if (port) assert.equal(b.proxyRequests.listeners[0]({url: 'https://example.com/'}).port, port);
  }
}
for (const name of ['Chrome', 'Firefox']) {
  test(name + ': startup waits for initialization', async () => {
    const b = await background(name, false);
    assertRoute(b, name, 0);
    b.ports[0].onMessage.emit({status: {running: true}});
    assertRoute(b, name, 0);
    b.ports[0].onMessage.emit({init: {error: ''}});
    assertRoute(b, name, 41001);
  });
  test(name + ': toggle off restores routing; toggle on reuses port', async () => {
    const b = await background(name);
    b.api.runtime.onMessage.emit({command: 'toggleProxy'}, {}, () => {});
    assert.equal(b.ports[0].sent.at(-1).cmd, 'down');
    assertRoute(b, name, 0);
    b.ports[0].onMessage.emit({status: {running: false, error: 'State: Stopped'}});
    b.api.runtime.onMessage.emit({command: 'toggleProxy'}, {}, () => {});
    assert.equal(b.ports[0].sent.at(-1).cmd, 'up');
    b.ports[0].onMessage.emit({status: {running: true}});
    assertRoute(b, name, 41001);
  });
  test(name + ': disconnect clears routing and replacement gets init', async () => {
    const b = await background(name);
    b.ports[0].onDisconnect.emit();
    assertRoute(b, name, 0);
    assert.equal(b.timers.length, 1);
    b.timers.shift()();
    b.ports[1].onMessage.emit({procRunning: {port: 41002, pid: 2}});
    assert.equal(b.ports[1].sent.filter(x => x.cmd === 'init').length, 1);
    assertRoute(b, name, 0);
    b.ports[1].onMessage.emit({init: {error: ''}});
    b.ports[1].onMessage.emit({status: {running: true}});
    assertRoute(b, name, 41002);
  });
  test(name + ': init errors never enable routing', async () => {
    const b = await background(name, false);
    b.ports[0].onMessage.emit({status: {running: true}});
    b.ports[0].onMessage.emit({init: {error: 'start failed'}});
    assertRoute(b, name, 0);
  });
  test(name + ': repeated status updates do not duplicate routes', async () => {
    const b = await background(name);
    for (let i = 0; i < 20; i++) b.ports[0].onMessage.emit({status: {running: true}});
    assertRoute(b, name, 41001);
    if (name === 'Chrome') assert.equal(b.configurations.length, 1);
  });
  test(name + ': login click opens the supplied URL', () => {
    const registrations = [], tabs = [];
    let ready;
    function element(name) { return {innerHTML:'',textContent:'',classList:{remove(){}},addEventListener(type,fn){registrations.push({name,type,fn});}}; }
    const elements = Object.fromEntries(['toggleSlider','.slider','settingsButton','state'].map(x=>[x,element(x)]));
    const port = {onMessage: event(), disconnect(){}};
    const document = {addEventListener(type,fn){if(type==='DOMContentLoaded')ready=fn;},getElementById:name=>elements[name],querySelector:name=>elements[name]};
    const api = {runtime:{connect:()=>port},tabs:{create:item=>{tabs.push(item);return Promise.resolve();}}};
    const context = vm.createContext({document,console:quiet,window:{addEventListener(){}},chrome:api,browser:api});
    vm.runInContext(fs.readFileSync(path.join(root,name==='Chrome'?'popup.js':'firefox/popup.js'),'utf8'),context);
    ready();
    const url='https://login.tailscale.com/a/example';
    port.onMessage.emit({status:{running:false,needsLogin:true,browseToURL:url}});
    assert.match(elements.state.innerHTML,/href='#login'/);
    const click=registrations.find(x=>x.name==='state'&&x.type==='click');
    assert.ok(click);
    let prevented=false;
    click.fn({target:{closest:()=>({})},preventDefault(){prevented=true;}});
    assert.equal(prevented,true);
    assert.equal(tabs[0].url,url);
  });
}
test('Firefox bypasses loopback and resolves tailnet names over SOCKS', async () => {
  const b = await background('Firefox');
  const route = b.proxyRequests.listeners[0];
  for(const url of ['http://localhost/','http://foo.localhost/','http://127.0.0.1/','http://[::1]/']) assert.equal(route({url}).type,'direct');
  assert.equal(route({url:'http://100.100.100.100/'}).type,'http');
  assert.equal(route({url:'https://127.example.com/'}).type,'socks');
  const tailnet=route({url:'https://host.example.ts.net/'});
  assert.equal(tailnet.type,'socks');
  assert.equal(tailnet.proxyDNS,true);
});
