#Requires AutoHotkey v2.0.30
#Warn All, StdOut

#Include ..\Includes\Jxon.ahk
#Include ..\Includes\App.ahk
#Include ..\Includes\Logger.ahk
#Include ..\Includes\Crypto.ahk
#Include ..\Includes\Config.ahk
#Include ..\Includes\CredentialStore.ahk
#Include ..\Includes\PipeIpc.ahk
#Include ..\Includes\BrowserBridgePipe.ahk

class TestSuite {
    __New() {
        this.Passed := 0
        this.Failed := 0
        this.OutputPath := A_ScriptDir "\..\test-results\ahk-" (A_PtrSize * 8) ".txt"
        DirCreate(A_ScriptDir "\..\test-results")
        if FileExist(this.OutputPath)
            FileDelete(this.OutputPath)
    }

    Assert(condition, message) {
        if !condition
            throw Error(message)
    }

    ExpectError(callback, code) {
        try callback.Call()
        catch as caughtError {
            this.Assert(caughtError is AppError, "Expected AppError, got " Type(caughtError))
            this.Assert(caughtError.Code == code, "Expected " code ", got " caughtError.Code)
            return
        }
        throw Error("Expected error " code)
    }

    Run(name, callback) {
        try {
            callback.Call()
            this.Passed++
            this.Log("PASS " name)
        } catch as caughtError {
            this.Failed++
            this.Log("FAIL " name ": " caughtError.Message " @ " caughtError.File ":" caughtError.Line " what=" caughtError.What " extra=" caughtError.Extra)
        }
    }

    Log(message) {
        ; AutoHotkey is a GUI-subsystem executable and may have no stdout when
        ; this test file is launched outside a console.
        try FileAppend(message "`n", "*")
        FileAppend(message "`r`n", this.OutputPath, "UTF-8")
    }

    Finish() {
        this.Log(Format("RESULT passed={} failed={}", this.Passed, this.Failed))
        ExitApp(this.Failed ? 1 : 0)
    }
}

suite := TestSuite()

if HasOption(A_Args, "--browser-only") {
    suite.Run("Browser submission requires explicit final click", (*) => TestBrowserSubmissionValidation(suite))
    suite.Run("HTTP browser rules require exact origins", (*) => TestHttpBrowserRule(suite))
    suite.Run("Browser bridge starts and reports extension state", (*) => TestBrowserWorker(suite))
    suite.Finish()
}

suite.Run("JSON Unicode and escaping", (*) => (
    parsed := JsonLoad('{"message":"hello \u263A","items":[1,2,3]}'),
    suite.Assert(parsed["message"] == "hello ☺", "Unicode escape was not decoded"),
    suite.Assert(JsonLoad(JsonDump(parsed))["items"].Length == 3, "JSON round trip failed")
))

suite.Run("Window-state map cleanup is idempotent", (*) => (
    state := Map(),
    suite.Assert(!MapDeleteIfPresent(state, 2492342), "Deleting an absent HWND should be a no-op"),
    state[2492342] := true,
    suite.Assert(MapDeleteIfPresent(state, 2492342), "An existing HWND was not removed"),
    suite.Assert(!MapDeleteIfPresent(state, 2492342), "Repeated HWND cleanup should be a no-op"),
    state[2492342] := "callback",
    suite.Assert(MapTakeIfPresent(state, 2492342, &removed) && removed == "callback", "Taking an HWND did not return its state"),
    suite.Assert(!MapTakeIfPresent(state, 2492342, &removed), "Repeated HWND take should be a no-op")
))

suite.Run("Keyboard text normalization preserves lines and removes formatting artifacts", (*) => TestKeyboardTextNormalization(suite))
suite.Run("Text-entry edit displays mixed line endings", (*) => TestTextEntryMixedLineEndings(suite))

suite.Run("AES-GCM credential round trip", (*) => (
    plain := '{"schemaVersion":2,"message":"päss 🔐"}',
    envelope := CngCrypto.EncryptText(plain, "correct horse battery staple"),
    suite.Assert(CngCrypto.DecryptEnvelope(envelope, "correct horse battery staple") == plain, "Decrypted text did not match")
))

suite.Run("AES-GCM rejects wrong password", (*) => (
    envelope := CngCrypto.EncryptText("secret", "right"),
    suite.ExpectError((*) => CngCrypto.DecryptEnvelope(envelope, "wrong"), "DECRYPT_FAILED")
))

suite.Run("AES-GCM rejects metadata, ciphertext, and tag tampering", (*) => TestEnvelopeTampering(suite))

suite.Run("DPAPI current-user round trip", (*) => (
    protected := Dpapi.Protect("portable unlock 🔑"),
    suite.Assert(Dpapi.Unprotect(protected) == "portable unlock 🔑", "DPAPI round trip failed")
))

suite.Run("Legacy RC4 decrypt compatibility", (*) => (
    plaintext := '{"passwords":{"password":"legacy"}}',
    password := "legacy-key",
    encrypted := LegacyEncryptForTest(plaintext, password),
    suite.Assert(LegacyCrypto.DecryptHex(encrypted, password) == plaintext, "Legacy decryption did not match")
))

