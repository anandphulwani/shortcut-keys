const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const source = fs.readFileSync(path.join(__dirname, "..", "extension", "common", "options.js"), "utf8");
class Element {
  constructor() { this.listeners = {}; this.children = []; this.checked = false; this.textContent = ""; this.className = ""; }
  addEventListener(name, callback) { this.listeners[name] = callback; }
  replaceChildren() { this.children = []; }
  append(...items) { this.children.push(...items); }
  async fire(name, event = {}) { return this.listeners[name](event); }
}

(async () => {
  const elements = Object.fromEntries(["add-form", "origin", "status", "origins", "allow-all-sites", "private-status"]
    .map(id => [id, new Element()]));
  const values = { allowedOrigins: [], allowAllSites: false };
  let permission = false;
  const requested = [];
  const context = { URL, Set, document: { getElementById(id) { return elements[id]; }, createElement() { return new Element(); } },
    window: { addEventListener() {} }, chrome: {
      storage: { local: { async get() { return values; }, async set(next) { Object.assign(values, next); } } },
      permissions: { async contains() { return permission; }, async request(request) {
        requested.push(request.origins); permission = true; return true;
      }, async remove() { permission = false; return true; } },
      extension: { async isAllowedIncognitoAccess() { return false; } }
    } };
  vm.createContext(context);
  vm.runInContext(source, context, { filename: "options.js" });
  await new Promise(resolve => setImmediate(resolve));
  assert.match(elements["private-status"].textContent, /disabled/);
  elements["allow-all-sites"].checked = true;
  await elements["allow-all-sites"].fire("change");
  assert.equal(values.allowAllSites, true);
  assert.deepEqual(Array.from(requested[0]), ["https://*/*", "http://*/*"]);
  assert.equal(elements["allow-all-sites"].checked, true);
  elements["allow-all-sites"].checked = false;
  await elements["allow-all-sites"].fire("change");
  assert.equal(values.allowAllSites, false);
  assert.equal(permission, false);
  console.log("PASS all-website permission opt-in and private-window status");
})().catch(error => { console.error(error); process.exitCode = 1; });
