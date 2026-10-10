const extensionApi = globalThis.browser ?? globalThis.chrome;
const HOST_NAME = "com.shortcutkeys.bridge";
const ALL_SITE_PATTERNS = ["https://*/*", "http://*/*"];
const permissionPattern = origin => `${new URL(origin).protocol}//${new URL(origin).hostname}/*`;
let nativePort;
let reconnectTimer;
let permissionRefresh = Promise.resolve();
let loginSnapshot = { version: 1, generation: "locked", rules: [] };
let approvedOrigins = new Set();
let allSitesAllowed = false;
const loginDocuments = new Map();
const attemptedDocumentRules = new Set();
let lastLoginResult = "";

function diagnostic(status, code = "", stepId = "") {
  lastLoginResult = [status, code, stepId].filter(Boolean).join(" | ");
  console.info("[ShortcutKeys login]", { status, code, stepId });
  void extensionApi.action?.setTitle?.({ title: `ShortcutKeys: ${lastLoginResult}` });
  void extensionApi.action?.setBadgeText?.({ text: status === "failed" || status === "skipped" ? "!" : "OK" });
}

function forgetAttempts(token) {
  for (const key of attemptedDocumentRules) if (key.startsWith(`${token}:`)) attemptedDocumentRules.delete(key);
}

function originOf(value) {
  try {
    const url = new URL(value);
    return url.protocol === "https:" || url.protocol === "http:" ? url.origin : "";
  } catch { return ""; }
}

function originApproved(origin) {
  return !!origin && originOf(origin) === origin && (allSitesAllowed || approvedOrigins.has(origin));
}

async function refreshApprovedOrigins() {
  const { allowedOrigins = [], allowAllSites = false } = await extensionApi.storage.local.get(["allowedOrigins", "allowAllSites"]);
  const next = new Set();
  for (const origin of allowedOrigins) {
    if (originOf(origin) !== origin) continue;
    if (await extensionApi.permissions.contains({ origins: [permissionPattern(origin)] })) next.add(origin);
  }
  const allGranted = !!allowAllSites && await extensionApi.permissions.contains({ origins: ALL_SITE_PATTERNS });
  approvedOrigins = next;
  allSitesAllowed = allGranted;
  loginSnapshot = { version: 1, generation: "locked", rules: [] };
  if (extensionApi.scripting?.unregisterContentScripts && extensionApi.scripting?.registerContentScripts) {
    try { await extensionApi.scripting.unregisterContentScripts({ ids: ["shortcutkeys-login"] }); } catch {}
    if (allGranted || next.size) {
      await extensionApi.scripting.registerContentScripts([{
        id: "shortcutkeys-login", matches: allGranted ? ALL_SITE_PATTERNS : [...new Set([...next].map(permissionPattern))],
        js: ["login-content.js"], allFrames: true, runAt: "document_start"
      }]);
      const tabs = await extensionApi.tabs.query({});
      for (const tab of tabs) {
        if (!tab.id || !originApproved(originOf(tab.url))) continue;
        try { await extensionApi.scripting.executeScript({ target: { tabId: tab.id, allFrames: true }, files: ["login-content.js"] }); }
        catch { /* A tab may navigate while the script is being installed. */ }
      }
    }
  }
  nativePort?.postMessage({ kind: "permissions", approvedOrigins: [...next], allowAllSites: allGranted });
}

async function safeRefreshApprovedOrigins() {
  try { await refreshApprovedOrigins(); }
  catch {
    approvedOrigins = new Set();
    allSitesAllowed = false;
    loginSnapshot = { version: 1, generation: "locked", rules: [] };
    try { nativePort?.postMessage({ kind: "permissions", approvedOrigins: [], allowAllSites: false }); } catch {}
  }
}

function queuePermissionRefresh() {
  permissionRefresh = permissionRefresh.then(safeRefreshApprovedOrigins, safeRefreshApprovedOrigins);
  return permissionRefresh;
}

function ruleMatches(rule, tab, frameUrl, frameId) {
  const match = rule.match;
  if (!match || !tab?.url || originOf(tab.url) !== match.origin) return false;
  if (match.frameOrigin ? frameId === 0 || originOf(frameUrl) !== match.frameOrigin : frameId !== 0) return false;
  try {
    const top = new URL(tab.url);
    const frame = new URL(frameUrl);
    return (!match.pathRegex || new RegExp(match.pathRegex).test(top.pathname + top.search))
      && (!match.framePathRegex || new RegExp(match.framePathRegex).test(frame.pathname + frame.search));
  } catch { return false; }
}