suite.Run("Legacy schema normalization", (*) => (
    legacy := Map(
        "passwords", Map("password", "one", "password_Shift", "two", "password_Alt", "three"),
        "autofill", Map("Radmin security", Map("Login.*", Map("WinMove", "10,20", "Components", Map(
            "Edit1", Map("Type", "Textbox", "Label", "User", "Value", "alice"),
            "Edit2", Map("Type", "Passwordbox", "Label", "Password", "Value", "secret"),
            "Button1", Map("Type", "Button", "Label", "OK", "WaitForWindowClose", 1)
        ))))
    ),
    normalized := CredentialConfig.Normalize(legacy),
    suite.Assert(normalized["migrated"], "Legacy config was not marked migrated"),
    suite.Assert(normalized["config"]["autofillRules"][1]["match"]["class"] == "#32770", "Radmin class was not migrated"),
    suite.Assert(normalized["config"]["autofillRules"][1]["target"] == "native", "Legacy rule target was not migrated"),
    suite.Assert(normalized["config"]["autofillRules"][1]["steps"].Length == 3, "Component order was not preserved")
))
suite.Run("Public native and browser schema example validates", (*) => (
    example := CredentialConfig.Normalize(JsonLoad(FileRead(A_ScriptDir "\..\credentials.example.json", "UTF-8"))),
    suite.Assert(example["config"]["autofillRules"].Length == 2, "Schema example rules were not loaded"),
    suite.Assert(CredentialConfig.ResolvePath(example["config"], "siteCredentials.example.username") == "user@example.com", "Site credential reference failed")
))
suite.Run("Browser submission requires explicit final click", (*) => TestBrowserSubmissionValidation(suite))
suite.Run("HTTP browser rules require exact origins", (*) => TestHttpBrowserRule(suite))
suite.Run("Obsolete bundled Radmin rule is repaired without changing passwords", (*) => TestRadminRuleUpgrade(suite))

suite.Run("Credential atomic write and verification", (*) => TestCredentialStore(suite))
suite.Run("Bundled sample encrypts, decrypts, exports, and preserves a backup", (*) => TestBundledSampleRoundTrip(suite))
suite.Run("Plaintext JSON at encrypted path gives an actionable error", (*) => TestPlaintextAtEncryptedPath(suite))
suite.Run("Legacy credential file migration", (*) => TestLegacyMigration(suite))
suite.Run("Persistent worker handshake, framing, and reuse", (*) => TestWorkerPipe(suite))
suite.Run("Truncated pipe frames are rejected", (*) => TestTruncatedPipe(suite))
suite.Run("Stalled pipe writes return before their deadline", (*) => TestStalledPipeWrite(suite))
suite.Run("Persistent worker timeout and restart are bounded", (*) => TestWorkerTimeout(suite))
suite.Run("Stopping a busy worker does not wait for its pipe", (*) => TestBoundedWorkerStop(suite))
suite.Run("Background control targets exact HWND without focus theft", (*) => TestBackgroundWorker(suite))
suite.Run("Send worker enters literal Unicode", (*) => TestSendWorker(suite))
suite.Run("Native worker pool executes and restores offscreen jobs", (*) => TestAutofillWorker(suite))
suite.Run("Browser bridge starts and reports extension state", (*) => TestBrowserWorker(suite))

suite.Finish()

TestBrowserSubmissionValidation(suite) {
    config := Map("schemaVersion", 2, "passwords", Map("password", "shared"),
        "siteCredentials", Map("site", Map("username", "alice", "password", "synthetic")),
        "autofillRules", [Map("id", "web", "target", "browser", "enabled", 1,
            "match", Map("origin", "https://login.example", "frameOrigin", "https://auth.example"),
            "steps", [Map("id", "user", "selector", "#user", "action", "setText", "valueFrom", "siteCredentials.site.username")])])
    suite.Assert(CredentialConfig.Validate(config), "Browser rule was rejected")
    rule := config["autofillRules"][1]
    rule["autoSubmit"] := true
    suite.ExpectError((*) => CredentialConfig.Validate(config), "INVALID_CONFIG")
    rule["steps"].Push(Map("id", "submit", "selector", "button[type=submit]", "action", "click"))
    suite.Assert(CredentialConfig.Validate(config), "Explicit final submit was rejected")
    rule["steps"][2]["submitMethod"] := "extjs"
    suite.Assert(CredentialConfig.Validate(config), "ExtJS submit method was rejected")
    rule["steps"][2]["submitMethod"] := "invalid"
    suite.ExpectError((*) => CredentialConfig.Validate(config), "INVALID_CONFIG")
    rule["steps"][2]["submitMethod"] := "extjs"
    rule["autoSubmit"] := false
    suite.ExpectError((*) => CredentialConfig.Validate(config), "INVALID_CONFIG")
}

TestHttpBrowserRule(suite) {
    config := Map("schemaVersion", 2, "passwords", Map("password", "synthetic"),
        "autofillRules", [Map("id", "http-site", "target", "browser", "enabled", 1,
            "match", Map("origin", "http://old.example:8080"),
            "steps", [Map("id", "user", "selector", "#user", "action", "setText", "value", "synthetic")])])
    suite.Assert(CredentialConfig.Validate(config), "Exact HTTP browser rule was rejected")
    config["autofillRules"][1]["match"]["origin"] := "http://old.example:8080/login"
    suite.ExpectError((*) => CredentialConfig.Validate(config), "INVALID_CONFIG")
}

