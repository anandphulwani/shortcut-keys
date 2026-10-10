const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const { performance } = require("node:perf_hooks");

const backgroundSource = fs.readFileSync(path.join(__dirname, "..", "extension", "common", "background.js"), "utf8");
const contentSource = fs.readFileSync(path.join(__dirname, "..", "extension", "common", "login-content.js"), "utf8");
const tick = () => new Promise(resolve => setImmediate(resolve));

function backgroundHarness({ allSites = false } = {}) {
  const nativeMessages = [];
  const tabMessages = [];
  const registrations = [];
  const injections = [];
  let scriptRunner;
  const allowed = ["https://login.example", "https://auth.example"];
  const tabs = new Map([[1, { id: 1, active: true, url: "https://login.example/sign-in" }]]);
  let reads = 0;
  let disconnect;
  const port = { postMessage(message) { nativeMessages.push(message); }, onMessage: { addListener() {} },
    onDisconnect: { addListener(listener) { disconnect = listener; } } };
  const api = {
    runtime: { connectNative() { return port; }, onMessage: { addListener() {} },
      onStartup: { addListener() {} }, onInstalled: { addListener() {} }, openOptionsPage() {} },
    action: { onClicked: { addListener() {} }, async setTitle() {} },
    storage: { local: { async get() { reads++; return { allowedOrigins: allSites ? [] : allowed, allowAllSites: allSites }; } }, onChanged: { addListener() {} } },
    permissions: { async contains({ origins }) { return allSites || allowed.some(origin => `https://${new URL(origin).hostname}/*` === origins[0]); },
      onAdded: { addListener() {} }, onRemoved: { addListener() {} } },
    tabs: { async query() { return [...tabs.values()]; }, async get(id) { return tabs.get(id); },
      async sendMessage(id, message, options) { tabMessages.push({ id, message, options }); } },
    scripting: { async unregisterContentScripts() {}, async registerContentScripts(items) { registrations.push(items[0]); },
      async executeScript(options) { injections.push(options); return scriptRunner?.(options) ?? []; } }
  };
  const context = { chrome: api, URL, Date, Set, Map, navigator: { userAgent: "Chrome/128" },
    setTimeout(callback, delay) { return delay === 50 ? setTimeout(callback, 0) : 1; }, clearTimeout() {}, console };
  vm.createContext(context);
  vm.runInContext(backgroundSource, context, { filename: "background.js" });
  return { context, api, allowed, tabs, nativeMessages, tabMessages, registrations, injections,
    setScriptRunner(runner) { scriptRunner = runner; }, get reads() { return reads; }, disconnect: () => disconnect() };
}

function sendContent(bridge, message, sender) {
  return new Promise(resolve => {
    const asynchronous = bridge.context.onContentMessage(message, sender, resolve);
    if (asynchronous !== true) resolve(undefined);
  });
}

