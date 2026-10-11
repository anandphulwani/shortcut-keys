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
    .replaceAll('import(modulePath)', 'globalThis.__loadModule(modulePath)')
    .replaceAll('import("/novnc/app.js")', 'globalThis.__loadModule("/novnc/app.js")')
    .replaceAll('import("/novnc/app/ui.js")', 'globalThis.__loadModule("/novnc/app/ui.js")')
    .replaceAll('import("/novnc/core/input/keysymdef.js")', 'globalThis.__loadModule("/novnc/core/input/keysymdef.js")');
  const keyBridge = createBridge({ sourceText: injectedSource });
  const keys = [];
  const keyEvents = [];
  const rfb = { _rfbConnectionState: "connected", viewOnly: false, sendKey(keysym, code, down) {
    keyEvents.push([keysym, code, down]);
    if (keysym !== 0xffe1) keys.push(keysym);
  } };
  keyBridge.context.__testUI = { rfb };
  const modernImports = [];
  keyBridge.context.__loadModule = modulePath => {
    modernImports.push(modulePath);
    return modulePath === "/novnc/app.js" ? Promise.resolve({ default: keyBridge.context.__testUI })
      : Promise.reject(new Error("unexpected split-module import"));
  };
  keyBridge.context.document = { title: "VM console", getElementById(id) { return id === "noVNC_container" ? {} : null; } };
  keyBridge.context.location = { href: "https://pve.example:8006/" };
  assert.equal((await keyBridge.context.probeNoVnc()).eligible, true);
  const accepted = await keyBridge.context.sendNoVnc("{+}\n\t\u03a9", 0, keyBridge.context.location.href);
  assert.equal(accepted.ok, true);
  assert.deepEqual(keys, [123, 43, 125, 0xff0d, 0xff09, 0x010003a9]);
  assert.deepEqual(keyEvents.slice(0, 6), [
    [0xffe1, "ShiftLeft", true], [123, "BracketLeft", undefined], [0xffe1, "ShiftLeft", false],
    [0xffe1, "ShiftLeft", true], [43, "Equal", undefined], [0xffe1, "ShiftLeft", false]
  ], "shifted punctuation must include physical Shift and US key codes");
  assert.deepEqual(keyEvents.slice(9, 11), [[0xff0d, "Enter", undefined], [0xff09, "Tab", undefined]]);
  assert.ok(modernImports.every(modulePath => modulePath === "/novnc/app.js"), "bundled Proxmox fetched a missing split module");
  keys.length = 0;
  keyEvents.length = 0;
  assert.equal((await keyBridge.context.sendNoVnc("aA1!zZ", 0, keyBridge.context.location.href)).ok, true);
  assert.deepEqual(keyEvents, [
    [97, "KeyA", undefined],
    [0xffe1, "ShiftLeft", true], [65, "KeyA", undefined], [0xffe1, "ShiftLeft", false],
    [49, "Digit1", undefined],
    [0xffe1, "ShiftLeft", true], [33, "Digit1", undefined], [0xffe1, "ShiftLeft", false],
    [122, "KeyZ", undefined],
    [0xffe1, "ShiftLeft", true], [90, "KeyZ", undefined], [0xffe1, "ShiftLeft", false]
  ], "uppercase and shifted symbols must be sent like physical US keyboard events");
  keyEvents.length = 0;
  const ascii = Array.from({ length: 95 }, (_, index) => String.fromCharCode(index + 32)).join("");
  assert.equal((await keyBridge.context.sendNoVnc(ascii, 0, keyBridge.context.location.href)).ok, true);
  assert.equal(keyEvents.filter(([, code]) => code !== "ShiftLeft" && !code).length, 0,
    "every printable US ASCII character needs a physical key code");
  assert.equal(keyEvents.filter(([, code, down]) => code === "ShiftLeft" && down === true).length,
    keyEvents.filter(([, code, down]) => code === "ShiftLeft" && down === false).length,
    "Shift must always be released");
  keyEvents.length = 0;
  const plainSymbols = "`1234567890-=[]\\;',./";
  const shiftedSymbols = '~!@#$%^&*()_+{}|:"<>?';
  const symbolCodes = ["Backquote", "Digit1", "Digit2", "Digit3", "Digit4", "Digit5",
    "Digit6", "Digit7", "Digit8", "Digit9", "Digit0", "Minus", "Equal",
    "BracketLeft", "BracketRight", "Backslash", "Semicolon", "Quote", "Comma", "Period", "Slash"];
  assert.equal((await keyBridge.context.sendNoVnc(plainSymbols + shiftedSymbols, 0,
    keyBridge.context.location.href)).ok, true);
  const symbolEvents = keyEvents.filter(([, code]) => code !== "ShiftLeft");
  assert.deepEqual(symbolEvents.map(([, code]) => code), symbolCodes.concat(symbolCodes),
    "all US ASCII punctuation must map to the matching physical key");
  assert.deepEqual(symbolEvents.map(([keysym]) => keysym),
    Array.from(plainSymbols + shiftedSymbols, character => character.charCodeAt(0)));
  assert.equal(keyEvents.filter(([, code, down]) => code === "ShiftLeft" && down === true).length,
    shiftedSymbols.length);
  keyEvents.length = 0;
  const normalSendKey = rfb.sendKey;
  rfb.sendKey = (keysym, code, down) => {
    keyEvents.push([keysym, code, down]);
    if (keysym === 65) throw new Error("synthetic key failure");
  };
  await assert.rejects(keyBridge.context.sendNoVnc("A", 0, keyBridge.context.location.href),
    /synthetic key failure/);
  assert.deepEqual(keyEvents, [
    [0xffe1, "ShiftLeft", true], [65, "KeyA", undefined], [0xffe1, "ShiftLeft", false]
  ], "a failed key send must release Shift");
  rfb.sendKey = normalSendKey;
  keys.length = 0;
  keyEvents.length = 0;
  assert.equal((await keyBridge.context.sendNoVnc("\u{1f512}", 0, keyBridge.context.location.href)).ok, true);
  assert.deepEqual(keys, [0x0101f512], "bundled Proxmox lost a non-BMP Unicode code point");
  assert.deepEqual(keyEvents, [[0x0101f512, null, undefined]], "unmapped Unicode should retain the keysym path");

  const versionedBridge = createBridge({ sourceText: injectedSource });
  const versionedKeys = [];
  const versionedRfb = { _rfbConnectionState: "connected", viewOnly: false,
    sendKey(keysym) { versionedKeys.push(keysym); } };
  const versionedImports = [];
  versionedBridge.context.__loadModule = modulePath => {
    versionedImports.push(modulePath);
    if (modulePath === "/novnc/app.js?ver=1.6.0-4") return Promise.resolve({ default: { rfb: versionedRfb } });
    if (modulePath === "/novnc/app.js") return Promise.resolve({ default: { rfb: undefined } });
    return Promise.reject(new Error("missing module"));
  };
  versionedBridge.context.document = {
    title: "Versioned Proxmox console",
    scripts: [
      { src: "https://pve.example:8006/novnc/app/error-handler.js?ver=1.6.0-4", type: "module" },
      { src: "", type: "module", textContent: 'import UI from "/novnc/app.js?ver=1.6.0-4"; UI.start({});' }
    ],
    getElementById(id) { return id === "noVNC_container" ? {} : null; }
  };
  versionedBridge.context.location = { href: "https://pve.example:8006/?console=kvm" };
  assert.equal((await versionedBridge.context.probeNoVnc()).eligible, true);
  assert.equal((await versionedBridge.context.sendNoVnc("A", 0, versionedBridge.context.location.href)).ok, true);
  assert.deepEqual(versionedKeys, [0xffe1, 65, 0xffe1]);
  assert.deepEqual(versionedImports, ["/novnc/app.js?ver=1.6.0-4", "/novnc/app.js?ver=1.6.0-4"],
    "probe and send must use the page's live, versioned module instance");

  const legacyBridge = createBridge({ sourceText: injectedSource });
  const legacyKeys = [];
  const legacyRfb = { _rfbConnectionState: "connected", viewOnly: false, sendKey(keysym) { legacyKeys.push(keysym); } };
  const legacyImports = [];
  legacyBridge.context.__loadModule = modulePath => {
    legacyImports.push(modulePath);
    if (modulePath === "/novnc/app.js") return Promise.reject(new Error("bundle not installed"));
    if (modulePath === "/novnc/app/ui.js") return Promise.resolve({ default: { rfb: legacyRfb } });
    if (modulePath === "/novnc/core/input/keysymdef.js")
      return Promise.resolve({ default: { lookup(codePoint) { return codePoint === 0x03a9 ? 0x07d9 : codePoint; } } });
    return Promise.reject(new Error("unexpected module"));
  };
  legacyBridge.context.document = { title: "Legacy console", getElementById() { return {}; } };
  legacyBridge.context.location = { href: "https://pve.example:8006/" };
  assert.equal((await legacyBridge.context.probeNoVnc()).eligible, true);
  assert.equal((await legacyBridge.context.sendNoVnc("\u03a9", 0, legacyBridge.context.location.href)).ok, true);
  assert.deepEqual(legacyKeys, [0x07d9]);
  assert.ok(legacyImports.includes("/novnc/app/ui.js") && legacyImports.includes("/novnc/core/input/keysymdef.js"));

  const noConsole = createBridge({ sourceText: injectedSource });
  noConsole.context.__loadModule = () => { throw new Error("non-console page imported noVNC"); };
  noConsole.context.document = { getElementById() { return null; } };
  noConsole.context.location = { href: "https://pve.example:8006/" };
  assert.equal((await noConsole.context.probeNoVnc()).eligible, false);
  assert.equal((await noConsole.context.sendNoVnc("x", 0, noConsole.context.location.href)).code, "NOVNC_UNAVAILABLE");
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
