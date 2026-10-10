# ShortcutKeys

ShortcutKeys is a Windows AutoHotkey v2 utility for sending configured credentials, entering arbitrary text without using the clipboard, and filling matched native Windows dialogs.

## Process architecture

The controller starts all workers once and keeps them waiting on persistent anonymous pipes:

- `shortcut-keys.exe`: controller, hotkeys, tray, rules, and recovery;
- `shortcut-keys-send.exe`: one persistent guarded text worker;
- `shortcut-keys-autofill.exe`: a persistent pool of two native-window workers;
- `shortcut-keys-browser.exe`: one persistent browser-extension bridge.

Workers handshake before accepting jobs, are reused across jobs, and restart with bounded backoff after a crash or timeout. A Windows Job Object ties their lifetime to the controller. The Task Manager **Processes** view may group them beneath the controller, while the **Details** view necessarily shows a PID for every isolated process.

## Hotkeys

| Hotkey | Action |
|---|---|
| `F8` | Send `passwords.password` to the currently focused control |
| `Shift+F8` | Send `passwords.password_Shift` |
| `Alt+F8` | Send `passwords.password_Alt` |
| Hold an F8 combination for 500 ms | Send at 100 ms per grapheme |
| `Ctrl+F8` | Open the text-entry window; Ctrl+Enter submits |
| Short `F1` | Pause or re-enable automatic filling |
| Long `F1` | Send a normal F1 |
| `Ctrl+Alt+Esc` | Cancel guarded Ctrl+F8 input |

## Security model

`credentials.json.enc` is a versioned AES-256-GCM envelope. Its key is derived with PBKDF2-HMAC-SHA256, a unique 16-byte salt, and 600,000 iterations. A unique 12-byte nonce and 16-byte authentication tag protect every write.

The validated master password can be cached under `HKCU\Software\shortcut-keys` using Windows DPAPI. The encrypted credential file remains portable: another Windows user or machine can unlock it by entering the master password.

The encrypted file is intentionally tracked in this repository. That permits offline password guessing, so use a strong, unique master password. Plaintext exports are never removed automatically.

Worker requests travel through long-lived inherited anonymous pipes. Passwords and entered text do not appear in worker command lines, logs, tooltips, or the clipboard.

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

Native rules may specify `presentation.mode: "offscreen"`. The worker moves the exact window beyond the complete virtual desktop, fills it, and restores its original position and state. Both the worker and controller retain restoration paths so a worker timeout or crash does not leave the window offscreen. This is visual concealment, not a security boundary.

The bundled Radmin rule matches the `#32770` dialog whose title begins with `Radmin security:` (case-insensitively). It intentionally has no process restriction because the authentication dialog can be owned by the Radmin server process rather than `Radmin.exe`. It fills `Edit1` and `Edit2`, checks the Save User control (`Button1`), and submits with `Button2`. Existing dialogs are scanned immediately after credentials are unlocked, so Radmin may be opened before ShortcutKeys starts.

Browser rules use an exact HTTPS `origin`, an optional `pathRegex`, CSS `selector` steps, and remain disabled in the example. The persistent browser bridge and protocol boundary are included, but browser rules are not dispatched by the native window hook: secure URL verification and DOM execution require the separately planned ShortcutKeys browser extension. The bridge currently reports that no extension is connected.

## Build

Requirements:

- Windows;
- AutoHotkey v2.0.30 x64 and x86 runtimes;
- Ahk2Exe v1.1.37.02a2.

Build and test both architectures:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\build.ps1 -Architecture all
```

Use `-AutoHotkeyRoot` and `-CompilerPath` for portable tool locations. Outputs are written to `dist/win-x64`, `dist/win-x86`, and zipped under `artifacts/`.

## Diagnostics

Redacted rotating logs are stored in `%LOCALAPPDATA%\ShortcutKeys\logs`. If Windows integrity levels prevent automation of an elevated target, restart ShortcutKeys as administrator; the executables do not request elevation automatically.

Migration details are in [MIGRATION.md](MIGRATION.md).
