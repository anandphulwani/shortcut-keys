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
        this.ManualLock := false
        this.AutofillEnabled := true
        this.PendingWindows := Map()
        this.ActiveWindows := Map()
        this.HandledWindows := Map()
        this.WindowRecovery := Map()
        this.Workers := ""
        this.TextGui := ""
        this.TextEdit := ""
        this.TextSpeedEdit := ""
        this.TextModeChoice := ""
        this.TextConfirmCheck := ""
        this.TextNormalizeCheck := ""
        this.TextSendDelayMs := 30
        this.TextSendMode := 1
        this.TextSendSession := ""
        this.LineConfirmGui := ""
        this.BrowserSessionsGui := ""
        this.TextTargetHwnd := 0
        this.TextTargetControl := ""
        this.TextTargetControlHwnd := 0
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
        A_TrayMenu.Add("Lock Credentials", ObjBindMethod(this, "TrayLock"))
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

    UnlockCredentials(manual := false) {
        if this.ManualLock && !manual
            throw AppError("Credentials are locked. Unlock them from the tray menu.", "CREDENTIALS_LOCKED")
        this.Config := this.Store.Unlock(true)
        this.ManualLock := false
        this.SyncBrowserRules()
        this.Notify("Credentials unlocked.", 2500)
        this.Logger.Info("Credentials unlocked", Map("schemaVersion", this.Config["schemaVersion"], "autofillRuleCount", this.Config["autofillRules"].Length))
        this.QueueExistingWindows()
    }

    TrayUnlock(*) {
        this.Logger.Info("Tray credential reload requested")
        try this.UnlockCredentials(true)
        catch as caughtError
            this.ShowError(caughtError)
    }

    TrayLock(*) {
        this.ManualLock := true
        this.Config := ""
        this.Store.ClearMemory()
        this.SyncBrowserRules()
        this.Notify("Credentials locked.", 2500)
    }

    SyncBrowserRules() {
        if !(this.Workers is PersistentWorkerSupervisor)
            return
        rules := []
        if this.AutofillEnabled && this.Config is Map && !this.ManualLock {
            for rule in this.Config["autofillRules"] {
                if StrLower(String(MapGet(rule, "target", "native"))) != "browser" || !MapGet(rule, "enabled", true)
                    continue
                resolved := Map("id", rule["id"], "match", rule["match"], "autoSubmit", MapGet(rule, "autoSubmit", false), "steps", [])
                for step in rule["steps"]
                    resolved["steps"].Push(CredentialConfig.ResolveStep(step, this.Config))
                rules.Push(resolved)
            }
        }
        snapshot := Map("version", 1, "generation", ProcessExist() "-" A_TickCount "-" Random(100000, 999999), "rules", rules)
        try this.Workers.SetControlState("browser", "cacheSnapshot", Map("snapshot", snapshot))
        catch as caughtError
            this.Logger.Warn("Browser rule cache could not be queued", Map("code", caughtError is AppError ? caughtError.Code : Type(caughtError)))
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
            this.ManualLock := false
            this.SyncBrowserRules()
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
        this.SyncBrowserRules()
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
        if this.LineConfirmGui is Gui {
            try this.LineConfirmGui.Show()
            return
        }
        if this.TextSendSession is Map {
            this.Notify("Text entry is already in progress.", 3000)
            return
        }
        if this.TextGui is Gui {
            try this.TextGui.Show()
            return
        }
        targetHwnd := WinExist("A")
        targetControl := this.GetFocusedControl(targetHwnd)
        targetControlHwnd := this.GetFocusedControlHwnd(targetHwnd, targetControl)
        windowGui := Gui(, "ShortcutKeys - Text To Send")
        windowGui.SetFont("s10", "Segoe UI")
        windowGui.AddText("w600", "Enter text to send. Press Ctrl+Enter to submit.")
        textControl := windowGui.AddEdit("w600 h160 WantTab")
        windowGui.AddText("xm y+10", "Send mode:")
        modeChoice := windowGui.AddDropDownList("xm w300 Choose" this.TextSendMode, ["Foreground keyboard", "Background control", "Direct noVNC"])
        windowGui.AddText("xm y+10", "Delay between keyboard events (milliseconds):")
        speedControl := windowGui.AddEdit("xm w90 Number", this.TextSendDelayMs)
        windowGui.AddUpDown("Range0-1000", this.TextSendDelayMs)
        confirmControl := windowGui.AddCheckbox("xm y+10", "Confirm before sending each next line")
        normalizeControl := windowGui.AddCheckbox("xm y+6 Checked", "Normalize formatted Unicode punctuation for keyboard compatibility")
        ok := windowGui.AddButton("xm y+14 Default w140", "Send")
        cancel := windowGui.AddButton("x+20 w140", "Cancel")
        ok.OnEvent("Click", (*) => this.SubmitTextGui(targetHwnd, targetControl))
        cancel.OnEvent("Click", (*) => this.CloseTextGui())
        windowGui.OnEvent("Close", (*) => this.CloseTextGui())
        windowGui.OnEvent("Escape", (*) => this.CloseTextGui())
        this.TextGui := windowGui, this.TextEdit := textControl
        this.TextSpeedEdit := speedControl, this.TextConfirmCheck := confirmControl, this.TextNormalizeCheck := normalizeControl, this.TextModeChoice := modeChoice
        this.TextTargetHwnd := targetHwnd, this.TextTargetControl := targetControl, this.TextTargetControlHwnd := targetControlHwnd
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
        try delayMs := Integer(this.TextSpeedEdit.Value)
        catch {
            this.Notify("The keyboard delay must be a number from 0 to 1000.", 4000)
            return
        }
        if delayMs < 0 || delayMs > 1000 {
            this.Notify("The keyboard delay must be from 0 to 1000 milliseconds.", 4000)
            return
        }
        text := NormalizeLineEndings(this.TextEdit.Value)
        if this.TextNormalizeCheck.Value
            text := NormalizeKeyboardText(text)
        confirmLines := !!this.TextConfirmCheck.Value
        mode := this.TextModeChoice.Value
        this.TextSendDelayMs := delayMs
        this.TextSendMode := mode
        targetControlHwnd := this.TextTargetControlHwnd
        this.CloseTextGui()
        try {
            this.StartTextEntry(targetHwnd, targetControl, targetControlHwnd, text, delayMs, mode, confirmLines)
        } catch as caughtError {
            this.ShowError(caughtError)
        }
    }

    CloseTextGui() {
        if this.TextGui is Gui
            try this.TextGui.Destroy()
        this.TextGui := "", this.TextEdit := "", this.TextSpeedEdit := "", this.TextConfirmCheck := "", this.TextNormalizeCheck := "", this.TextModeChoice := ""
        this.TextTargetHwnd := 0, this.TextTargetControl := "", this.TextTargetControlHwnd := 0
    }

    StartTextEntry(hwnd, targetControl, controlHwnd, text, delayMs, mode, confirmLines) {
        if mode != 3 && (!hwnd || !WinExist("ahk_id " hwnd))
            throw AppError("The selected target window no longer exists", "TARGET_GONE")
        if !(this.Workers is PersistentWorkerSupervisor)
            throw AppError("Background workers are unavailable", "WORKER_UNAVAILABLE")
        if mode == 3 && RegExMatch(text, "[\x00-\x08\x0B-\x1F\x7F]")
            throw AppError("Direct noVNC cannot send this control character", "NOVNC_UNSUPPORTED_CHARACTER")
        this.TextSendSession := Map(
            "targetHwnd", hwnd, "targetControl", targetControl, "controlHwnd", controlHwnd,
            "lines", confirmLines && InStr(text, "`n") ? SplitTextLines(text) : [text],
            "index", 1, "delayMs", delayMs, "mode", mode, "jobId", "", "browserSession", ""
        )
        if mode == 3 {
            session := this.TextSendSession
            session["jobId"] := this.Workers.Submit("browser", "browser", Map("action", "listSessions"), ObjBindMethod(this, "OnBrowserSessions", session), 5000)
            this.Notify("Finding connected noVNC consoles...", 2500)
        } else
            this.SendCurrentSegment()
    }

    OnBrowserSessions(session, response) {
        if this.TextSendSession != session
            return
        session["jobId"] := ""
        if !MapGet(response, "ok", false) {
            this.TextSendSession := ""
            this.OnSendComplete(response)
            return
        }
        sessions := MapGet(response, "sessions", [])
        if sessions.Length == 0 {
            this.TextSendSession := ""
            this.Notify("No connected Proxmox noVNC console is authorized. Check extension settings and connection.", 6500)
        } else if sessions.Length == 1 {
            session["browserSession"] := sessions[1]
            this.SendCurrentSegment()
        } else {
            labels := []
            for item in sessions
                labels.Push(item["label"])
            picker := Gui(, "Choose noVNC console")
            picker.AddText("w540", "Select the connected guest that already has the intended control focused:")
            choice := picker.AddListBox("xm w540 r8 Choose1", labels)
            sendButton := picker.AddButton("xm y+12 Default w120", "Send")
            cancelButton := picker.AddButton("x+16 w120", "Cancel")
            sendButton.OnEvent("Click", (*) => this.SelectBrowserSession(session, sessions, choice.Value))
            cancelButton.OnEvent("Click", (*) => this.CancelTextSending())
            picker.OnEvent("Close", (*) => this.CancelTextSending())
            picker.OnEvent("Escape", (*) => this.CancelTextSending())
            this.BrowserSessionsGui := picker
            picker.Show("AutoSize Center")
        }
    }

    SelectBrowserSession(session, sessions, index) {
        if this.TextSendSession != session || index < 1 || index > sessions.Length
            return
        this.CloseBrowserPicker()
        session["browserSession"] := sessions[index]
        this.SendCurrentSegment()
    }

    CloseBrowserPicker() {
        if this.BrowserSessionsGui is Gui
            try this.BrowserSessionsGui.Destroy()
        this.BrowserSessionsGui := ""
    }

    SendCurrentSegment() {
        if !(this.TextSendSession is Map)
            return
        session := this.TextSendSession
        text := (session["index"] > 1 ? "`n" : "") session["lines"][session["index"]]
        session["currentText"] := text
        try {
            if session["mode"] == 3 {
                session["offset"] := 1
                this.SendBrowserBatch(session)
            } else if session["mode"] == 2 {
                if !session["controlHwnd"]
                    this.OfferForegroundFallback(session)
                else
                    session["jobId"] := this.StartSendWorker(session["targetHwnd"], session["targetControl"], text, session["delayMs"], false, "background", ObjBindMethod(this, "OnTextSegmentComplete", session), session["controlHwnd"])
            } else {
                session["jobId"] := this.StartSendWorker(session["targetHwnd"], session["targetControl"], text, session["delayMs"], true, "keyboard", ObjBindMethod(this, "OnTextSegmentComplete", session))
            }
        } catch as caughtError {
            this.TextSendSession := ""
            this.ShowError(caughtError)
        }
    }

    SendBrowserBatch(session) {
        if this.TextSendSession != session
            return
        text := session["currentText"]
        if session["offset"] > StrLen(text) {
            this.OnTextSegmentComplete(session, Map("ok", 1))
            return
        }
        delayMs := session["delayMs"]
        maxUnits := delayMs == 0 ? 32 : Max(1, Min(16, Floor(250 / delayMs)))
        batch := "", offset := session["offset"]
        while offset <= StrLen(text) && RegExMatch(text, "\X", &match, offset) {
            if batch != "" && StrLen(batch) + match.Len > maxUnits
                break
            batch .= match[0]
            offset += match.Len
            if StrLen(batch) >= maxUnits
                break
        }
        if batch == "" {
            this.TextSendSession := ""
            this.Notify("Text entry failed: NOVNC_UNSUPPORTED_CHARACTER", 5000)
            return
        }
        target := session["browserSession"]
        payload := Map("action", "sendBatch", "sessionId", target["sessionId"], "expectedUrl", target["url"], "text", batch, "delayMs", delayMs)
        timeoutMs := Max(7000, StrLen(batch) * delayMs + 5000)
        session["jobId"] := this.Workers.Submit("browser", "browser", payload, ObjBindMethod(this, "OnBrowserBatchComplete", session, StrLen(batch)), timeoutMs)
    }

    OnBrowserBatchComplete(session, consumed, response) {
        if this.TextSendSession != session
            return
        session["jobId"] := ""
        if !MapGet(response, "ok", false) {
            this.OnTextSegmentComplete(session, response)
            return
        }
        session["offset"] += consumed
        this.SendBrowserBatch(session)
    }

    OnTextSegmentComplete(session, response) {
        if this.TextSendSession != session
            return
        session["jobId"] := ""
        if !MapGet(response, "ok", false) {
            if session["mode"] == 2 && MapGet(response, "code") == "TARGET_CONTROL_UNAVAILABLE" {
                this.OfferForegroundFallback(session, true)
                return
            }
            this.TextSendSession := ""
            this.OnSendComplete(response)
            return
        }
        if session["index"] >= session["lines"].Length {
            this.TextSendSession := ""
            this.Notify(session["mode"] == 3 ? "noVNC accepted the key events; guest entry is not verified." : "Text entry completed.", 4000)
        } else
            this.ShowLineConfirmation()
    }

    OfferForegroundFallback(session, possiblyPartial := false) {
        if this.TextSendSession != session
            return
        warning := possiblyPartial ? "Some text may already have been sent. Remove any partial entry before choosing Yes to resend this line.`n`n" : ""
        answer := MsgBox(warning "This application has no usable background text control. Switch this text entry to foreground keyboard mode? This will activate the original window.", "Background input unavailable", "YesNo Icon!")
        if answer != "Yes" {
            this.CancelTextSending()
            return
        }
        session["mode"] := 1
        this.SendCurrentSegment()
    }

    ShowLineConfirmation() {
        session := this.TextSendSession
        confirmationGui := Gui("+AlwaysOnTop", "Continue text entry")
        confirmationGui.SetFont("s10", "Segoe UI")
        confirmationGui.AddText("w360", "Line " session["index"] " of " session["lines"].Length " was sent. Send the next line?")
        nextButton := confirmationGui.AddButton("xm y+14 Default w140", "Next line")
        cancelButton := confirmationGui.AddButton("x+20 w140", "Cancel")
        nextButton.OnEvent("Click", (*) => this.ContinueConfirmedText())
        cancelButton.OnEvent("Click", (*) => this.CancelConfirmedText())
        confirmationGui.OnEvent("Close", (*) => this.CancelConfirmedText())
        confirmationGui.OnEvent("Escape", (*) => this.CancelConfirmedText())
        this.LineConfirmGui := confirmationGui
        confirmationGui.Show("AutoSize Center")
    }

    ContinueConfirmedText() {
        if !(this.TextSendSession is Map)
            return
        this.CloseLineConfirmation()
        this.TextSendSession["index"] += 1
        this.SendCurrentSegment()
    }

    CancelConfirmedText() {
        this.CancelTextSending()
    }

    CloseLineConfirmation() {
        if this.LineConfirmGui is Gui
            try this.LineConfirmGui.Destroy()
        this.LineConfirmGui := ""
    }

    CancelTextSending() {
        this.CloseLineConfirmation()
        this.CloseBrowserPicker()
        if this.TextSendSession is Map {
            jobId := this.TextSendSession["jobId"]
            this.TextSendSession := ""
            if jobId != "" && this.Workers is PersistentWorkerSupervisor
                this.Workers.Cancel(jobId)
        }
        this.Notify("Text entry canceled.", 3000)
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

    StartSendWorker(hwnd, targetControl, text, delayMs, guard, sendMode := "control", completion := "", targetControlHwnd := 0) {
        if !hwnd || !WinExist("ahk_id " hwnd)
            throw AppError("The selected target window no longer exists", "TARGET_GONE")
        if !(this.Workers is PersistentWorkerSupervisor)
            throw AppError("The send worker is unavailable", "WORKER_UNAVAILABLE")
        timeoutMs := Max(70000, Min(600000, StrLen(text) * (delayMs + 20) + 10000))
        payload := Map(
            "targetHwnd", hwnd, "targetControl", targetControl, "targetControlHwnd", targetControlHwnd, "text", text,
            "delayMs", delayMs, "guard", guard ? 1 : 0, "sendMode", sendMode,
            "timeoutMs", timeoutMs - 5000
        )
        callback := IsObject(completion) ? completion : ObjBindMethod(this, "OnSendComplete")
        return this.Workers.Submit("send", "send", payload, callback, timeoutMs)
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

    GetFocusedControlHwnd(hwnd, control) {
        if !hwnd || control == ""
            return 0
        try return ControlGetHwnd(control, "ahk_id " hwnd)
        catch
            return 0
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
        if !this.AutofillEnabled || !(this.Config is Map) || this.HandledWindows.Has(hwnd)
            return
        ; Move a matched window before the queued worker job. CREATE events can
        ; arrive before the title is ready, so SHOW events retry this even when
        ; an evaluation timer is already pending.
        this.PrepareWindowPresentation(hwnd, event == 0x8002)
        if this.ActiveWindows.Has(hwnd)
            return
        if this.PendingWindows.Has(hwnd)
            return
        callback := ObjBindMethod(this, "EvaluateWindow", hwnd)
        this.PendingWindows[hwnd] := callback
        SetTimer(callback, -1)
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
            if resolved.Has("presentation") && resolved["presentation"] is Map && MapGet(resolved["presentation"], "mode") == "offscreen" && !this.WindowRecovery.Has(hwnd)
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

    PrepareWindowPresentation(hwnd, forceMove := false) {
        if !DllCall("IsWindow", "Ptr", hwnd, "Int")
            return
        if this.WindowRecovery.Has(hwnd) && !forceMove
            return
        for rule in this.Config["autofillRules"] {
            target := StrLower(String(MapGet(rule, "target", "native")))
            if target != "native" || !MapGet(rule, "enabled", true) || !this.RuleMatches(hwnd, rule["match"])
                continue
            presentation := MapGet(rule, "presentation", 0)
            if !(presentation is Map) || StrLower(String(MapGet(presentation, "mode", "normal"))) != "offscreen"
                return
            try {
                alreadyPrepared := this.WindowRecovery.Has(hwnd)
                snapshot := alreadyPrepared ? this.WindowRecovery[hwnd] : this.CaptureWindow(hwnd)
                this.MoveWindowOffscreenNow(hwnd, snapshot, presentation)
                if !alreadyPrepared
                    this.WindowRecovery[hwnd] := snapshot
            }
            return
        }
    }

    MoveWindowOffscreenNow(hwnd, snapshot, presentation) {
        if snapshot["state"] != 0
            WinRestore("ahk_id " hwnd)
        margin := Max(16, Min(1000, Integer(MapGet(presentation, "margin", 64))))
        virtualX := DllCall("GetSystemMetrics", "Int", 76, "Int")
        virtualY := DllCall("GetSystemMetrics", "Int", 77, "Int")
        virtualWidth := DllCall("GetSystemMetrics", "Int", 78, "Int")
        virtualHeight := DllCall("GetSystemMetrics", "Int", 79, "Int")
        edge := StrLower(String(MapGet(presentation, "edge", "top")))
        if edge == "bottom"
            offX := virtualX, offY := virtualY + virtualHeight + margin
        else if edge == "left"
            offX := virtualX - snapshot["width"] - margin, offY := virtualY
        else if edge == "right"
            offX := virtualX + virtualWidth + margin, offY := virtualY
        else
            offX := virtualX, offY := virtualY - snapshot["height"] - margin
        WinMove(offX, offY, snapshot["width"], snapshot["height"], "ahk_id " hwnd)
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
        this.Logger.Info("Shutdown started", Map("reason", reason))
        this.WindowMonitor.Stop()
        this.Logger.Info("Window monitor stopped")
        if this.Workers is PersistentWorkerSupervisor
            this.Workers.Stop()
        this.Logger.Info("Workers stopped")
        while this.WindowRecovery.Count {
            for hwnd in this.WindowRecovery {
                this.RestoreWindowIfNeeded(hwnd)
                break
            }
        }
        this.Store.ClearMemory()
        this.Logger.Info("Shutdown completed")
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
#HotIf ShortcutKeys.TextSendSession is Map
$^!Esc::ShortcutKeys.CancelTextSending()
#HotIf