TestRadminRuleUpgrade(suite) {
    config := Map(
        "schemaVersion", 2,
        "passwords", Map("password", "keep-me"),
        "autofillRules", [Map(
            "id", "radmin-security", "enabled", 1, "target", "native",
            "match", Map("class", "#32770", "titleRegex", "^Radmin Security.*$", "process", "Radmin.exe"),
            "steps", [
                Map("id", "username", "control", "Edit1", "action", "setText", "value", "username", "verify", "textEquals"),
                Map("id", "password", "control", "Edit2", "action", "setText", "valueFrom", "passwords.password", "verify", "controlExists"),
                Map("id", "submit", "control", "Button1", "action", "click", "dependsOn", "password", "verify", "windowClosed")
            ]
        )]
    )
    normalized := CredentialConfig.Normalize(config)
    rule := normalized["config"]["autofillRules"][1]
    suite.Assert(normalized["migrated"], "Obsolete Radmin sample was not marked for encrypted rewrite")
    suite.Assert(normalized["config"]["passwords"]["password"] == "keep-me", "Password data changed during rule repair")
    suite.Assert(!rule["match"].Has("process") && rule["match"]["titleRegex"] == "i)^Radmin security:", "Radmin match was not repaired")
    suite.Assert(rule["steps"].Length == 4 && rule["steps"][3]["action"] == "setChecked", "Radmin Save User step was not repaired")
    suite.Assert(rule["steps"][4]["control"] == "Button2", "Radmin submit control was not repaired")
}

TestKeyboardTextNormalization(suite) {
    mixedLines := "one`r`ntwo`rthree`n" Chr(0x2028) "five" Chr(0x2029) "six"
    suite.Assert(NormalizeLineEndings(mixedLines) == "one`ntwo`nthree`n`nfive`nsix", "Mixed line endings were not normalized")
    formatted := Chr(0x1D400) Chr(0x00A0) Chr(0x201C) "quoted" Chr(0x201D) Chr(0x2014) "done" Chr(0x2026) Chr(0x200B)
    suite.Assert(NormalizeKeyboardText(formatted) == 'A "quoted"-done...', "Keyboard compatibility normalization failed")
    lines := SplitTextLines("first`r`n`r`nthird`r`n")
    suite.Assert(lines.Length == 4 && lines[1] == "first" && lines[2] == "" && lines[3] == "third" && lines[4] == "", "Line splitting did not preserve empty or trailing lines")
}

TestTextEntryMixedLineEndings(suite) {
    testGui := Gui()
    inputEdit := testGui.AddEdit("w300 h120 WantTab")
    try {
        suite.Assert(EnableMixedLineEndingPaste(inputEdit.Hwnd), "Edit control rejected mixed-line-ending paste styles")
        samples := [
            Map("input", "one`ntwo", "lines", 2),
            Map("input", "one`rtwo", "lines", 2),
            Map("input", "one`r`ntwo", "lines", 2),
            Map("input", "one`ntwo`rthree`r`nfour", "lines", 4)
        ]
        for sample in samples {
            inputEdit.Value := ""
            input := sample["input"]
            ; EM_REPLACESEL inserts without touching the user's clipboard.
            DllCall("user32\SendMessageW", "Ptr", inputEdit.Hwnd, "UInt", 0xC2, "UPtr", 1, "Ptr", StrPtr(input), "Ptr")
            lineCount := DllCall("user32\SendMessageW", "Ptr", inputEdit.Hwnd, "UInt", 0xBA, "UPtr", 0, "Ptr", 0, "Ptr") ; EM_GETLINECOUNT
            suite.Assert(lineCount == sample["lines"], "Edit control displayed " lineCount " lines instead of " sample["lines"])
            suite.Assert(NormalizeLineEndings(inputEdit.Value) == NormalizeLineEndings(input), "Edit control changed pasted text")
        }
    } finally testGui.Destroy()
}

TestCredentialStore(suite) {
    directory := A_Temp "\ShortcutKeysTests-" ProcessExist()
    DirCreate(directory)
    path := directory "\credentials.json.enc"
    config := Map("schemaVersion", 2, "passwords", Map("password", "one"), "autofillRules", [])
    store := CredentialStore(path, AppLogger("tests", directory), false)
    store.Password := "unit-test-password"
    store.SaveConfig(config)
    before := FileRead(path, "UTF-8")
    result := store.TryUnlock("unit-test-password")
    after := FileRead(path, "UTF-8")
    suite.Assert(result["config"]["passwords"]["password"] == "one", "Stored config could not be read")
    suite.Assert(before == after, "Reading unexpectedly changed the encrypted file")
    tempCollision := path "." ProcessExist() ".tmp"
    DirCreate(tempCollision)
    changed := Map("schemaVersion", 2, "passwords", Map("password", "changed"), "autofillRules", [])
    suite.ExpectError((*) => store.SaveConfig(changed), "WRITE_FAILED")
    suite.Assert(FileRead(path, "UTF-8") == before, "A failed atomic write changed the original file")
    DirDelete(tempCollision)
    FileDelete(path)
    DirDelete(directory, true)
}

TestBundledSampleRoundTrip(suite) {
    directory := A_Temp "\ShortcutKeysSampleTests-" ProcessExist()
    DirCreate(directory)
    path := directory "\credentials.json.enc"
    FileAppend("previous encrypted content", path, "UTF-8-RAW")
    store := CredentialStore(path, AppLogger("tests", directory), false)
    try {
        imported := store.ImportJson(A_ScriptDir "\..\credentials.example.json", "sample-round-trip-password", true)
        suite.Assert(store.LastBackupPath != "" && FileExist(store.LastBackupPath), "The previous credential file was not backed up")
        suite.Assert(FileRead(store.LastBackupPath, "UTF-8") == "previous encrypted content", "The credential backup was changed")
        unlocked := store.TryUnlock("sample-round-trip-password")["config"]
        suite.Assert(unlocked["schemaVersion"] == 2, "The encrypted sample did not decrypt")
        suite.Assert(unlocked["passwords"]["password"] == imported["passwords"]["password"], "The sample password field did not round trip")
        exportPath := directory "\credentials.export.json"
        store.Config := unlocked
        store.ExportJson(exportPath)
        exported := JsonLoad(FileRead(exportPath, "UTF-8"))
        suite.Assert(exported["passwords"]["password"] == imported["passwords"]["password"], "The decrypted sample export did not match")
    } finally {
        store.ClearMemory()
        DirDelete(directory, true)
    }
}