async function dispatchLoginDocument(documentInfo) {
  if (!loginSnapshot.rules.length || Date.now() > documentInfo.deadline) return;
  let tab;
  try { tab = await extensionApi.tabs.get(documentInfo.tabId); } catch { return; }
  if (!tab?.active || tab.url !== documentInfo.topUrl || !originApproved(originOf(tab.url))
      || !originApproved(originOf(documentInfo.frameUrl))) return;
  const rule = loginSnapshot.rules.find(item => ruleMatches(item, tab, documentInfo.frameUrl, documentInfo.frameId));
  if (!rule || documentInfo.preparedGeneration === loginSnapshot.generation) return;
  documentInfo.preparedGeneration = loginSnapshot.generation;
  clearTimeout(documentInfo.waitTimer);
  try {
    await extensionApi.tabs.sendMessage(documentInfo.tabId, {
      kind: "loginPrepare", token: documentInfo.token, generation: loginSnapshot.generation,
      rule: { id: rule.id, selectors: rule.steps.map(step => step.selector), timeoutMs: 10000 }
    }, { frameId: documentInfo.frameId });
  } catch { diagnostic("skipped", "TARGET_FRAME_UNAVAILABLE"); }
}

async function onLoginReady(message, sender) {
  const tabId = sender.tab?.id;
  const frameId = sender.frameId ?? 0;
  const info = loginDocuments.get(`${tabId}:${frameId}`);
  if (!info || info.token !== message.token || info.documentId !== (sender.documentId ?? "")
      || info.frameUrl !== sender.url || Date.now() > info.deadline
      || message.generation !== loginSnapshot.generation || info.attempted
      || attemptedDocumentRules.has(`${message.token}:${message.ruleId}`)) return { ok: false, code: "DOCUMENT_CHANGED_OR_EXPIRED" };
  let tab;
  try { tab = await extensionApi.tabs.get(tabId); } catch { return { ok: false, code: "TAB_UNAVAILABLE" }; }
  if (!tab?.active || tab.url !== info.topUrl || !originApproved(originOf(tab.url))
      || !originApproved(originOf(sender.url))) return { ok: false, code: "TAB_OR_PERMISSION_CHANGED" };
  const rule = loginSnapshot.rules.find(item => item.id === message.ruleId && ruleMatches(item, tab, sender.url, frameId));
  if (!rule) return { ok: false, code: "RULE_UNAVAILABLE" };
  if (!await extensionApi.permissions.contains({ origins: [permissionPattern(originOf(tab.url))] })) return { ok: false, code: "PERMISSION_REVOKED" };
  if (frameId && !await extensionApi.permissions.contains({ origins: [permissionPattern(originOf(sender.url))] })) return { ok: false, code: "FRAME_PERMISSION_REVOKED" };
  info.attempted = true;
  attemptedDocumentRules.add(`${message.token}:${message.ruleId}`);
  return { ok: true, generation: loginSnapshot.generation, expectedUrl: sender.url,
    steps: rule.steps, autoSubmit: !!rule.autoSubmit };
}

// Runs in the page's MAIN world. Only a selector and URL cross this boundary; no credential does.
function fireExtJsSubmit(selector, expectedUrl) {
  if (location.href !== expectedUrl) return { ok: false, code: "DOCUMENT_CHANGED" };
  let elements;
  try { elements = document.querySelectorAll(selector); }
  catch { return { ok: false, code: "INVALID_SUBMIT_SELECTOR" }; }
  if (elements.length !== 1 || !elements[0].isConnected)
    return { ok: false, code: "EXTJS_COMPONENT_NOT_READY", retryable: true };
  const element = elements[0];
  const component = element.id && globalThis.Ext?.getCmp?.(element.id);
  if (!component || component.destroyed || component.rendered === false)
    return { ok: false, code: "EXTJS_COMPONENT_NOT_READY", retryable: true };
  try {
    if (component.isVisible?.(true) === false || component.isDisabled?.() || component.disabled
        || element.getAttribute("aria-disabled") === "true")
      return { ok: false, code: "EXTJS_COMPONENT_NOT_READY", retryable: true };
    if (typeof component.fireEvent !== "function") return { ok: false, code: "EXTJS_COMPONENT_UNSUPPORTED" };
    component.fireEvent("click", component);
    return { ok: true, code: "EXTJS_CLICK_DISPATCHED_UNVERIFIED" };
  } catch { return { ok: false, code: "EXTJS_SUBMIT_EXCEPTION" }; }
}

