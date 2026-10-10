#Requires AutoHotkey v2.0.30
#Warn All, StdOut

#Include ..\Includes\Jxon.ahk
#Include ..\Includes\App.ahk
#Include ..\Includes\Logger.ahk
#Include ..\Includes\Crypto.ahk
#Include ..\Includes\Config.ahk
#Include ..\Includes\CredentialStore.ahk
#Include ..\Includes\PipeIpc.ahk

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

suite.Run("JSON Unicode and escaping", (*) => (
    parsed := JsonLoad('{"message":"hello \u263A","items":[1,2,3]}'),
    suite.Assert(parsed["message"] == "hello ☺", "Unicode escape was not decoded"),
    suite.Assert(JsonLoad(JsonDump(parsed))["items"].Length == 3, "JSON round trip failed")
))

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
    suite.Assert(example["config"]["autofillRules"].Length == 2, "Schema example rules were not loaded")
))

suite.Run("Credential atomic write and verification", (*) => TestCredentialStore(suite))
suite.Run("Legacy credential file migration", (*) => TestLegacyMigration(suite))
suite.Run("Persistent worker handshake, framing, and reuse", (*) => TestWorkerPipe(suite))
suite.Run("Truncated pipe frames are rejected", (*) => TestTruncatedPipe(suite))
suite.Run("Persistent worker timeout and restart are bounded", (*) => TestWorkerTimeout(suite))
suite.Run("Send worker enters literal Unicode", (*) => TestSendWorker(suite))
suite.Run("Native worker pool executes and restores offscreen jobs", (*) => TestAutofillWorker(suite))
suite.Run("Browser bridge starts and reports extension state", (*) => TestBrowserWorker(suite))

suite.Finish()

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

TestSendWorker(suite) {
    global SendWorkerResult := ""
    testGui := Gui(, "ShortcutKeys Send Worker Test")
    textControl := testGui.AddEdit("w400")
    testGui.Show()
    textControl.Focus()
    manager := PersistentWorkerSupervisor(AppLogger("tests", A_Temp "\ShortcutKeysTests"))
    manager.Register("send", A_AhkPath, A_ScriptDir "\..\shortcut-keys-send.ahk", 1)
    try {
        manager.Start()
        WaitForWorkers(manager, "send", 1)
        manager.Submit("send", "send", Map("targetHwnd", testGui.Hwnd, "targetControl", "Edit1", "text", "literal {+} päss 🔐", "delayMs", 0, "guard", 1), (response) => SendWorkerResult := response, 10000)
        WaitForResult(&SendWorkerResult)
        suite.Assert(SendWorkerResult["ok"], "Send worker failed: " JsonDump(SendWorkerResult))
        suite.Assert(textControl.Value == "literal {+} päss 🔐", "Send worker did not preserve literal Unicode text; actual=" textControl.Value)
    } finally {
        manager.Stop()
        testGui.Destroy()
    }
}

TestAutofillWorker(suite) {
    global AutofillWorkerResult := ""
    testGui := Gui(, "ShortcutKeys Autofill Worker Test")
    textControl := testGui.AddEdit("w400")
    checkbox := testGui.AddCheckbox(, "Enabled")
    testGui.Show("x220 y220")
    WinGetPos(&originalX, &originalY,,, "ahk_id " testGui.Hwnd)
    rule := Map(
        "id", "integration-test",
        "match", Map("class", WinGetClass("ahk_id " testGui.Hwnd), "titleRegex", "^ShortcutKeys Autofill Worker Test$", "process", WinGetProcessName("ahk_id " testGui.Hwnd)),
        "presentation", Map("mode", "offscreen", "edge", "top", "restore", 1),
        "steps", [
            Map("id", "text", "control", "Edit1", "action", "setText", "value", "worker value", "verify", "textEquals"),
            Map("id", "check", "control", "Button1", "action", "setChecked", "value", 1, "dependsOn", "text", "verify", "checkedEquals")
        ]
    )
    manager := PersistentWorkerSupervisor(AppLogger("tests", A_Temp "\ShortcutKeysTests"))
    manager.Register("native", A_AhkPath, A_ScriptDir "\..\shortcut-keys-autofill.ahk", 2)
    try {
        manager.Start()
        WaitForWorkers(manager, "native", 2)
        manager.Submit("native", "autofill", Map("targetHwnd", testGui.Hwnd, "rule", rule), (response) => AutofillWorkerResult := response, 10000)
        WaitForResult(&AutofillWorkerResult)
        suite.Assert(AutofillWorkerResult["ok"], "Autofill worker failed: " JsonDump(AutofillWorkerResult))
        suite.Assert(textControl.Value == "worker value", "Autofill text step failed")
        suite.Assert(checkbox.Value == 1, "Autofill checkbox step failed")
        WinGetPos(&restoredX, &restoredY,,, "ahk_id " testGui.Hwnd)
        suite.Assert(restoredX == originalX && restoredY == originalY, "Offscreen window position was not restored")
    } finally {
        manager.Stop()
        testGui.Destroy()
    }
}

TestBrowserWorker(suite) {
    global BrowserWorkerResult := ""
    manager := PersistentWorkerSupervisor(AppLogger("tests", A_Temp "\ShortcutKeysTests"))
    manager.Register("browser", A_AhkPath, A_ScriptDir "\..\shortcut-keys-browser.ahk", 1)
    try {
        manager.Start()
        WaitForWorkers(manager, "browser", 1)
        manager.Submit("browser", "browser", Map("action", "status"), (response) => BrowserWorkerResult := response, 5000)
        WaitForResult(&BrowserWorkerResult)
        suite.Assert(BrowserWorkerResult["ok"] && BrowserWorkerResult["code"] == "READY", "Browser bridge did not report ready")
    } finally {
        manager.Stop()
    }
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