async function testWarmCache() {
  const bridge = backgroundHarness();
  await tick();
  await bridge.context.refreshApprovedOrigins();
  const rule = { id: "site", match: { origin: "https://login.example", pathRegex: "^/sign-in$",
    frameOrigin: "https://auth.example", framePathRegex: "^/form$" }, autoSubmit: false,
    steps: [{ id: "user", selector: "#user", action: "setText", value: "alice" },
      { id: "pass", selector: "#pass", action: "setText", value: "synthetic-secret" }] };
  await bridge.context.onNativeMessage({ kind: "cacheSnapshot", snapshot: { version: 1, generation: "g1", rules: [rule] } });
  const sender = { tab: { ...bridge.tabs.get(1) }, frameId: 2, documentId: "doc-1", url: "https://auth.example/form" };
  await sendContent(bridge, { kind: "loginDocument", token: "document-token" }, sender);
  await tick();
  assert.equal(bridge.tabMessages.length, 1);
  await sendContent(bridge, { kind: "loginDocument", token: "document-token" }, sender);
  await tick();
  assert.equal(bridge.tabMessages.length, 1, "duplicate page event prepared twice");
  assert.equal(bridge.tabMessages[0].options.frameId, 2);
  assert.deepEqual(Array.from(bridge.tabMessages[0].message.rule.selectors), ["#user", "#pass"]);
  const nativeBefore = bridge.nativeMessages.length;
  const readsBefore = bridge.reads;
  const filled = await sendContent(bridge, { kind: "loginReady", token: "document-token", ruleId: "site", generation: "g1" }, sender);
  assert.equal(filled.ok, true);
  assert.equal(filled.steps[1].value, "synthetic-secret");
  assert.equal(bridge.nativeMessages.length, nativeBefore, "warm fill used native messaging");
  assert.equal(bridge.reads, readsBefore, "warm fill read storage");
  assert.equal((await sendContent(bridge, { kind: "loginReady", token: "document-token", ruleId: "site", generation: "g1" }, sender)).ok, false);
  bridge.disconnect();
  assert.equal((await bridge.context.onLoginReady({ token: "document-token", ruleId: "site", generation: "g1" }, sender)).ok, false);
  assert.equal(bridge.registrations.at(-1).allFrames, true);
}

async function testSafety() {
  const bridge = backgroundHarness();
  await tick();
  await bridge.context.refreshApprovedOrigins();
  const rule = { id: "site", match: { origin: "https://login.example", frameOrigin: "https://auth.example" },
    autoSubmit: false, steps: [{ selector: "#pass", action: "setText", value: "synthetic-secret" }] };
  await bridge.context.onNativeMessage({ kind: "cacheSnapshot", snapshot: { version: 1, generation: "g2", rules: [rule] } });
  const sender = { tab: { ...bridge.tabs.get(1) }, frameId: 3, documentId: "doc-2", url: "https://auth.example/form" };
  await sendContent(bridge, { kind: "loginDocument", token: "token-2" }, sender);
  await tick();
  assert.equal((await sendContent(bridge, { kind: "loginReady", token: "token-2", ruleId: "site", generation: "g2" },
    { ...sender, documentId: "replacement-document" })).ok, false);
  bridge.tabs.get(1).active = false;
  assert.equal((await sendContent(bridge, { kind: "loginReady", token: "token-2", ruleId: "site", generation: "g2" }, sender)).ok, false);
  bridge.tabs.get(1).active = true;
  bridge.allowed.splice(bridge.allowed.indexOf("https://auth.example"), 1);
  await bridge.context.refreshApprovedOrigins();
  assert.equal((await sendContent(bridge, { kind: "loginReady", token: "token-2", ruleId: "site", generation: "g2" }, sender)).ok, false);
}

async function testAllSiteRulesStayExact() {
  const bridge = backgroundHarness({ allSites: true });
  await tick();
  await bridge.context.refreshApprovedOrigins();
  assert.deepEqual(Array.from(bridge.registrations.at(-1).matches), ["https://*/*", "http://*/*"]);
  const rule = { id: "http-site", match: { origin: "http://old.example:8080" }, autoSubmit: false,
    steps: [{ id: "pass", selector: "#pass", action: "setText", value: "synthetic-secret" }] };
  await bridge.context.onNativeMessage({ kind: "cacheSnapshot", snapshot: { version: 1, generation: "http-g1", rules: [rule] } });
  const sender = { tab: { id: 1, active: true, url: "http://old.example:8080/login" },
    frameId: 0, documentId: "http-doc", url: "http://old.example:8080/login" };
  bridge.tabs.set(1, sender.tab);
  await sendContent(bridge, { kind: "loginDocument", token: "http-token" }, sender);
  await tick();
  assert.equal(bridge.tabMessages.length, 1);
  assert.equal((await sendContent(bridge, { kind: "loginReady", token: "http-token", ruleId: "http-site", generation: "http-g1" }, sender)).ok, true);
  bridge.tabs.get(1).url = "http://other.example/login";
  assert.equal((await sendContent(bridge, { kind: "loginReady", token: "http-token", ruleId: "http-site", generation: "http-g1" }, sender)).ok, false);
}

