#Requires AutoHotkey v2.0.30
#SingleInstance Force
#Warn All, OutputDebug
Persistent()

#Include Includes\Jxon.ahk
#Include Includes\App.ahk
#Include Includes\Logger.ahk
#Include Includes\Crypto.ahk
#Include Includes\Config.ahk
#Include Includes\CredentialStore.ahk
#Include Includes\PipeIpc.ahk
#Include Includes\WindowEvents.ahk

class ShortcutKeysApplication {
    __New() {
        this.Logger := AppLogger("main")
        this.Store := CredentialStore(, this.Logger)
        this.Config := ""
        this.AutofillEnabled := true
        this.PendingWindows := Map()
        this.ActiveWindows := Map()
        this.HandledWindows := Map()
        this.WindowRecovery := Map()
        this.Workers := ""
        this.TextGui := ""
        this.TextEdit := ""
        this.TextTargetHwnd := 0
        this.TextTargetControl := ""
        this.PauseGui := ""
        this.ReenableTimer := ""
        this.WindowMonitor := WindowEventMonitor(ObjBindMethod(this, "OnWindowEvent"))
        OnExit(ObjBindMethod(this, "OnExit"))
    }

    Start() {
        this.ConfigureTray()
        try this.StartWorkers()
        catch as caughtError {
            this.Logger.Error("Persistent workers could not start", Map("error", SafeErrorMessage(caughtError)))
            this.Notify("Background workers are unavailable.", 5000)
        }
        try this.UnlockCredentials()
        catch as caughtError {
            this.Logger.Warn("Startup continued with credentials locked", Map("code", caughtError is AppError ? caughtError.Code : Type(caughtError)))
            this.Notify("Credentials are locked. Use the tray menu to unlock them.", 5000)
        }
        try this.WindowMonitor.Start()
        catch as caughtError {
            this.Logger.Error("Window event monitoring could not start", Map("error", SafeErrorMessage(caughtError)))
            this.Notify("Automatic window filling is unavailable.", 5000)
        }
    }

    ConfigureTray() {
        A_TrayMenu.Delete()
        A_TrayMenu.Add("Unlock / Reload Credentials", ObjBindMethod(this, "TrayUnlock"))
        A_TrayMenu.Add("Import and Encrypt JSON...", ObjBindMethod(this, "TrayImport"))
        A_TrayMenu.Add("Export Decrypted JSON...", ObjBindMethod(this, "TrayExport"))
        A_TrayMenu.Add()
        A_TrayMenu.Add("Toggle Automatic Fill", ObjBindMethod(this, "TrayToggleAutofill"))
        A_TrayMenu.Add("Worker Status", ObjBindMethod(this, "TrayWorkerStatus"))
        A_TrayMenu.Add()
        A_TrayMenu.Add("Exit", (*) => ExitApp())
        A_TrayMenu.Default := "Unlock / Reload Credentials"
        try TraySetIcon(A_ScriptDir "\Resources\icons8-bot-48.ico")
    }

    StartWorkers() {
        this.Workers := PersistentWorkerSupervisor(this.Logger)
        send := this.WorkerCommand("send")
        native := this.WorkerCommand("native")
        browser := this.WorkerCommand("browser")
        this.Workers.Register("send", send["executable"], send["script"], 1)
        this.Workers.Register("native", native["executable"], native["script"], 2)
        this.Workers.Register("browser", browser["executable"], browser["script"], 1)
        this.Workers.Start()
    }

    TrayWorkerStatus(*) {
        if !(this.Workers is PersistentWorkerSupervisor) {
            this.Notify("Background workers are unavailable.", 4000)
            return
        }
        status := this.Workers.Status()
        lines := []
        for role in ["send", "native", "browser"] {
            item := status[role]
            lines.Push(role ": " item["ready"] " ready, " item["busy"] " busy, " item["queued"] " queued")
        }
        this.Notify(lines[1] "`n" lines[2] "`n" lines[3], 6000)
    }

    UnlockCredentials() {
        this.Config := this.Store.Unlock(true)
        this.Notify("Credentials unlocked.", 2500)
        this.Logger.Info("Credentials unlocked", Map("schemaVersion", this.Config["schemaVersion"], "autofillRuleCount", this.Config["autofillRules"].Length))
        this.QueueExistingWindows()
    }

    TrayUnlock(*) {
        try this.UnlockCredentials()
        catch as caughtError
            this.ShowError(caughtError)
    }