async function onLoginExtJsSubmit(message, sender) {
  const tabId = sender.tab?.id;
  const frameId = sender.frameId ?? 0;
  const info = loginDocuments.get(`${tabId}:${frameId}`);
  if (!info || info.token !== message.token || info.documentId !== (sender.documentId ?? "")
      || info.frameUrl !== sender.url || info.topUrl !== sender.tab.url || !info.attempted
      || info.submitClaimed || message.generation !== loginSnapshot.generation
      || message.expectedUrl !== sender.url)
    return { ok: false, code: "DOCUMENT_CHANGED_OR_EXPIRED" };
  const rule = loginSnapshot.rules.find(item => item.id === message.ruleId);
  const step = rule?.steps?.at(-1);
  if (!rule?.autoSubmit || !step || step.id !== message.stepId || step.action !== "click"
      || step.submitMethod !== "extjs") return { ok: false, code: "SUBMIT_METHOD_UNAVAILABLE" };
  info.submitClaimed = true;
  const timeoutMs = Math.max(50, Math.min(5000, Number(step.timeoutMs) || 5000));
  const deadline = Date.now() + timeoutMs;
  do {
    if (loginDocuments.get(`${tabId}:${frameId}`) !== info || loginSnapshot.generation !== message.generation)
      return { ok: false, code: "DOCUMENT_CHANGED_OR_LOCKED" };
    let tab;
    try { tab = await extensionApi.tabs.get(tabId); }
    catch { return { ok: false, code: "TAB_UNAVAILABLE" }; }
    if (!tab?.active || tab.discarded || tab.url !== info.topUrl || !originApproved(originOf(tab.url))
        || !originApproved(originOf(sender.url)) || !ruleMatches(rule, tab, sender.url, frameId))
      return { ok: false, code: "TAB_OR_PERMISSION_CHANGED" };
    if (!await extensionApi.permissions.contains({ origins: [permissionPattern(originOf(tab.url))] })
        || !await extensionApi.permissions.contains({ origins: [permissionPattern(originOf(sender.url))] }))
      return { ok: false, code: "PERMISSION_REVOKED" };
    let injection;
    try {
      [injection] = await extensionApi.scripting.executeScript({ target: { tabId, frameIds: [frameId] },
        world: "MAIN", func: fireExtJsSubmit, args: [step.selector, sender.url] });
    } catch { return { ok: false, code: "EXTJS_INJECTION_FAILED" }; }
    if (injection?.frameId !== undefined && injection.frameId !== frameId
        || injection?.documentId && info.documentId && injection.documentId !== info.documentId)
      return { ok: false, code: "DOCUMENT_CHANGED" };
    const result = injection?.result || { ok: false, code: "EXTJS_INJECTION_FAILED" };
    if (result.ok || !result.retryable) return { ok: !!result.ok, code: result.code };
    if (Date.now() >= deadline) break;
    await new Promise(resolve => setTimeout(resolve, 50));
  } while (Date.now() < deadline);
  return { ok: false, code: "EXTJS_COMPONENT_TIMEOUT" };
}

