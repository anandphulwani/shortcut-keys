# ShortcutKeys

ShortcutKeys is a Windows AutoHotkey v2 utility for sending configured credentials, entering arbitrary text without using the clipboard, and filling matched native Windows dialogs.

## Process architecture

The controller starts all workers once and keeps them waiting on persistent anonymous pipes:

- `shortcut-keys.exe`: controller, hotkeys, tray, rules, and recovery;
- `shortcut-keys-send.exe`: one persistent guarded text worker;
- `shortcut-keys-autofill.exe`: a persistent pool of two native-window workers;
- `shortcut-keys-browser.exe`: one persistent browser-extension bridge, also used as the browser-launched native-messaging host.

Workers handshake before accepting jobs, are reused across jobs, and restart with bounded backoff after a crash or timeout. A Windows Job Object ties their lifetime to the controller. Each connected browser extension also starts a separate native-messaging host process; the extension keeps that connection open. The Task Manager **Processes** view may group workers beneath the controller, while **Details** necessarily shows a PID for every isolated process.

## Hotkeys

| Hotkey | Action |
|---|---|
| `F8` | Send `passwords.password` to the currently focused control |
| `Shift+F8` | Send `passwords.password_Shift` |
| `Alt+F8` | Send `passwords.password_Alt` |
| Hold an F8 combination for 500 ms | Send at 100 ms per grapheme |
| `Ctrl+F8` | Open the keyboard text-entry window; Ctrl+Enter submits |
| Short `F1` | Pause or re-enable automatic filling |
| Long `F1` | Send a normal F1 |
| `Ctrl+Alt+Esc` | Cancel an active Ctrl+F8 text-entry session |

## Security model

`credentials.json.enc` is a versioned AES-256-GCM envelope. Its key is derived with PBKDF2-HMAC-SHA256, a unique 16-byte salt, and 600,000 iterations. A unique 12-byte nonce and 16-byte authentication tag protect every write.

The validated master password can be cached under `HKCU\Software\shortcut-keys` using Windows DPAPI. The encrypted credential file remains portable: another Windows user or machine can unlock it by entering the master password.

The encrypted file is intentionally tracked in this repository. That permits offline password guessing, so use a strong, unique master password. Plaintext exports are never removed automatically.

Worker requests travel through long-lived inherited anonymous pipes. The browser extension's native host connects to the browser worker over a same-user local named pipe. Passwords and entered text do not appear in worker command lines, logs, tooltips, or the clipboard.

## Keyboard text entry and noVNC

The Ctrl+F8 window has three modes. **Foreground keyboard** is the default and activates the original window while it sends keys. **Background control** addresses the captured native Edit, RichEdit, or Scintilla child-control HWND directly, does not activate its window, and does not guard your mouse or keyboard. If the control is unsupported or unavailable, the app asks before switching to foreground mode. **Direct noVNC** sends keys through the connected Proxmox browser console, without activating the browser or using clipboard paste. Select and focus the intended field *inside the guest* before sending.

The delay field accepts 0 to 1000 milliseconds per grapheme and defaults to 30 ms. Use a small value for a responsive session and increase it when the guest drops input. The app acknowledges noVNC key-event submission, not verified entry into the guest field. An unloaded, discarded, disconnected, or view-only console is rejected; minimized browser tabs are best-effort.

All CRLF, LF, CR, and Unicode line separators are normalized, and each newline is sent as an Enter key event. The optional compatibility normalization (enabled by default) converts compatibility-styled Unicode, non-breaking spaces, smart quotes, long dashes, and ellipses to keyboard-friendly plain text. Pasting into the ordinary Edit control already removes rich-text bold, italic, and underline metadata.

**Confirm before sending each next line** is off by default and works in all three modes. When enabled, the first line is sent and a Next line / Cancel window appears before every subsequent line. Ctrl+Alt+Esc cancels the remaining session; an already submitted noVNC batch may finish before cancellation takes effect.

### Direct noVNC setup