    TrayImport(*) {
        try {
            source := FileSelect(1, A_ScriptDir "\credentials.example.json", "Select plaintext credential JSON to encrypt", "JSON files (*.json)")
            if source == ""
                return
            password := this.Store.Password
            replacingLockedFile := password == ""
            if replacingLockedFile {
                if FileExist(this.Store.Path) {
                    answer := MsgBox("The current encrypted credential file cannot be reused. Importing will preserve a backup and replace it. Continue?", "Replace encrypted credentials", "YesNo Icon!")
                    if answer != "Yes"
                        return
                }
                password := PromptNewMasterPassword()
            }
            this.Config := this.Store.ImportJson(source, password, true)
            this.Notify("Credential JSON encrypted and verified" (this.Store.LastBackupPath != "" ? "; previous file backed up." : "."), 5000)
        } catch as caughtError {
            this.ShowError(caughtError)
        }
    }

    TrayExport(*) {
        try {
            if !(this.Config is Map)
                this.UnlockCredentials()
            answer := MsgBox("The exported file will contain plaintext credentials. Continue?", "Export credentials", "YesNo Icon!")
            if answer != "Yes"
                return
            destination := FileSelect("S16", A_ScriptDir "\credentials.export.json", "Export decrypted JSON", "JSON files (*.json)")
            if destination == ""
                return
            this.Store.ExportJson(destination)
            this.Notify("Decrypted JSON exported. Protect or remove it when finished.", 6000)
        } catch as caughtError {
            this.ShowError(caughtError)
        }
    }

    TrayToggleAutofill(*) {
        this.AutofillEnabled := !this.AutofillEnabled
        this.Notify("Automatic fill is " (this.AutofillEnabled ? "enabled." : "disabled."), 3000)
    }

    HandleCredentialHotkey(passwordKey) {
        targetHwnd := WinExist("A")
        targetControl := this.GetFocusedControl(targetHwnd)
        started := A_TickCount
        slow := false
        while GetKeyState("F8", "P") {
            if !slow && A_TickCount - started >= 500 {
                slow := true
                SoundBeep(1000, 120)
            }
            Sleep(10)
        }
        try {
            if !(this.Config is Map)
                this.UnlockCredentials()
            passwords := this.Config["passwords"]
            if !passwords.Has(passwordKey)
                throw AppError("The selected password entry is not configured", "PASSWORD_NOT_CONFIGURED")
            this.StartSendWorker(targetHwnd, targetControl, String(passwords[passwordKey]), slow ? 100 : 0, false)
            this.Notify(slow ? "Slow credential entry started." : "Credential entry started.", 2000)
        } catch as caughtError {
            this.ShowError(caughtError)
        }
    }

    HandleTextHotkey() {
        if this.TextGui is Gui {
            try this.TextGui.Show()
            return
        }
        targetHwnd := WinExist("A")
        targetControl := this.GetFocusedControl(targetHwnd)
        windowGui := Gui(, "ShortcutKeys - Text To Send")
        windowGui.SetFont("s10", "Segoe UI")
        windowGui.AddText("w600", "Enter text to send. Press Ctrl+Enter to submit.")
        textControl := windowGui.AddEdit("w600 h160 WantTab")
        ok := windowGui.AddButton("Default w140", "OK")
        cancel := windowGui.AddButton("x+20 w140", "Cancel")
        ok.OnEvent("Click", (*) => this.SubmitTextGui(targetHwnd, targetControl))
        cancel.OnEvent("Click", (*) => this.CloseTextGui())
        windowGui.OnEvent("Close", (*) => this.CloseTextGui())
        windowGui.OnEvent("Escape", (*) => this.CloseTextGui())
        this.TextGui := windowGui, this.TextEdit := textControl, this.TextTargetHwnd := targetHwnd, this.TextTargetControl := targetControl
        windowGui.Show("AutoSize Center")
        textControl.Focus()
    }

    HandleCtrlEnter(keyName) {
        if this.TextGui is Gui && WinActive("ahk_id " this.TextGui.Hwnd) {
            this.SubmitTextGui(this.TextTargetHwnd, this.TextTargetControl)
            return
        }
        SendEvent(keyName == "NumpadEnter" ? "^{NumpadEnter}" : "^{Enter}")
    }