async function testExtJsSubmit() {
  const bridge = backgroundHarness();
  await tick();
  await bridge.context.refreshApprovedOrigins();
  const rule = { id: "ext-site", match: { origin: "https://login.example" }, autoSubmit: true,
    steps: [{ id: "pass", selector: "#pass", action: "setText", value: "synthetic-secret" },
      { id: "submit", selector: "#submit", action: "click", submitMethod: "extjs", timeoutMs: 5000 }] };
  await bridge.context.onNativeMessage({ kind: "cacheSnapshot", snapshot: { version: 1, generation: "ext-g1", rules: [rule] } });
  const sender = { tab: { ...bridge.tabs.get(1) }, frameId: 0, documentId: "ext-doc", url: "https://login.example/sign-in" };
  await sendContent(bridge, { kind: "loginDocument", token: "ext-token" }, sender);
  await tick();
  assert.equal((await sendContent(bridge, { kind: "loginReady", token: "ext-token", ruleId: "ext-site", generation: "ext-g1" }, sender)).ok, true);

  let visible = false;
  let clicks = 0;
  const element = { id: "submit", isConnected: true, getAttribute() { return null; } };
  const component = { rendered: true, isVisible() { return visible; }, isDisabled() { return false; },
    fireEvent(event, target) { assert.equal(event, "click"); assert.equal(target, this); clicks++; } };
  const page = { location: { href: sender.url }, document: { querySelectorAll(selector) { return selector === "#submit" ? [element] : []; } },
    Ext: { getCmp(id) { return id === "submit" ? component : null; } } };
  vm.createContext(page);
  const fireSource = vm.runInContext("fireExtJsSubmit.toString()", bridge.context);
  const fire = vm.runInContext(`(${fireSource})`, page);
  assert.equal(fire("#submit", sender.url).code, "EXTJS_COMPONENT_NOT_READY");
  assert.equal(clicks, 0, "hidden ExtJS component was submitted");
  visible = true;
  assert.equal(fire("#submit", sender.url).code, "EXTJS_CLICK_DISPATCHED_UNVERIFIED");
  assert.equal(clicks, 1);
  assert.equal(fire("#submit", "https://other.example/").code, "DOCUMENT_CHANGED");
  clicks = 0;
  bridge.setScriptRunner(options => [{ frameId: 0, documentId: "ext-doc", result: fire(...options.args) }]);
  const request = { kind: "loginExtJsSubmit", token: "ext-token", ruleId: "ext-site", stepId: "submit",
    generation: "ext-g1", expectedUrl: sender.url };
  assert.equal((await sendContent(bridge, request, sender)).code, "EXTJS_CLICK_DISPATCHED_UNVERIFIED");
  assert.equal(clicks, 1);
  const submitInjections = bridge.injections.filter(item => item.world === "MAIN");
  assert.equal(submitInjections.length, 1, "ready ExtJS component should submit without a delay");
  assert.deepEqual(Array.from(submitInjections[0].target.frameIds), [0]);
  assert.ok(!JSON.stringify(submitInjections[0].args).includes("synthetic-secret"), "credential crossed into page-context submit call");
  assert.equal((await sendContent(bridge, request, sender)).ok, false, "duplicate submit was accepted");

  await sendContent(bridge, { kind: "loginDocument", token: "ext-token-retry" }, sender);
  await tick();
  assert.equal((await sendContent(bridge, { kind: "loginReady", token: "ext-token-retry", ruleId: "ext-site", generation: "ext-g1" }, sender)).ok, true);
  visible = false;
  let attempts = 0;
  bridge.setScriptRunner(options => {
    attempts++;
    const result = fire(...options.args);
    if (attempts === 1) queueMicrotask(() => { visible = true; });
    return [{ frameId: 0, documentId: "ext-doc", result }];
  });
  assert.equal((await sendContent(bridge, { ...request, token: "ext-token-retry" }, sender)).ok, true);
  assert.equal(attempts, 2, "ExtJS readiness was not retried");

  await sendContent(bridge, { kind: "loginDocument", token: "ext-token-switch" }, sender);
  await tick();
  assert.equal((await sendContent(bridge, { kind: "loginReady", token: "ext-token-switch", ruleId: "ext-site", generation: "ext-g1" }, sender)).ok, true);
  visible = false;
  attempts = 0;
  bridge.setScriptRunner(options => {
    attempts++;
    bridge.tabs.get(1).active = false;
    return [{ frameId: 0, documentId: "ext-doc", result: fire(...options.args) }];
  });
  assert.equal((await sendContent(bridge, { ...request, token: "ext-token-switch" }, sender)).code, "TAB_OR_PERMISSION_CHANGED");
  assert.equal(attempts, 1, "submit retried after tab switch");
  bridge.tabs.get(1).active = false;
  assert.equal((await sendContent(bridge, { ...request, token: "wrong-token" }, sender)).ok, false);
}

