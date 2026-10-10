/* Website login form watcher. Values arrive only after the exact document is ready. */
if (!globalThis.__shortcutKeysLoginLoaded) {
  globalThis.__shortcutKeysLoginLoaded = true;
  (() => {
    const api = globalThis.browser ?? globalThis.chrome;
    const bytes = new Uint8Array(16);
    crypto.getRandomValues(bytes);
    const token = Array.from(bytes, value => value.toString(16).padStart(2, "0")).join("");
    let prepared;
    let observer;
    let timeout;
    let requested = false;
    let firstUrl = location.href;

    function report(result, code = "", stepId = "") {
      // Never log field values, selectors, or page URLs.
      console.info("[ShortcutKeys login]", { result, code, stepId });
      void api.runtime.sendMessage({ kind: "loginResult", token, result, code, stepId }).catch(() => {});
    }

    function one(selector) {
      try {
        const found = document.querySelectorAll(selector);
        return found.length === 1 ? found[0] : null;
      } catch { return null; }
    }

    function stepFailure(code, stepId = "") {
      const error = new Error(code);
      error.code = code;
      error.stepId = stepId;
      throw error;
    }

    function waitForOne(selector, timeoutMs, stepId) {
      const immediate = one(selector);
      if (immediate?.isConnected !== false) {
        if (immediate) return Promise.resolve(immediate);
      }
      return new Promise((resolve, reject) => {
        let timer;
        const watcher = new MutationObserver(() => {
          const element = one(selector);
          if (!element || element.isConnected === false) return;
          watcher.disconnect();
          clearTimeout(timer);
          resolve(element);
        });
        watcher.observe(document, { childList: true, subtree: true, attributes: true });
        timer = setTimeout(() => {
          watcher.disconnect();
          const error = new Error("CONTROL_NOT_UNIQUE_OR_MISSING");
          error.code = "CONTROL_NOT_UNIQUE_OR_MISSING";
          error.stepId = stepId;
          reject(error);
        }, timeoutMs);
      });
    }

    function stopWatching() {
      observer?.disconnect();
      observer = undefined;
      clearTimeout(timeout);
    }

    function setText(element, value) {
      if (element instanceof HTMLInputElement || element instanceof HTMLTextAreaElement) {
        const prototype = element instanceof HTMLInputElement ? HTMLInputElement.prototype : HTMLTextAreaElement.prototype;
        Object.getOwnPropertyDescriptor(prototype, "value").set.call(element, String(value));
      } else if (element.isContentEditable) {
        element.textContent = String(value);
      } else return false;
      element.dispatchEvent(new Event("input", { bubbles: true }));
      element.dispatchEvent(new Event("change", { bubbles: true }));
      return true;
    }

    function setChecked(element, value) {
      if (!(element instanceof HTMLInputElement) || !["checkbox", "radio"].includes(element.type)) return false;
      Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "checked").set.call(element, !!value);
      element.dispatchEvent(new Event("input", { bubbles: true }));
      element.dispatchEvent(new Event("change", { bubbles: true }));
      return true;
    }

    async function ready() {
      if (!prepared || requested || location.href !== prepared.url) return;
      if (!prepared.selectors.every(selector => one(selector))) return;
      requested = true;
      stopWatching();
      let response;
      try {
        response = await api.runtime.sendMessage({ kind: "loginReady", token,
          generation: prepared.generation, ruleId: prepared.id });
      } catch { report("failed", "EXTENSION_MESSAGE_FAILED"); return; }
      if (!response?.ok || response.generation !== prepared.generation || location.href !== response.expectedUrl) {
        report("failed", response?.code || "READY_REJECTED"); return;
      }
      let currentStepId = "";
      try {
        for (const step of response.steps) {
          currentStepId = String(step.id || "");
          if (location.href !== response.expectedUrl) stepFailure("DOCUMENT_CHANGED", currentStepId);
          const timeoutMs = Math.max(50, Math.min(5000, Number(step.timeoutMs) || 1500));
          const element = await waitForOne(step.selector, timeoutMs, currentStepId);
          if (location.href !== response.expectedUrl) stepFailure("DOCUMENT_CHANGED", currentStepId);
          if (step.action === "setText" && !setText(element, step.value)) stepFailure("UNSUPPORTED_TEXT_CONTROL", currentStepId);
          if (step.action === "setChecked" && !setChecked(element, step.value)) stepFailure("UNSUPPORTED_CHECKBOX", currentStepId);
          if (step.action === "click") {
            if (!response.autoSubmit) stepFailure("SUBMISSION_DISABLED", currentStepId);
            if (step.submitMethod === "extjs") {
              const result = await api.runtime.sendMessage({ kind: "loginExtJsSubmit", token,
                generation: response.generation, ruleId: prepared.id, stepId: currentStepId,
                expectedUrl: response.expectedUrl });
              if (!result?.ok) stepFailure(result?.code || "EXTJS_SUBMIT_FAILED", currentStepId);
              report("submitted", result.code, currentStepId);
              return;
            }
            if (element.disabled || element.getAttribute?.("aria-disabled") === "true") stepFailure("SUBMIT_DISABLED", currentStepId);
            let clickSeen = !element.addEventListener;
            const markClick = () => { clickSeen = true; };
            element.addEventListener?.("click", markClick, { capture: true, once: true });
            try { element.click(); }
            finally { element.removeEventListener?.("click", markClick, true); }
            if (!clickSeen) stepFailure("CLICK_EVENT_NOT_OBSERVED", currentStepId);
            report("submitted", "CLICK_DISPATCHED_UNVERIFIED", currentStepId);
            return;
          }
        }
        report("filled", "FIELDS_FILLED");
      } catch (error) { report("failed", error.code || "STEP_EXCEPTION", error.stepId || currentStepId); }
    }

    function watch(message) {
      if (message.token !== token || requested) return;
      stopWatching();
      prepared = { id: message.rule.id, selectors: message.rule.selectors,
        generation: message.generation, url: location.href };
      timeout = setTimeout(() => { stopWatching(); report("failed", "FORM_NOT_READY"); }, message.rule.timeoutMs);
      observer = new MutationObserver(() => {
        if (location.href !== firstUrl) {
          firstUrl = location.href;
          stopWatching();
          prepared = undefined;
          announce();
        } else void ready();
      });
      observer.observe(document, { childList: true, subtree: true, attributes: true });
      void ready();
    }

    function announce() {
      void api.runtime.sendMessage({ kind: "loginDocument", token }).catch(() => {});
    }

    api.runtime.onMessage.addListener(message => {
      if (message?.kind === "loginPrepare") watch(message);
    });
    addEventListener("popstate", announce);
    addEventListener("hashchange", announce);
    document.addEventListener("DOMContentLoaded", announce, { once: true });
    announce();
  })();
}