    SubmitTextGui(targetHwnd, targetControl := "") {
        if !(this.TextGui is Gui)
            return
        text := this.TextEdit.Value
        this.CloseTextGui()
        try {
            this.StartSendWorker(targetHwnd, targetControl, text, 90, true)
            this.Notify("Text entry started. Ctrl+Alt+Esc cancels it.", 3000)
        } catch as caughtError {
            this.ShowError(caughtError)
        }
    }

    CloseTextGui() {
        if this.TextGui is Gui
            try this.TextGui.Destroy()
        this.TextGui := "", this.TextEdit := "", this.TextTargetHwnd := 0, this.TextTargetControl := ""
    }

    HandleF1() {
        started := A_TickCount
        longPress := false
        while GetKeyState("F1", "P") {
            if !longPress && A_TickCount - started >= 200 {
                longPress := true
                SoundBeep(1000, 120)
            }
            Sleep(10)
        }
        if longPress {
            SendEvent("{F1}")
            return
        }
        if !this.AutofillEnabled {
            this.EnableAutofill()
            return
        }
        this.ShowPauseGui()
    }

    ShowPauseGui() {
        if this.PauseGui is Gui {
            this.PauseGui.Show()
            return
        }
        windowGui := Gui(, "Pause automatic password fill")
        windowGui.SetFont("s10", "Segoe UI")
        windowGui.AddText("w380", "Re-enable automatic fill after:")
        choices := ["1 Minute", "5 Minutes", "10 Minutes", "30 Minutes", "1 Hour", "5 Hours", "Never"]
        dropdown := windowGui.AddDropDownList("w380 Choose2", choices)
        ok := windowGui.AddButton("Default w140", "OK")
        cancel := windowGui.AddButton("x+20 w140", "Cancel")
        ok.OnEvent("Click", (*) => this.ApplyPauseChoice(dropdown.Text))
        cancel.OnEvent("Click", (*) => this.ClosePauseGui())
        windowGui.OnEvent("Close", (*) => this.ClosePauseGui())
        windowGui.OnEvent("Escape", (*) => this.ClosePauseGui())
        this.PauseGui := windowGui
        windowGui.Show("AutoSize Center")
    }

    ApplyPauseChoice(choice) {
        durations := Map("1 Minute", 60000, "5 Minutes", 300000, "10 Minutes", 600000, "30 Minutes", 1800000, "1 Hour", 3600000, "5 Hours", 18000000, "Never", 0)
        this.ClosePauseGui()
        this.AutofillEnabled := false
        if IsObject(this.ReenableTimer)
            SetTimer(this.ReenableTimer, 0)
        duration := durations[choice]
        if duration {
            this.ReenableTimer := ObjBindMethod(this, "EnableAutofill")
            SetTimer(this.ReenableTimer, -duration)
        } else {
            this.ReenableTimer := ""
        }
        this.Notify("Automatic fill disabled" (duration ? " for " choice "." : " until manually enabled."), 4000)
    }

    ClosePauseGui() {
        if this.PauseGui is Gui
            try this.PauseGui.Destroy()
        this.PauseGui := ""
    }

    EnableAutofill(*) {
        this.AutofillEnabled := true
        this.ReenableTimer := ""
        this.Notify("Automatic fill is enabled.", 3000)
    }

    StartSendWorker(hwnd, targetControl, text, delayMs, guard) {
        if !hwnd || !WinExist("ahk_id " hwnd)
            throw AppError("The selected target window no longer exists", "TARGET_GONE")
        if !(this.Workers is PersistentWorkerSupervisor)
            throw AppError("The send worker is unavailable", "WORKER_UNAVAILABLE")
        payload := Map("targetHwnd", hwnd, "targetControl", targetControl, "text", text, "delayMs", delayMs, "guard", guard ? 1 : 0)
        this.Workers.Submit("send", "send", payload, ObjBindMethod(this, "OnSendComplete"), 70000)
    }

    OnSendComplete(response) {
        if !MapGet(response, "ok", false)
            this.Notify("Text entry failed: " MapGet(response, "code", "UNKNOWN"), 5000)
    }

    GetFocusedControl(hwnd) {
        if !hwnd
            return ""
        try return ControlGetFocus("ahk_id " hwnd)
        catch
            return ""
    }

    QueueExistingWindows() {
        if !(this.Config is Map) || !this.AutofillEnabled
            return
        try {
            for hwnd in WinGetList()
                this.OnWindowEvent(0x8002, hwnd)
        }
    }