async function testContentFill(submit = false, submitMethod = "dom") {
  class Input {
    constructor() { this.currentValue = ""; this.events = []; }
    get value() { return this.currentValue; }
    set value(value) { this.currentValue = value; }
    dispatchEvent(event) { this.events.push(event.type); }
  }
  const user = new Input();
  const pass = new Input();
  const button = { clicks: 0, listeners: [], addEventListener(type, callback) { if (type === "click") this.listeners.push(callback); },
    removeEventListener(type, callback) { this.listeners = this.listeners.filter(item => item !== callback); },
    click() { this.clicks++; for (const listener of [...this.listeners]) listener(); } };
  let listener;
  let mutationCallback;
  let fieldsReady = false;
  const results = [];
  const submitRequests = [];
  const api = { runtime: { onMessage: { addListener(callback) { listener = callback; } },
    async sendMessage(message) {
      if (message.kind === "loginDocument") return;
      if (message.kind === "loginResult") { results.push(message.result); return; }
      if (message.kind === "loginExtJsSubmit") { submitRequests.push(message); return { ok: true, code: "EXTJS_CLICK_DISPATCHED_UNVERIFIED" }; }
      if (message.kind === "loginReady") return { ok: true, generation: "g1", expectedUrl: "https://auth.example/form",
        autoSubmit: submit, steps: [{ selector: "#user", action: "setText", value: "alice" },
          { selector: "#pass", action: "setText", value: "synthetic-secret" },
          ...(submit ? [{ selector: "#submit", action: "click", submitMethod }] : [])] };
    } } };
  const context = { chrome: api, globalThis: null, crypto: { getRandomValues(bytes) { bytes.fill(3); } },
    Uint8Array, Array, location: { href: "https://auth.example/form" }, document: {
      querySelectorAll(selector) { return !fieldsReady ? [] : selector === "#user" ? [user] : selector === "#pass" ? [pass] : selector === "#submit" ? [button] : []; },
      addEventListener() {}
    }, HTMLInputElement: Input, HTMLTextAreaElement: class {}, Event: class { constructor(type) { this.type = type; } },
    MutationObserver: class { constructor(callback) { mutationCallback = callback; } observe() {} disconnect() {} }, addEventListener() {},
    setTimeout() { return 1; }, clearTimeout() {}, console: { info() {} } };
  context.globalThis = context;
  vm.createContext(context);
  vm.runInContext(contentSource, context, { filename: "login-content.js" });
  listener({ kind: "loginPrepare", token: "03030303030303030303030303030303", generation: "g1",
    rule: { id: "site", selectors: submit ? ["#user", "#pass", "#submit"] : ["#user", "#pass"], timeoutMs: 10000 } });
  assert.equal(user.value, "");
  fieldsReady = true;
  const started = performance.now();
  mutationCallback();
  await tick();
  const elapsed = performance.now() - started;
  assert.equal(user.value, "alice");
  assert.equal(pass.value, "synthetic-secret");
  assert.deepEqual(results, [submit ? "submitted" : "filled"]);
  assert.equal(button.clicks, submit && submitMethod === "dom" ? 1 : 0);
  assert.equal(submitRequests.length, submit && submitMethod === "extjs" ? 1 : 0);
  assert.equal(submitRequests[0]?.expectedUrl, submitMethod === "extjs" && submit ? "https://auth.example/form" : undefined);
  return elapsed;
}