TestPlaintextAtEncryptedPath(suite) {
    directory := A_Temp "\ShortcutKeysPlaintextTests-" ProcessExist()
    DirCreate(directory)
    path := directory "\credentials.json.enc"
    FileCopy(A_ScriptDir "\..\credentials.example.json", path)
    store := CredentialStore(path, AppLogger("tests", directory), false)
    try suite.ExpectError((*) => store.TryUnlock("irrelevant"), "PLAINTEXT_CREDENTIAL_FILE")
    finally DirDelete(directory, true)
}

TestLegacyMigration(suite) {
    directory := A_Temp "\ShortcutKeysLegacyTests-" ProcessExist()
    DirCreate(directory)
    path := directory "\credentials.json.enc"
    plaintext := '{"passwords":{"password":"legacy","password_Shift":"two","password_Alt":"three"},"autofill":{}}'
    encrypted := LegacyEncryptForTest(plaintext, "legacy-key")
    FileAppend(encrypted, path, "UTF-8-RAW")
    store := CredentialStore(path, AppLogger("tests", directory), false)
    result := store.TryUnlock("legacy-key")
    store.Password := "legacy-key"
    store.Config := result["config"]
    store.FinalizeMigration(result)
    suite.Assert(FileRead(path ".legacy.bak", "UTF-8") == encrypted, "Legacy backup did not match the source")
    suite.Assert(SubStr(LTrim(FileRead(path, "UTF-8")), 1, 1) == "{", "Migrated file is not a JSON envelope")
    suite.Assert(store.TryUnlock("legacy-key")["config"]["schemaVersion"] == 2, "Migrated file could not be unlocked")
    FileDelete(path), FileDelete(path ".legacy.bak")
    DirDelete(directory, true)
}

TestWorkerPipe(suite) {
    global WorkerResult := ""
    manager := PersistentWorkerSupervisor(AppLogger("tests", A_Temp "\ShortcutKeysTests"))
    manager.Register("send", A_AhkPath, A_ScriptDir "\..\shortcut-keys-send.ahk", 1)
    try {
        manager.Start()
        WaitForWorkers(manager, "send", 1)
        originalPid := manager.Pools["send"][1].ProcessId
        framingText := 'spaces "quotes" {braces}`nUnicode Ω 🔐 '
        Loop 4096
            framingText .= "long"
        manager.Submit("send", "send", Map("targetHwnd", 0, "targetControl", "", "text", framingText, "delayMs", 0, "guard", 0), (response) => WorkerResult := response, 10000)
        WaitForResult(&WorkerResult)
        suite.Assert(!WorkerResult["ok"] && WorkerResult["code"] == "TARGET_GONE", "Unexpected worker response: " JsonDump(WorkerResult))
        WorkerResult := ""
        manager.Submit("send", "invalid", Map("targetHwnd", 0), (response) => WorkerResult := response, 10000)
        WaitForResult(&WorkerResult)
        suite.Assert(!WorkerResult["ok"] && WorkerResult["code"] == "IPC_JOB_TYPE", "Invalid worker job was not rejected")
        suite.Assert(manager.Pools["send"][1].ProcessId == originalPid, "Worker process was not reused")
    } finally {
        manager.Stop()
    }
}

TestTruncatedPipe(suite) {
    path := A_Temp "\ShortcutKeysTruncated-" ProcessExist() ".bin"
    stream := FileOpen(path, "w")
    header := Buffer(4, 0), body := Buffer(2, 65)
    NumPut("UInt", 10, header, 0)
    stream.RawWrite(header, header.Size), stream.RawWrite(body, body.Size), stream.Close()
    stream := FileOpen(path, "r")
    try suite.ExpectError((*) => PipeProtocol.Read(stream), "IPC_TRUNCATED")
    finally stream.Close(), FileDelete(path)
}

TestStalledPipeWrite(suite) {
    readHandle := 0, writeHandle := 0, stream := ""
    if !DllCall("CreatePipe", "Ptr*", &readHandle, "Ptr*", &writeHandle, "Ptr", 0, "UInt", 4096)
        throw OSError(A_LastError, -1, "Could not create test pipe")
    try {
        stream := FileOpen(writeHandle, "h"), writeHandle := 0
        largeValue := ""
        Loop 65536
            largeValue .= "x"
        started := A_TickCount
        suite.ExpectError((*) => PipeProtocol.Write(stream, Map("payload", largeValue), 150), "IPC_WRITE_TIMEOUT")
        suite.Assert(A_TickCount - started < 1000, "A stalled pipe write blocked the caller")
    } finally {
        if stream is File
            stream.Close()
        if writeHandle
            DllCall("CloseHandle", "Ptr", writeHandle)
        if readHandle
            DllCall("CloseHandle", "Ptr", readHandle)
    }
}