function onContentMessage(message, sender, sendResponse) {
  if (!message || !sender.tab || !Number.isInteger(sender.frameId)) return;
  const tabId = sender.tab.id;
  const frameId = sender.frameId;
  if (message.kind === "loginDocument" && typeof message.token === "string" && message.token.length <= 100) {
    const key = `${tabId}:${frameId}`;
    const current = loginDocuments.get(key);
    if (current?.token === message.token && current.frameUrl === sender.url && current.topUrl === sender.tab.url) return;
    clearTimeout(current?.waitTimer);
    if (current && current.token !== message.token) forgetAttempts(current.token);
    const info = { tabId, frameId, token: message.token, documentId: sender.documentId ?? "",
      topUrl: sender.tab.url, frameUrl: sender.url, deadline: Date.now() + 10000,
      preparedGeneration: "", attempted: false };
    loginDocuments.set(key, info);
    info.waitTimer = setTimeout(() => {
      if (loginDocuments.get(key) !== info || info.preparedGeneration) return;
      loginDocuments.delete(key);
      diagnostic("skipped", "CREDENTIALS_OR_RULE_UNAVAILABLE");
    }, 10000);
    void dispatchLoginDocument(info);
  } else if (message.kind === "loginReady") {
    void onLoginReady(message, sender).then(sendResponse, () => sendResponse({ ok: false, code: "READY_CHECK_FAILED" }));
    return true;
  } else if (message.kind === "loginExtJsSubmit") {
    void onLoginExtJsSubmit(message, sender).then(sendResponse, () => sendResponse({ ok: false, code: "EXTJS_SUBMIT_FAILED" }));
    return true;
  } else if (message.kind === "loginResult") {
    const info = loginDocuments.get(`${tabId}:${frameId}`);
    if (!info || info.token !== message.token || info.documentId !== (sender.documentId ?? "")) return;
    if (message.result === "submitted") diagnostic("click dispatched; login not verified", message.code || "CLICK_DISPATCHED", message.stepId || "");
    else if (message.result === "filled") diagnostic("filled; not submitted", "FILLED");
    else diagnostic("failed", message.code || "UNKNOWN", message.stepId || "");
  }
}

function browserName() {
  const agent = navigator.userAgent;
  return agent.includes("Firefox/") ? "Firefox" : agent.includes("Edg/") ? "Edge" : "Chrome";
}

function connect() {
  if (nativePort) return;
  try {
    const port = extensionApi.runtime.connectNative(HOST_NAME);
    nativePort = port;
    port.onMessage.addListener(message => { void onNativeMessage(message); });
    port.onDisconnect.addListener(() => {
      if (nativePort === port) nativePort = undefined;
      loginSnapshot = { version: 1, generation: "locked", rules: [] };
      diagnostic("skipped", "BRIDGE_DISCONNECTED");
      clearTimeout(reconnectTimer);
      reconnectTimer = setTimeout(connect, 2000);
    });
    permissionRefresh = queuePermissionRefresh();
    void permissionRefresh.then(() => {
      if (nativePort === port) port.postMessage({ kind: "hello", browser: browserName(), approvedOrigins: [...approvedOrigins], allowAllSites: allSitesAllowed });
    }).catch(() => {});
  } catch {
    clearTimeout(reconnectTimer);
    reconnectTimer = setTimeout(connect, 2000);
  }
}

function probeNoVnc() {
  return import("/novnc/app/ui.js").then(({ default: UI }) => {
    const rfb = UI?.rfb;
    if (!document.getElementById("noVNC_container") || !rfb || rfb._rfbConnectionState !== "connected" || rfb.viewOnly)
      return { eligible: false };
    return { eligible: true, label: document.title.slice(0, 120) || "Proxmox noVNC console" };
  }).catch(() => ({ eligible: false }));
}

async function sendNoVnc(text, delayMs, expectedUrl) {
  if (location.href !== expectedUrl) return { ok: false, code: "BROWSER_SESSION_CHANGED" };
  let UI, keysyms;
  try {
    [{ default: UI }, { default: keysyms }] = await Promise.all([
      import("/novnc/app/ui.js"), import("/novnc/core/input/keysymdef.js")
    ]);
  }
  catch { return { ok: false, code: "NOVNC_UNAVAILABLE" }; }
  const rfb = UI?.rfb;
  if (!document.getElementById("noVNC_container") || !rfb) return { ok: false, code: "NOVNC_UNAVAILABLE" };
  const graphemes = typeof Intl.Segmenter === "function"
    ? Array.from(new Intl.Segmenter(undefined, { granularity: "grapheme" }).segment(text), item => item.segment)
    : Array.from(text);
  for (const grapheme of graphemes) {
    for (const character of grapheme) {
      if (location.href !== expectedUrl) return { ok: false, code: "BROWSER_SESSION_CHANGED" };
      if (UI.rfb !== rfb || rfb._rfbConnectionState !== "connected") return { ok: false, code: "NOVNC_DISCONNECTED" };
      if (rfb.viewOnly) return { ok: false, code: "NOVNC_VIEW_ONLY" };
      const codePoint = character.codePointAt(0);
      let keysym;
      if (character === "\n") keysym = 0xff0d;
      else if (character === "\t") keysym = 0xff09;
      else if (codePoint >= 0x20 && codePoint <= 0x10ffff && (codePoint < 0xd800 || codePoint > 0xdfff)) keysym = keysyms.lookup(codePoint);
      else return { ok: false, code: "NOVNC_UNSUPPORTED_CHARACTER" };
      rfb.sendKey(keysym, null);
    }
    if (delayMs > 0) await new Promise(resolve => setTimeout(resolve, delayMs));
  }
  return { ok: true };
}