1. Build or unpack a distribution. In Edge or Chrome, open the extensions page, enable Developer mode, and load `extension\chromium` unpacked. In Firefox development mode, temporarily load `extension\firefox\manifest.json` from `about:debugging`.
2. Note each Chromium extension ID shown by the browser. Run `install-browser-bridge.ps1` from the distribution with `-ChromeExtensionId <id>`, `-EdgeExtensionId <id>`, and/or `-Firefox`, as applicable. The script registers a per-user native-messaging host; no administrator access is required. Restart the selected browser.
3. Open the extension settings and check **Allow on all websites (HTTP and HTTPS)**, then approve the browser's permission prompt. You can instead authorize exact origins under **Authorize only specific sites**. Open a connected Proxmox noVNC console, focus its guest-side target field, then choose **Direct noVNC** in Ctrl+F8. One eligible console is selected automatically; multiple eligible consoles open a session picker.

Browser host permissions apply by hostname rather than port; website rules still check their configured exact origin, including scheme and port. HTTP sites are supported when explicitly configured, but their credential traffic is not encrypted in transit.

For Edge InPrivate windows, visit `edge://extensions`, open **ShortcutKeys Browser Bridge → Details**, and turn on **Allow in InPrivate**. The extension settings show whether private access is enabled, but extensions cannot turn on that browser-controlled switch themselves. Reload the unpacked extension after updating its files; if you load it from a different folder and its ID changes, rerun `install-browser-bridge.ps1` with the new ID.

The extension supports both Proxmox's bundled `/novnc/app.js` and older split `/novnc/app/ui.js` layouts through noVNC's connected `RFB.sendKey()` API. It imports the page's exact versioned module URL (for example, `?ver=1.6.0-4`) so it reaches the running console rather than a disconnected duplicate. Direct noVNC sends printable US-English ASCII with physical key codes and explicit Shift for capitals and shifted symbols; Enter and Tab have physical codes too. Other Unicode uses noVNC keysyms as a best effort and may depend on guest support. The bundled layout uses noVNC's Latin-1/Unicode keysym fallback because its separate keysym table is not served; the older layout keeps the full table when available. A Proxmox version with a different page integration is reported as incompatible instead of sending blindly. Standard Firefox requires a Mozilla-signed XPI for persistent installation; the packaged Firefox source is a development build.

### Automatic website login

The same extension can fill enabled `target: "browser"` rules on a selected browser tab. The all-websites checkbox grants page access broadly, but credentials are sent only to documents matching an enabled rule's exact HTTP or HTTPS origin; cross-origin iframes must also match `frameOrigin`. Alternatively, authorize individual sites in extension settings. The browser window may be behind another Windows application, but the login tab must be selected within its browser window. Passkeys, MFA, CAPTCHA, and SSO challenges remain manual.

Unlocked browser rules and their resolved values are preloaded into extension memory. Form detection and filling then need no desktop round trip, decryption, clipboard, or intentional delay. This is fast but increases exposure if the browser process is compromised: all approved-site values held in that extension's RAM may be accessible. They are not saved to browser storage. Use **Lock Credentials** in the tray to clear the cache; disconnecting the bridge or removing a site permission also invalidates it. JavaScript cannot guarantee physical zeroization of discarded strings.

`siteCredentials` is an optional map in the encrypted JSON. A browser step's `valueFrom` can point to `siteCredentials.example.username`, `siteCredentials.example.password`, or an existing key such as `passwords.password`. Browser rules keep `match.origin` and optional `pathRegex`; use `frameOrigin` plus optional `framePathRegex` only when the form is inside a separately approved iframe. The example browser rule is disabled until you replace its site and selectors, import/encrypt your edited JSON, and enable it.

The default `autoSubmit: false` fills without clicking Sign in. To submit, set `autoSubmit: true` and add exactly one final `click` step with the submit button's CSS selector. The extension reports **click dispatched; login not verified** after observing a click event; this is not proof that the site accepted the login. If a form replaces the submit control during input, the extension waits up to 1.5 seconds by default for a unique replacement (`timeoutMs` on the step can set 50–5000 ms). A form is attempted once per document; a missing initial field times out after 10 seconds. Hover the extension icon or inspect the extension/content-script console for non-secret failure codes such as `FORM_NOT_READY`, `CONTROL_NOT_UNIQUE_OR_MISSING`, or `SUBMIT_DISABLED`. Browser DOM events are synthetic, so some websites may require a site-specific adapter.