TestBoundedWorkerStop(suite) {
    manager := PersistentWorkerSupervisor(AppLogger("tests", A_Temp "\ShortcutKeysTests"))
    manager.Register("hang", A_AhkPath, A_ScriptDir "\hang-worker.ahk", 1)
    try {
        manager.Start()
        WaitForWorkers(manager, "hang", 1)
        workerPid := manager.Pools["hang"][1].ProcessId
        manager.Submit("hang", "hang", Map(),, 10000)
        started := A_TickCount
        manager.Stop()
        suite.Assert(A_TickCount - started < 1500, "Stopping a busy worker blocked the caller")
        suite.Assert(!ProcessExist(workerPid), "Stopping the worker left its process running")
    } finally {
        manager.Stop()
    }
}

TestWorkerTimeout(suite) {
    global TimeoutWorkerResult := ""
    manager := PersistentWorkerSupervisor(AppLogger("tests", A_Temp "\ShortcutKeysTests"))
    manager.Register("hang", A_AhkPath, A_ScriptDir "\hang-worker.ahk", 1)
    try {
        manager.Start()
        WaitForWorkers(manager, "hang", 1)
        originalPid := manager.Pools["hang"][1].ProcessId
        manager.Submit("hang", "hang", Map(), (response) => TimeoutWorkerResult := response, 250)
        WaitForResult(&TimeoutWorkerResult, 3000)
        suite.Assert(!TimeoutWorkerResult["ok"] && TimeoutWorkerResult["code"] == "WORKER_TIMEOUT", "Worker timeout did not return the expected result")
        WaitForWorkers(manager, "hang", 1, 5000)
        suite.Assert(manager.Pools["hang"][1].ProcessId != originalPid, "Timed-out worker was not restarted")
    } finally {
        manager.Stop()
    }
}

TestBackgroundWorker(suite) {
    global BackgroundWorkerResult := ""
    target := Gui(, "ShortcutKeys Background Target")
    targetEdit := target.AddEdit("w300 r4")
    target.Show()
    unrelated := Gui(, "ShortcutKeys Unrelated Target")
    unrelated.AddEdit("w300", "other work")
    unrelated.Show()
    WinActivate("ahk_id " unrelated.Hwnd)
    activeBefore := WinExist("A")
    manager := PersistentWorkerSupervisor(AppLogger("tests", A_Temp "\ShortcutKeysTests"))
    manager.Register("send", A_AhkPath, A_ScriptDir "\..\shortcut-keys-send.ahk", 1)
    try {
        manager.Start()
        WaitForWorkers(manager, "send", 1)
        manager.Submit("send", "send", Map("targetHwnd", target.Hwnd, "targetControlHwnd", targetEdit.Hwnd, "text", "line one`nline two {+}", "delayMs", 1, "guard", 0, "sendMode", "background"), (response) => BackgroundWorkerResult := response, 10000)
        WaitForResult(&BackgroundWorkerResult)
        suite.Assert(BackgroundWorkerResult["ok"] && NormalizeLineEndings(targetEdit.Value) == "line one`nline two {+}", "Exact-HWND background send failed")
        suite.Assert(WinExist("A") == activeBefore, "Background send changed the foreground window")
        BackgroundWorkerResult := ""
        manager.Submit("send", "send", Map("targetHwnd", target.Hwnd, "targetControlHwnd", unrelated.Hwnd, "text", "must not send", "delayMs", 0, "guard", 0, "sendMode", "background"), (response) => BackgroundWorkerResult := response, 10000)
        WaitForResult(&BackgroundWorkerResult)
        suite.Assert(!BackgroundWorkerResult["ok"] && BackgroundWorkerResult["code"] == "TARGET_CONTROL_UNAVAILABLE", "Wrong HWND was accepted")
        suite.Assert(NormalizeLineEndings(targetEdit.Value) == "line one`nline two {+}", "Rejected send changed target text")
    } finally {
        manager.Stop()
        unrelated.Destroy()
        target.Destroy()
    }
}