    OnWindowEvent(event, hwnd) {
        if event == 0x8001 {
            callback := ""
            if MapTakeIfPresent(this.PendingWindows, hwnd, &callback)
                try SetTimer(callback, 0)
            MapDeleteIfPresent(this.ActiveWindows, hwnd)
            MapDeleteIfPresent(this.HandledWindows, hwnd)
            MapDeleteIfPresent(this.WindowRecovery, hwnd)
            return
        }
        if !this.AutofillEnabled || !(this.Config is Map) || this.PendingWindows.Has(hwnd) || this.ActiveWindows.Has(hwnd) || this.HandledWindows.Has(hwnd)
            return
        callback := ObjBindMethod(this, "EvaluateWindow", hwnd)
        this.PendingWindows[hwnd] := callback
        SetTimer(callback, -250)
    }

    EvaluateWindow(hwnd) {
        ; A destroy event can remove this HWND after the timer was queued but
        ; before its callback begins (or while this thread is interrupted).
        if !MapDeleteIfPresent(this.PendingWindows, hwnd)
            return
        if !this.AutofillEnabled || !WinExist("ahk_id " hwnd)
            return
        for rule in this.Config["autofillRules"] {
            target := StrLower(String(MapGet(rule, "target", "native")))
            if target != "native" || !MapGet(rule, "enabled", true) || !this.RuleMatches(hwnd, rule["match"])
                continue
            resolved := Map()
            for key, value in rule
                resolved[key] := value
            resolvedSteps := []
            for step in rule["steps"]
                resolvedSteps.Push(CredentialConfig.ResolveStep(step, this.Config))
            resolved["steps"] := resolvedSteps
            this.ActiveWindows[hwnd] := true
            if resolved.Has("presentation") && resolved["presentation"] is Map && MapGet(resolved["presentation"], "mode") == "offscreen"
                this.WindowRecovery[hwnd] := this.CaptureWindow(hwnd)
            try {
                if !(this.Workers is PersistentWorkerSupervisor)
                    throw AppError("The native worker pool is unavailable", "WORKER_UNAVAILABLE")
                this.Workers.Submit("native", "autofill", Map("targetHwnd", hwnd, "rule", resolved), ObjBindMethod(this, "OnAutofillComplete", hwnd), 70000)
            }
            catch as caughtError {
                MapDeleteIfPresent(this.ActiveWindows, hwnd)
                this.RestoreWindowIfNeeded(hwnd)
                this.ShowError(caughtError)
            }
            return
        }
    }

    RuleMatches(hwnd, match) {
        try {
            if match.Has("class") && WinGetClass("ahk_id " hwnd) != match["class"]
                return false
            if match.Has("titleRegex") && !RegExMatch(WinGetTitle("ahk_id " hwnd), match["titleRegex"])
                return false
            if match.Has("process") && StrLower(WinGetProcessName("ahk_id " hwnd)) != StrLower(match["process"])
                return false
            return true
        } catch {
            return false
        }
    }

    OnAutofillComplete(hwnd, response) {
        this.RestoreWindowIfNeeded(hwnd)
        MapDeleteIfPresent(this.ActiveWindows, hwnd)
        if WinExist("ahk_id " hwnd)
            this.HandledWindows[hwnd] := true
        if !MapGet(response, "ok", false)
            this.Notify("Automatic fill failed: " MapGet(response, "code", "UNKNOWN"), 5000)
    }

    CaptureWindow(hwnd) {
        WinGetPos(&x, &y, &width, &height, "ahk_id " hwnd)
        return Map("x", x, "y", y, "width", width, "height", height, "state", WinGetMinMax("ahk_id " hwnd))
    }

    RestoreWindowIfNeeded(hwnd) {
        snapshot := ""
        if !MapTakeIfPresent(this.WindowRecovery, hwnd, &snapshot)
            return
        if !WinExist("ahk_id " hwnd)
            return
        try {
            WinGetPos(&x, &y, &width, &height, "ahk_id " hwnd)
            virtualX := DllCall("GetSystemMetrics", "Int", 76, "Int")
            virtualY := DllCall("GetSystemMetrics", "Int", 77, "Int")
            virtualRight := virtualX + DllCall("GetSystemMetrics", "Int", 78, "Int")
            virtualBottom := virtualY + DllCall("GetSystemMetrics", "Int", 79, "Int")
            outside := x + width <= virtualX || x >= virtualRight || y + height <= virtualY || y >= virtualBottom
            if !outside
                return
            WinRestore("ahk_id " hwnd)
            WinMove(snapshot["x"], snapshot["y"], snapshot["width"], snapshot["height"], "ahk_id " hwnd)
            if snapshot["state"] == 1
                WinMaximize("ahk_id " hwnd)
            else if snapshot["state"] == -1
                WinMinimize("ahk_id " hwnd)
        }
    }