For an ExtJS login button that ignores DOM `click()`, set `"submitMethod": "extjs"` on that final `click` step. The extension looks up the exact button's ExtJS component in the page, checks that it is rendered, visible within the page, and enabled, then fires its `click` event. A ready button is submitted immediately; an unready button is retried every 50 ms for up to 5 seconds (`timeoutMs` may shorten this). This sends only the selector and expected URL to the page-context submit call, not credential values. The result `EXTJS_CLICK_DISPATCHED_UNVERIFIED` still does not prove login succeeded. This method is intended only for pages whose component event path you have tested; ordinary rules continue to use DOM clicks.

## Configuration

See `credentials.example.json`. Rules are evaluated in array order. A rule's `target` is `native` by default and may also be `browser`.

For first-time setup or recovery from a missing/invalid encrypted file, choose **Import and Encrypt JSON...** from the tray, select `credentials.example.json`, and create a new master password twice. The previous encrypted file is backed up, the replacement is written atomically, and it is decrypted again for verification before the import succeeds. A plaintext JSON file must never be renamed directly to `credentials.json.enc`.

The same sample initialization is available from source or a packaged controller with `shortcut-keys.exe --initialize-sample`; the password is requested in local masked dialogs and is never accepted on the command line.

Native rules require one or more of `class`, `titleRegex`, and `process`; all supplied fields must match. Steps run in order and support:

- `setText`, with `textEquals` or `controlExists` verification. Native steps may set `inputMethod` to `direct`, `paste`, or `type`;
- `setChecked`, with `checkedEquals` verification;
- `click`, optionally waiting for `windowClosed`;
- `value` or a dotted `valueFrom` path;
- `dependsOn`, `timeoutMs`, and `retryMs`.

Default control and window waits are 5 seconds with 50 ms retries. Every operation is bound to the exact matched HWND.

For native `setText` steps, `direct` is the backward-compatible default and uses the Windows control API. `paste` temporarily places the value on the clipboard, sends a synchronous paste to the exact control, and immediately restores the prior clipboard contents. `type` sends literal key events and accepts an optional `keyDelayMs` from 0 to 1000 (default 10 ms). Because `paste` necessarily exposes the value to clipboard observers for a short interval, prefer `direct` or `type` when that risk matters.

Native rules may specify `presentation.mode: "offscreen"`. The controller moves a matching HWND beyond the complete virtual desktop immediately inside its create/show event handler, before it queues the autofill job. The worker then fills it and restores its original position and state when appropriate. Both the worker and controller retain restoration paths so a worker timeout or crash does not leave the window offscreen. Windows reports an external application's show event after the window exists, so this is the earliest supported interception point rather than a guarantee that the compositor never draws a frame. This is visual concealment, not a security boundary.

The bundled Radmin rule matches the `#32770` dialog whose title begins with `Radmin security:` (case-insensitively). It intentionally has no process restriction because the authentication dialog can be owned by the Radmin server process rather than `Radmin.exe`. It fills `Edit1` and `Edit2`, checks the Save User control (`Button1`), and submits with `Button2`. Existing dialogs are scanned immediately after credentials are unlocked, so Radmin may be opened before ShortcutKeys starts.

Browser website rules and Direct noVNC share the browser bridge. They do not use the native window hook. Browser steps use CSS `selector` values rather than Windows `control` names.

## Build

Requirements:

- Windows;
- AutoHotkey v2.0.30 x64 and x86 runtimes;
- Ahk2Exe v1.1.37.02a2;
- Node.js for browser-extension tests (not required to run the packaged application).

Build and test both architectures:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\build.ps1 -Architecture all
```

Use `-AutoHotkeyRoot` and `-CompilerPath` for portable tool locations. Outputs are written to `dist/win-x64`, `dist/win-x86`, and zipped under `artifacts/`.
If an existing distribution is running, close it first or use `-OutputRoot` and `-ArtifactRoot` to build into separate directories; the script refuses to remove in-use executables.

## Diagnostics

Redacted rotating logs are stored in `%LOCALAPPDATA%\ShortcutKeys\logs`. If Windows integrity levels prevent automation of an elevated target, restart ShortcutKeys as administrator; the executables do not request elevation automatically.

Migration details are in [MIGRATION.md](MIGRATION.md).