TestSendWorker(suite) {
    global SendWorkerResult := ""
    testGui := Gui(, "ShortcutKeys Send Worker Test")
    textControl := testGui.AddEdit("w400 r5")
    testGui.Show()
    textControl.Focus()
    manager := PersistentWorkerSupervisor(AppLogger("tests", A_Temp "\ShortcutKeysTests"))
    manager.Register("send", A_AhkPath, A_ScriptDir "\..\shortcut-keys-send.ahk", 1)
    try {
        manager.Start()
        WaitForWorkers(manager, "send", 1)
        otherGui := Gui(, "ShortcutKeys Unrelated Window")
        otherGui.AddEdit("w250", "unrelated work")
        otherGui.Show()
        WinActivate("ahk_id " otherGui.Hwnd)
        activeBefore := WinExist("A")
        manager.Submit("send", "send", Map("targetHwnd", testGui.Hwnd, "targetControlHwnd", textControl.Hwnd, "text", "background {+} text", "delayMs", 0, "guard", 0, "sendMode", "background"), (response) => SendWorkerResult := response, 10000)
        WaitForResult(&SendWorkerResult)
        suite.Assert(SendWorkerResult["ok"], "Background control send failed: " JsonDump(SendWorkerResult))
        suite.Assert(textControl.Value == "background {+} text", "Background control did not receive literal text")
        suite.Assert(WinExist("A") == activeBefore, "Background control send stole foreground focus")
        textControl.Value := "", SendWorkerResult := ""
        manager.Submit("send", "send", Map("targetHwnd", testGui.Hwnd, "targetControlHwnd", otherGui.Hwnd, "text", "must not send", "delayMs", 0, "guard", 0, "sendMode", "background"), (response) => SendWorkerResult := response, 10000)
        WaitForResult(&SendWorkerResult)
        suite.Assert(!SendWorkerResult["ok"] && SendWorkerResult["code"] == "TARGET_CONTROL_UNAVAILABLE", "Mismatched control HWND was not rejected")
        suite.Assert(textControl.Value == "", "Rejected background job still changed target text")
        temporaryGui := Gui(, "ShortcutKeys Destruction Test")
        temporaryControl := temporaryGui.AddEdit("w200")
        temporaryGui.Show()
        SendWorkerResult := ""
        manager.Submit("send", "send", Map("targetHwnd", temporaryGui.Hwnd, "targetControlHwnd", temporaryControl.Hwnd, "text", Format("{:0100}", 1), "delayMs", 20, "guard", 0, "sendMode", "background"), (response) => SendWorkerResult := response, 10000)
        Sleep(100)
        temporaryGui.Destroy()
        WaitForResult(&SendWorkerResult)
        suite.Assert(!SendWorkerResult["ok"] && SendWorkerResult["code"] == "TARGET_GONE", "Destroyed background target did not stop the worker")
        otherGui.Destroy()
        SendWorkerResult := ""
        manager.Submit("send", "send", Map("targetHwnd", testGui.Hwnd, "targetControl", "Edit1", "text", "literal {+} päss 🔐", "delayMs", 0, "guard", 1), (response) => SendWorkerResult := response, 10000)
        WaitForResult(&SendWorkerResult)
        suite.Assert(SendWorkerResult["ok"], "Send worker failed: " JsonDump(SendWorkerResult))
        suite.Assert(textControl.Value == "literal {+} päss 🔐", "Send worker did not preserve literal Unicode text; actual=" textControl.Value)

        textControl.Value := "", SendWorkerResult := ""
        WinActivate("ahk_id " testGui.Hwnd), textControl.Focus(), Sleep(50)
        manager.Submit("send", "send", Map("targetHwnd", testGui.Hwnd, "targetControl", "", "text", "active fallback {+}", "delayMs", 0, "guard", 0), (response) => SendWorkerResult := response, 10000)
        WaitForResult(&SendWorkerResult)
        suite.Assert(SendWorkerResult["ok"], "Active-window fallback failed: " JsonDump(SendWorkerResult))
        suite.Assert(textControl.Value == "active fallback {+}", "Active-window fallback did not send literal text; actual=" textControl.Value)

        textControl.Value := "", SendWorkerResult := ""
        WinActivate("ahk_id " testGui.Hwnd), textControl.Focus(), Sleep(50)
        manager.Submit("send", "send", Map("targetHwnd", testGui.Hwnd, "targetControl", "MissingControl42", "text", "invalid-control fallback", "delayMs", 0, "guard", 0), (response) => SendWorkerResult := response, 10000)
        WaitForResult(&SendWorkerResult)
        suite.Assert(SendWorkerResult["ok"], "Invalid-control fallback failed: " JsonDump(SendWorkerResult))
        suite.Assert(textControl.Value == "invalid-control fallback", "Invalid-control fallback did not send text; actual=" textControl.Value)

        textControl.Value := "", SendWorkerResult := ""
        keyboardText := "first line`r`nsecond {+} ^!#"
        manager.Submit("send", "send", Map(
            "targetHwnd", testGui.Hwnd, "targetControl", "Edit1", "text", keyboardText,
            "delayMs", 1, "guard", 1, "sendMode", "keyboard", "timeoutMs", 10000
        ), (response) => SendWorkerResult := response, 15000)
        WaitForResult(&SendWorkerResult, 15000)
        suite.Assert(SendWorkerResult["ok"], "Keyboard-event worker mode failed: " JsonDump(SendWorkerResult))
        suite.Assert(NormalizeLineEndings(textControl.Value) == NormalizeLineEndings(keyboardText), "Keyboard mode did not preserve newlines or literal special characters; actual=" textControl.Value)
    } finally {
        manager.Stop()
        testGui.Destroy()
    }
}

TestAutofillWorker(suite) {
    global AutofillWorkerResult := ""
    testGui := Gui(, "ShortcutKeys Autofill Worker Test")
    pastedControl := testGui.AddEdit("w400", "replace pasted text")
    typedControl := testGui.AddEdit("w400", "replace typed text")
    checkbox := testGui.AddCheckbox(, "Enabled")
    testGui.Show("x220 y220")
    WinGetPos(&originalX, &originalY,,, "ahk_id " testGui.Hwnd)
    clipboardMarker := "clipboard must survive autofill"
    savedClipboard := ClipboardAll()
    A_Clipboard := clipboardMarker
    rule := Map(
        "id", "integration-test",
        "match", Map("class", WinGetClass("ahk_id " testGui.Hwnd), "titleRegex", "^ShortcutKeys Autofill Worker Test$", "process", WinGetProcessName("ahk_id " testGui.Hwnd)),
        "presentation", Map("mode", "offscreen", "edge", "top", "restore", 1),
        "steps", [
            Map("id", "paste", "control", "Edit1", "action", "setText", "inputMethod", "paste", "value", "pasted {+} value", "verify", "textEquals"),
            Map("id", "type", "control", "Edit2", "action", "setText", "inputMethod", "type", "keyDelayMs", 0, "value", "typed {+} value", "dependsOn", "paste", "verify", "textEquals"),
            Map("id", "check", "control", "Button1", "action", "setChecked", "value", 1, "dependsOn", "type", "verify", "checkedEquals")
        ]
    )
    manager := PersistentWorkerSupervisor(AppLogger("tests", A_Temp "\ShortcutKeysTests"))
    manager.Register("native", A_AhkPath, A_ScriptDir "\..\shortcut-keys-autofill.ahk", 2)
    try {
        manager.Start()
        WaitForWorkers(manager, "native", 2)
        manager.Submit("native", "autofill", Map("targetHwnd", testGui.Hwnd, "rule", rule), (response) => AutofillWorkerResult := response, 10000)
        WaitForResult(&AutofillWorkerResult)
        suite.Assert(pastedControl.Value == "pasted {+} value", "Autofill paste input method failed")
        suite.Assert(typedControl.Value == "typed {+} value", "Autofill type input method failed; actual=" typedControl.Value)
        suite.Assert(AutofillWorkerResult["ok"], "Autofill worker failed: " JsonDump(AutofillWorkerResult))
        suite.Assert(A_Clipboard == clipboardMarker, "Autofill paste did not restore the clipboard")
        suite.Assert(checkbox.Value == 1, "Autofill checkbox step failed")
        WinGetPos(&restoredX, &restoredY,,, "ahk_id " testGui.Hwnd)
        suite.Assert(restoredX == originalX && restoredY == originalY, "Offscreen window position was not restored")
    } finally {
        manager.Stop()
        testGui.Destroy()
        A_Clipboard := savedClipboard
    }
}

