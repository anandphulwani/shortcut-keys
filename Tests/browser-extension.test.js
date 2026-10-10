const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const source = fs.readFileSync(path.join(__dirname, "..", "extension", "common", "background.js"), "utf8");
const chromiumManifest = JSON.parse(fs.readFileSync(path.join(__dirname, "..", "extension", "chromium", "manifest.json"), "utf8"));
const firefoxManifest = JSON.parse(fs.readFileSync(path.join(__dirname, "..", "extension", "firefox", "manifest.json"), "utf8"));
assert.equal(chromiumManifest.background.service_worker, "background.js");
assert.equal(firefoxManifest.background.scripts[0], "background.js");
assert.ok(chromiumManifest.permissions.includes("nativeMessaging"));
assert.ok(firefoxManifest.permissions.includes("nativeMessaging"));
assert.ok(!chromiumManifest.permissions.includes("tabs") && !firefoxManifest.permissions.includes("tabs"));
for (const manifest of [chromiumManifest, firefoxManifest]) {
  assert.ok(manifest.optional_host_permissions.includes("https://*/*"));
  assert.ok(manifest.optional_host_permissions.includes("http://*/*"));
}

function createBridge({ firefox = false, permission = true, tabs = [], sourceText = source,
  allowAllSites = false, allowedOrigins = ["https://pve.example:8006"] } = {}) {
  const messages = [];
  const injections = [];
  const tabMessages = [];
  const permissionChecks = [];
  const timers = [];
  const port = {
    onMessage: { addListener() {} }, onDisconnect: { addListener() {} },
    postMessage(message) { messages.push(message); }
  };
  const api = {
    runtime: { connectNative() { return port; }, onStartup: { addListener() {} }, onInstalled: { addListener() {} },
      onMessage: { addListener() {} }, openOptionsPage() {} },
    action: { onClicked: { addListener() {} } },
    storage: { local: { async get() { return { allowedOrigins, allowAllSites }; } }, onChanged: { addListener() {} } },
    permissions: { async contains(request) { permissionChecks.push(request); return permission; },
      onAdded: { addListener() {} }, onRemoved: { addListener() {} } },
    tabs: { async query() { return tabs; }, async get(id) { return tabs.find(tab => tab.id === id); },
      async sendMessage(id, message, options) { tabMessages.push({ id, message, options }); } },
    scripting: { async executeScript(options) {
      injections.push(options);
      if (options.func.name === "probeNoVnc") return [{ result: { eligible: true, label: "VM console" } }];
      return [{ result: { ok: true } }];
    } }
  };
  const context = { URL, navigator: { userAgent: firefox ? "Firefox/128" : "Chrome/128" },
    setTimeout(callback, delay) { timers.push(delay); callback(); return 1; }, clearTimeout() {}, console };
  context[firefox ? "browser" : "chrome"] = api;
  vm.createContext(context);
  vm.runInContext(sourceText, context, { filename: "background.js" });
  return { context, messages, injections, tabMessages, permissionChecks, timers };
}

(async () => {
  const tabs = [
    { id: 1, url: "https://pve.example:8006/?console=kvm&vmid=1" },
    { id: 2, url: "https://pve.example:8006/?console=kvm&vmid=2" },
    { id: 3, url: "https://other.example/" }
  ];
  for (const firefox of [false, true]) {
    const bridge = createBridge({ firefox, tabs });
    await bridge.context.onNativeMessage({ kind: "list", requestId: "list-1" });
    assert.equal(bridge.messages.at(-1).sessions.length, 2);
    assert.equal(bridge.injections.length, 2);
    assert.equal(bridge.permissionChecks[0].origins[0], "https://pve.example/*");
    assert.ok(bridge.injections.every(value => value.world === "MAIN"));
    await bridge.context.onNativeMessage({ kind: "send", requestId: "send-1", tabId: 1,
      expectedUrl: tabs[0].url, text: "literal {+} Ω", delayMs: 0 });
    assert.equal(bridge.messages.at(-1).ok, true);
    assert.equal(bridge.injections.at(-1).args[0], "literal {+} Ω");
    await bridge.context.onNativeMessage({ kind: "send", requestId: "send-2", tabId: 1,
      expectedUrl: tabs[1].url, text: "secret", delayMs: 0 });
    assert.equal(bridge.messages.at(-1).code, "BROWSER_SESSION_CHANGED");
  }
  const denied = createBridge({ permission: false, tabs });
  await denied.context.onNativeMessage({ kind: "list", requestId: "denied" });
  assert.equal(denied.messages.at(-1).sessions.length, 0);
  const allSites = createBridge({ allowAllSites: true, allowedOrigins: [], tabs: [
    { id: 4, url: "http://old.example:8080/novnc/" },
    { id: 5, url: "https://new.example/novnc/" }
  ] });
  await allSites.context.onNativeMessage({ kind: "list", requestId: "all-sites" });
  assert.equal(allSites.messages.at(-1).sessions.length, 2);
  assert.ok(allSites.messages.some(message => message.kind === "hello" && message.allowAllSites === true));
  assert.ok(allSites.permissionChecks.some(check => check.origins[0] === "http://old.example/*"));

  const injectedSource = source
    .replaceAll('import("/novnc/app/ui.js")', 'Promise.resolve({ default: globalThis.__testUI })')
    .replaceAll('import("/novnc/core/input/keysymdef.js")', 'Promise.resolve({ default: globalThis.__testKeysyms })');
  const keyBridge = createBridge({ sourceText: injectedSource });
  const keys = [];
  const rfb = { _rfbConnectionState: "connected", viewOnly: false, sendKey(keysym) { keys.push(keysym); } };
  keyBridge.context.__testUI = { rfb };
  keyBridge.context.__testKeysyms = { lookup(codePoint) { return codePoint === 0x03a9 ? 0x07d9 : codePoint; } };
  keyBridge.context.document = { getElementById(id) { return id === "noVNC_container" ? {} : null; } };
  keyBridge.context.location = { href: "https://pve.example:8006/" };
  const accepted = await keyBridge.context.sendNoVnc("{+}\n\tΩ", 0, keyBridge.context.location.href);
  assert.equal(accepted.ok, true);
  assert.deepEqual(keys, [123, 43, 125, 0xff0d, 0xff09, 0x07d9]);
  rfb.viewOnly = true;
  assert.equal((await keyBridge.context.sendNoVnc("x", 0, keyBridge.context.location.href)).code, "NOVNC_VIEW_ONLY");
  rfb.viewOnly = false;
  rfb._rfbConnectionState = "disconnected";
  assert.equal((await keyBridge.context.sendNoVnc("x", 0, keyBridge.context.location.href)).code, "NOVNC_DISCONNECTED");
  assert.equal((await keyBridge.context.sendNoVnc("x", 0, "https://other.example/")).code, "BROWSER_SESSION_CHANGED");
  rfb._rfbConnectionState = "connected";
  keys.length = 0;
  await keyBridge.context.sendNoVnc("e\u0301x", 5, keyBridge.context.location.href);
  assert.deepEqual(keyBridge.timers, [5, 5]);
  assert.equal(keys.length, 3);
  console.log("PASS browser extension permissions, session selection, and noVNC key events");
})().catch(error => { console.error(error); process.exitCode = 1; });