    WorkerCommand(kind) {
        name := kind == "send" ? "shortcut-keys-send" : kind == "browser" ? "shortcut-keys-browser" : "shortcut-keys-autofill"
        if A_IsCompiled
            return Map("executable", A_ScriptDir "\" name ".exe", "script", "")
        return Map("executable", A_AhkPath, "script", A_ScriptDir "\" name ".ahk")
    }

    Notify(message, durationMs := 3000) {
        ToolTip(message, A_ScreenWidth - 440, 40)
        SetTimer((*) => ToolTip(), -durationMs)
    }

    ShowError(caughtError) {
        message := SafeErrorMessage(caughtError)
        this.Logger.Error("Operation failed", Map("message", message))
        this.Notify(message, 6000)
    }

    OnExit(reason, code) {
        this.WindowMonitor.Stop()
        if this.Workers is PersistentWorkerSupervisor
            this.Workers.Stop()
        while this.WindowRecovery.Count {
            for hwnd in this.WindowRecovery {
                this.RestoreWindowIfNeeded(hwnd)
                break
            }
        }
        this.Store.ClearMemory()
    }
}

PromptNewMasterPassword() {
    first := InputBox("Create a master password for credentials.json.enc.", "Encrypt ShortcutKeys credentials", "Password w460 h160")
    if first.Result != "OK"
        throw AppError("Credential initialization was canceled", "IMPORT_CANCELED")
    if first.Value == ""
        throw AppError("The master password cannot be empty", "EMPTY_MASTER_PASSWORD")
    second := InputBox("Enter the same master password again.", "Confirm master password", "Password w460 h160")
    if second.Result != "OK"
        throw AppError("Credential initialization was canceled", "IMPORT_CANCELED")
    if first.Value != second.Value
        throw AppError("The master passwords did not match", "PASSWORD_MISMATCH")
    password := first.Value
    first := "", second := ""
    return password
}

InitializeSampleCredentials() {
    samplePath := A_ScriptDir "\credentials.example.json"
    if !FileExist(samplePath) {
        MsgBox("credentials.example.json was not found beside the application.", "ShortcutKeys initialization", "Iconx")
        return 1
    }
    try {
        answer := MsgBox("This will encrypt credentials.example.json as credentials.json.enc. Any existing encrypted file will be backed up first. Continue?", "Initialize sample credentials", "YesNo Icon!")
        if answer != "Yes"
            return 2
        password := PromptNewMasterPassword()
        store := CredentialStore()
        config := store.ImportJson(samplePath, password, true)
        verification := store.TryUnlock(password)
        if !(verification["config"] is Map) || verification["config"]["schemaVersion"] != AppInfo.CredentialSchemaVersion
            throw AppError("The encrypted sample could not be verified", "VERIFY_FAILED")
        store.ClearMemory(), password := "", config := "", verification := ""
        MsgBox("The sample was encrypted and decrypted successfully. You can now use the tray Export and Import actions to replace its values.", "ShortcutKeys initialization", "Iconi")
        return 0
    } catch as caughtError {
        MsgBox(SafeErrorMessage(caughtError), "ShortcutKeys initialization failed", "Iconx")
        return 1
    }
}

if EnvGet("SHORTCUT_KEYS_SELF_TEST") == "1" || HasOption(A_Args, "self-test") || HasOption(A_Args, "--self-test") {
    if !A_IsCompiled
        FileAppend("ShortcutKeys " AppInfo.Version "`n", "*")
    ExitApp()
}

if HasOption(A_Args, "--initialize-sample")
    ExitApp(InitializeSampleCredentials())

global ShortcutKeys := ShortcutKeysApplication()
ShortcutKeys.Start()

$F8::ShortcutKeys.HandleCredentialHotkey("password")
$+F8::ShortcutKeys.HandleCredentialHotkey("password_Shift")
$!F8::ShortcutKeys.HandleCredentialHotkey("password_Alt")
$^F8::ShortcutKeys.HandleTextHotkey()
$F1::ShortcutKeys.HandleF1()
$^Enter::ShortcutKeys.HandleCtrlEnter("Enter")
$^NumpadEnter::ShortcutKeys.HandleCtrlEnter("NumpadEnter")