async function permittedTab(tab) {
  if (tab.discarded || !tab.url) return false;
  try {
    const url = new URL(tab.url);
    return originApproved(originOf(tab.url))
      && await extensionApi.permissions.contains({ origins: [permissionPattern(url.origin)] });
  } catch { return false; }
}

async function listSessions() {
  await permissionRefresh;
  const tabs = await extensionApi.tabs.query({});
  const sessions = [];
  for (const tab of tabs) {
    if (!await permittedTab(tab)) continue;
    try {
      const [injection] = await extensionApi.scripting.executeScript({ target: { tabId: tab.id }, world: "MAIN", func: probeNoVnc });
      if (injection?.result?.eligible)
        sessions.push({ tabId: tab.id, url: tab.url, label: injection.result.label });
    } catch { /* A page may navigate or reject injection while being probed. */ }
  }
  return sessions;
}

async function send(message) {
  const tab = await extensionApi.tabs.get(message.tabId);
  if (tab.url !== message.expectedUrl || !await permittedTab(tab))
    return { ok: false, code: "BROWSER_SESSION_CHANGED" };
  const [injection] = await extensionApi.scripting.executeScript({
    target: { tabId: tab.id }, world: "MAIN", func: sendNoVnc,
    args: [message.text, message.delayMs, message.expectedUrl]
  });
  return injection?.result ?? { ok: false, code: "NOVNC_UNAVAILABLE" };
}

async function onNativeMessage(message) {
  if (!nativePort) return;
  if (message?.kind === "cacheSnapshot") {
    const snapshot = message.snapshot;
    if (snapshot?.version !== 1 || !Array.isArray(snapshot.rules)) return;
    loginSnapshot = { version: 1, generation: snapshot.generation, rules: snapshot.rules.filter(rule =>
      originApproved(rule.match?.origin) && (!rule.match.frameOrigin || originApproved(rule.match.frameOrigin))) };
    for (const info of loginDocuments.values()) void dispatchLoginDocument(info);
    return;
  }
  if (!message || typeof message.requestId !== "string" || !nativePort) return;
  if (message.kind === "list") {
    const sessions = await listSessions();
    nativePort?.postMessage({ kind: "sessions", requestId: message.requestId, sessions });
  } else if (message.kind === "send") {
    let result;
    try { result = await send(message); }
    catch { result = { ok: false, code: "BROWSER_SEND_FAILED" }; }
    nativePort?.postMessage({ kind: "sent", requestId: message.requestId, ...result });
  }
}

extensionApi.runtime.onStartup?.addListener(connect);
extensionApi.runtime.onInstalled?.addListener(connect);
extensionApi.action.onClicked.addListener(() => extensionApi.runtime.openOptionsPage());
extensionApi.runtime.onMessage.addListener(onContentMessage);
extensionApi.permissions.onAdded?.addListener(() => { void queuePermissionRefresh(); });
extensionApi.permissions.onRemoved?.addListener(() => { void queuePermissionRefresh(); });
extensionApi.storage.onChanged?.addListener((changes, area) => {
  if (area === "local" && (changes.allowedOrigins || changes.allowAllSites)) void queuePermissionRefresh();
});
extensionApi.tabs.onRemoved?.addListener(tabId => {
  for (const [key, info] of loginDocuments) if (key.startsWith(`${tabId}:`)) {
    clearTimeout(info.waitTimer);
    forgetAttempts(info.token);
    loginDocuments.delete(key);
  }
});
extensionApi.tabs.onActivated?.addListener(({ tabId }) => {
  for (const info of loginDocuments.values()) if (info.tabId === tabId) void dispatchLoginDocument(info);
});
connect();
