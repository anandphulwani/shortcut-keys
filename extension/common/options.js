const extensionApi = globalThis.browser ?? globalThis.chrome;
const form = document.getElementById("add-form");
const input = document.getElementById("origin");
const status = document.getElementById("status");
const list = document.getElementById("origins");
const allSites = document.getElementById("allow-all-sites");
const privateStatus = document.getElementById("private-status");
const ALL_SITE_PATTERNS = ["https://*/*", "http://*/*"];
const permissionPattern = origin => `${new URL(origin).protocol}//${new URL(origin).hostname}/*`;

async function render() {
  const { allowedOrigins = [], allowAllSites = false } = await extensionApi.storage.local.get(["allowedOrigins", "allowAllSites"]);
  allSites.checked = !!allowAllSites && await extensionApi.permissions.contains({ origins: ALL_SITE_PATTERNS });
  try {
    const allowed = await extensionApi.extension.isAllowedIncognitoAccess();
    privateStatus.textContent = allowed ? "InPrivate access: enabled." : "InPrivate access: disabled; enable it in Edge extension details.";
  } catch {
    privateStatus.textContent = "Check the browser's extension details to enable private-window access.";
  }
  list.replaceChildren();
  for (const origin of allowedOrigins) {
    const item = document.createElement("li");
    const label = document.createElement("span");
    label.textContent = origin + " ";
    const remove = document.createElement("button");
    remove.type = "button";
    remove.textContent = "Remove";
    remove.addEventListener("click", async () => {
      const next = allowedOrigins.filter(value => value !== origin);
      await extensionApi.storage.local.set({ allowedOrigins: next });
      const stillUsed = next.some(value => permissionPattern(value) === permissionPattern(origin));
      if (!stillUsed) await extensionApi.permissions.remove({ origins: [permissionPattern(origin)] });
      await render();
    });
    item.append(label, remove);
    list.append(item);
  }
}

allSites.addEventListener("change", async () => {
  status.textContent = "";
  status.className = "";
  try {
    if (allSites.checked) {
      const granted = await extensionApi.permissions.request({ origins: ALL_SITE_PATTERNS });
      if (!granted) throw new Error("All-website permission was not granted.");
      await extensionApi.storage.local.set({ allowAllSites: true });
      status.textContent = "All HTTP and HTTPS websites authorized. Only configured rules receive credentials.";
    } else {
      await extensionApi.storage.local.set({ allowAllSites: false });
      await extensionApi.permissions.remove({ origins: ALL_SITE_PATTERNS });
      status.textContent = "All-website access removed. Specific sites may need reauthorization.";
    }
  } catch (error) {
    status.className = "error";
    status.textContent = error.message;
  }
  await render();
});

form.addEventListener("submit", async event => {
  event.preventDefault();
  status.textContent = "";
  status.className = "";
  try {
    const parsed = new URL(input.value.trim());
    if (!["https:", "http:"].includes(parsed.protocol) || parsed.username || parsed.password || parsed.pathname !== "/" || parsed.search || parsed.hash)
      throw new Error("Enter only an HTTP or HTTPS origin, without a path, query, or credentials.");
    const granted = await extensionApi.permissions.request({ origins: [permissionPattern(parsed.origin)] });
    if (!granted) throw new Error("Browser site permission was not granted.");
    const { allowedOrigins = [] } = await extensionApi.storage.local.get("allowedOrigins");
    await extensionApi.storage.local.set({ allowedOrigins: [...new Set([...allowedOrigins, parsed.origin])] });
    input.value = "";
    status.textContent = "Site authorized.";
    await render();
  } catch (error) {
    status.className = "error";
    status.textContent = error.message;
  }
});

void render();
window.addEventListener("focus", () => { void render(); });