TestBrowserWorker(suite) {
    global BrowserWorkerResult := ""
    previousBridgeDir := EnvGet("SHORTCUT_KEYS_BRIDGE_DIR")
    EnvSet("SHORTCUT_KEYS_BRIDGE_DIR", A_ScriptDir "\..\test-results")
    manager := PersistentWorkerSupervisor(AppLogger("tests", A_Temp "\ShortcutKeysTests"))
    manager.Register("browser", A_AhkPath, A_ScriptDir "\..\shortcut-keys-browser.ahk", 1)
    try {
        manager.Start()
        WaitForWorkers(manager, "browser", 1)
        manager.Submit("browser", "browser", Map("action", "status"), (response) => BrowserWorkerResult := response, 5000)
        WaitForResult(&BrowserWorkerResult)
        suite.Assert(BrowserWorkerResult["ok"] && BrowserWorkerResult["code"] == "READY", "Browser bridge did not report ready")
        bridge := BrowserPipeClient.Connect()
        reader := PipeFrameReader(bridge)
        PipeProtocol.Write(bridge, Map("kind", "hello", "browser", "Test Browser", "approvedOrigins", ["https://pve.example:8006", "https://login.example"]))
        initialCache := WaitForBridgeMessage(reader, manager)
        suite.Assert(initialCache["kind"] == "cacheSnapshot" && initialCache["snapshot"]["rules"].Length == 0, "Initial browser cache was not empty")
        BrowserWorkerResult := ""
        browserRule := Map("id", "site", "match", Map("origin", "https://login.example"), "steps", [Map("id", "password", "selector", "#pass", "action", "setText", "value", "synthetic-secret")])
        manager.Submit("browser", "browser", Map("action", "cacheSnapshot", "snapshot", Map("version", 1, "generation", "test-1", "rules", [browserRule])), (response) => BrowserWorkerResult := response, 5000)
        updatedCache := WaitForBridgeMessage(reader, manager)
        WaitForResult(&BrowserWorkerResult)
        suite.Assert(BrowserWorkerResult["ok"] && updatedCache["kind"] == "cacheSnapshot" && updatedCache["snapshot"]["rules"].Length == 1, "Browser cache was not preloaded")
        suite.Assert(updatedCache["snapshot"]["rules"][1]["steps"][1]["value"] == "synthetic-secret", "Browser cache value changed")
        PipeProtocol.Write(bridge, Map("kind", "permissions", "approvedOrigins", [], "allowAllSites", true))
        allSitesCache := WaitForBridgeMessage(reader, manager)
        suite.Assert(allSitesCache["kind"] == "cacheSnapshot" && allSitesCache["snapshot"]["rules"].Length == 1, "All-sites permission did not preload the configured rule")
        manager.SetControlState("browser", "cacheSnapshot", Map("snapshot", Map("version", 1, "generation", "locked", "rules", [])))
        clearedCache := WaitForBridgeMessage(reader, manager)
        suite.Assert(clearedCache["kind"] == "cacheSnapshot" && clearedCache["snapshot"]["rules"].Length == 0, "Out-of-band browser cache clear failed")
        BrowserWorkerResult := ""
        manager.Submit("browser", "browser", Map("action", "listSessions"), (response) => BrowserWorkerResult := response, 5000)
        request := WaitForBridgeMessage(reader, manager)
        suite.Assert(request["kind"] == "list", "Browser worker did not request extension sessions")
        PipeProtocol.Write(bridge, Map("kind", "sessions", "requestId", request["requestId"], "sessions", [Map("tabId", 42, "url", "https://pve.example:8006/?console=kvm", "label", "VM 42")]))
        WaitForResult(&BrowserWorkerResult)
        suite.Assert(BrowserWorkerResult["ok"] && BrowserWorkerResult["sessions"].Length == 1, "Browser session listing failed")
        selected := BrowserWorkerResult["sessions"][1]
        BrowserWorkerResult := ""
        manager.Submit("browser", "browser", Map("action", "sendBatch", "sessionId", selected["sessionId"], "expectedUrl", selected["url"], "text", "{+} Ω", "delayMs", 1), (response) => BrowserWorkerResult := response, 10000)
        request := WaitForBridgeMessage(reader, manager)
        suite.Assert(request["kind"] == "send" && request["text"] == "{+} Ω", "Browser batch changed literal Unicode text")
        manager.SetControlState("browser", "cacheSnapshot", Map("snapshot", Map("version", 1, "generation", "locked-during-send", "rules", [])))
        pendingClear := WaitForBridgeMessage(reader, manager)
        suite.Assert(pendingClear["kind"] == "cacheSnapshot" && pendingClear["snapshot"]["generation"] == "locked-during-send", "Browser cache clear waited for a pending noVNC job")
        PipeProtocol.Write(bridge, Map("kind", "sent", "requestId", request["requestId"], "ok", 1))
        WaitForResult(&BrowserWorkerResult)
        suite.Assert(BrowserWorkerResult["ok"] && BrowserWorkerResult["code"] == "ACCEPTED", "Browser batch acknowledgement failed")
        BrowserWorkerResult := ""
        manager.Submit("browser", "browser", Map("action", "sendBatch", "sessionId", selected["sessionId"], "expectedUrl", "https://pve.example:8006/?console=other", "text", "must not send", "delayMs", 0), (response) => BrowserWorkerResult := response, 5000)
        WaitForResult(&BrowserWorkerResult)
        suite.Assert(!BrowserWorkerResult["ok"] && BrowserWorkerResult["code"] == "BROWSER_SESSION_CHANGED", "Changed noVNC URL was not rejected")
        bridge.Close()
    } finally {
        manager.Stop()
        EnvSet("SHORTCUT_KEYS_BRIDGE_DIR", previousBridgeDir)
    }
}