async function testReplacedSubmit() {
  class Input {
    constructor() { this.currentValue = ""; }
    get value() { return this.currentValue; }
    set value(value) { this.currentValue = value; }
    dispatchEvent() {}
  }
  const user = new Input();
  const pass = new Input();
  let buttonReady = true;
  let mutationCallback;
  let listener;
  const results = [];
  let clicks = 0;
  const button = { addEventListener(type, callback) { this.listener = callback; }, removeEventListener() {},
    click() { clicks++; this.listener(); } };
  pass.dispatchEvent = event => {
    if (event.type === "input") {
      buttonReady = false;
      queueMicrotask(() => { buttonReady = true; mutationCallback(); });
    }
  };
  const api = { runtime: { onMessage: { addListener(callback) { listener = callback; } },
    async sendMessage(message) {
      if (message.kind === "loginResult") { results.push({ result: message.result, code: message.code }); return; }
      if (message.kind === "loginReady") return { ok: true, generation: "g1", expectedUrl: "https://login.example/",
        autoSubmit: true, steps: [{ id: "user", selector: "#user", action: "setText", value: "alice" },
          { id: "pass", selector: "#pass", action: "setText", value: "synthetic-secret" },
          { id: "submit", selector: "#submit", action: "click" }] };
    } } };
  const context = { chrome: api, globalThis: null, crypto: { getRandomValues(bytes) { bytes.fill(4); } },
    Uint8Array, Array, location: { href: "https://login.example/" }, document: {
      querySelectorAll(selector) { return selector === "#user" ? [user] : selector === "#pass" ? [pass]
        : selector === "#submit" && buttonReady ? [button] : []; }, addEventListener() {}
    }, HTMLInputElement: Input, HTMLTextAreaElement: class {}, Event: class { constructor(type) { this.type = type; } },
    MutationObserver: class { constructor(callback) { mutationCallback = callback; } observe() {} disconnect() {} },
    addEventListener() {}, setTimeout() { return 1; }, clearTimeout() {}, console: { info() {} } };
  context.globalThis = context;
  vm.createContext(context);
  vm.runInContext(contentSource, context, { filename: "login-content.js" });
  listener({ kind: "loginPrepare", token: "04040404040404040404040404040404", generation: "g1",
    rule: { id: "site", selectors: ["#user", "#pass", "#submit"], timeoutMs: 10000 } });
  await tick();
  assert.equal(clicks, 1, "replaced submit button was not clicked");
  assert.deepEqual(results, [{ result: "submitted", code: "CLICK_DISPATCHED_UNVERIFIED" }]);
}

(async () => {
  await testWarmCache();
  await testSafety();
  await testAllSiteRulesStayExact();
  const timings = [];
  for (let index = 0; index < 50; index++) timings.push(await testContentFill());
  await testContentFill(true);
  await testContentFill(true, "extjs");
  await testReplacedSubmit();
  await testExtJsSubmit();
  timings.sort((a, b) => a - b);
  const p95 = timings[Math.ceil(timings.length * 0.95) - 1];
  assert.ok(p95 < 100, `Synthetic warm form-fill p95 exceeded 100 ms: ${p95.toFixed(1)} ms`);
  console.log(`PASS warm website login cache, iframe safety, and content filling (synthetic p95 ${p95.toFixed(1)} ms)`);
})().catch(error => { console.error(error); process.exitCode = 1; });