WaitForBridgeMessage(reader, manager, timeoutMs := 5000) {
    started := A_TickCount
    while A_TickCount - started < timeoutMs {
        manager.Poll()
        result := reader.ReadAvailable()
        if result["messages"].Length
            return result["messages"][1]
        Sleep(20)
    }
    throw Error("Browser extension bridge message timed out")
}

TestEnvelopeTampering(suite) {
    originalIterations := CngCrypto.Iterations
    try {
        CngCrypto.Iterations := 100000
        envelope := CngCrypto.EncryptText("secret", "right")
        for path in ["kdf.salt", "cipher.nonce", "cipher.tag", "ciphertext"] {
            changed := JsonLoad(JsonDump(envelope))
            parts := StrSplit(path, ".")
            owner := parts.Length == 1 ? changed : changed[parts[1]]
            key := parts[parts.Length]
            bytes := BinaryCodec.FromBase64(owner[key])
            NumPut("UChar", NumGet(bytes, 0, "UChar") ^ 1, bytes, 0)
            owner[key] := BinaryCodec.ToBase64(bytes)
            suite.ExpectError((*) => CngCrypto.DecryptEnvelope(changed, "right"), "DECRYPT_FAILED")
        }
    } finally {
        CngCrypto.Iterations := originalIterations
    }
}

WaitForResult(&result, timeoutMs := 12000) {
    started := A_TickCount
    while !(result is Map) && A_TickCount - started < timeoutMs
        Sleep(25)
    if !(result is Map)
        throw Error("Worker did not return a response")
}

WaitForWorkers(manager, role, count, timeoutMs := 10000) {
    started := A_TickCount
    while manager.Status()[role]["ready"] < count && A_TickCount - started < timeoutMs {
        manager.Poll()
        Sleep(25)
    }
    if manager.Status()[role]["ready"] < count
        throw Error("Persistent " role " workers did not become ready")
}

LegacyEncryptForTest(plaintext, password) {
    dataLength := StrPut(plaintext, "UTF-16") * 2
    data := Buffer(dataLength + 32, 0)
    StrPut(plaintext, data, "UTF-16")
    passwordBuffer := Buffer(StrPut(password, "UTF-16") * 2, 0)
    StrPut(password, passwordBuffer, "UTF-16")
    provider := 0, hash := 0, key := 0
    try {
        if !DllCall("Advapi32\CryptAcquireContextW", "Ptr*", &provider, "Ptr", 0, "Ptr", 0, "UInt", 24, "UInt", 0xF0000000)
            throw OSError(A_LastError)
        if !DllCall("Advapi32\CryptCreateHash", "Ptr", provider, "UInt", 0x800C, "Ptr", 0, "UInt", 0, "Ptr*", &hash)
            throw OSError(A_LastError)
        if !DllCall("Advapi32\CryptHashData", "Ptr", hash, "Ptr", passwordBuffer.Ptr, "UInt", passwordBuffer.Size - 2, "UInt", 0)
            throw OSError(A_LastError)
        if !DllCall("Advapi32\CryptDeriveKey", "Ptr", provider, "UInt", 0x6801, "Ptr", hash, "UInt", 0x00800000, "Ptr*", &key)
            throw OSError(A_LastError)
        encryptedLength := dataLength
        if !DllCall("Advapi32\CryptEncrypt", "Ptr", key, "Ptr", 0, "Int", true, "UInt", 0, "Ptr", data.Ptr, "UInt*", &encryptedLength, "UInt", data.Size)
            throw OSError(A_LastError)
        output := ""
        Loop encryptedLength
            output .= Format("{:02X}", NumGet(data, A_Index - 1, "UChar"))
        return output
    } finally {
        SecureZero(data), SecureZero(passwordBuffer)
        if key
            DllCall("Advapi32\CryptDestroyKey", "Ptr", key)
        if hash
            DllCall("Advapi32\CryptDestroyHash", "Ptr", hash)
        if provider
            DllCall("Advapi32\CryptReleaseContext", "Ptr", provider, "UInt", 0)
    }
}
