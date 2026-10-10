#Requires AutoHotkey v2.0.30
#Warn All, StdOut

#Include ..\Includes\Jxon.ahk
#Include ..\Includes\App.ahk
#Include ..\Includes\Logger.ahk
#Include ..\Includes\PipeIpc.ahk

if A_Args.Length < 1
    ExitApp(64)

global SmokeResults := Map("send", "", "native", "", "browser", "")
binaryDirectory := A_Args[1]
outputPath := A_ScriptDir "\..\test-results\compiled-workers-" (A_PtrSize * 8) ".txt"
if FileExist(outputPath)
    FileDelete(outputPath)
manager := PersistentWorkerSupervisor(AppLogger("compiled-smoke", A_Temp "\ShortcutKeysTests"))
manager.Register("send", binaryDirectory "\shortcut-keys-send.exe", "", 1)
manager.Register("native", binaryDirectory "\shortcut-keys-autofill.exe", "", 2)
manager.Register("browser", binaryDirectory "\shortcut-keys-browser.exe", "", 1)

failed := false
try {
    manager.Start()
    WaitForRole(manager, "send", 1)
    WaitForRole(manager, "native", 2)
    WaitForRole(manager, "browser", 1)
    manager.Submit("send", "send", Map("targetHwnd", 0, "targetControl", "", "text", "smoke", "delayMs", 0, "guard", 0), (response) => SmokeResults["send"] := response, 5000)
    manager.Submit("native", "autofill", Map("targetHwnd", 0, "rule", Map()), (response) => SmokeResults["native"] := response, 5000)
    manager.Submit("browser", "browser", Map("action", "status"), (response) => SmokeResults["browser"] := response, 5000)
    WaitForResponses(manager)
    AssertSmoke(SmokeResults["send"] is Map && SmokeResults["send"]["code"] == "TARGET_GONE", "send worker")
    AssertSmoke(SmokeResults["native"] is Map && SmokeResults["native"]["code"] == "TARGET_GONE", "native worker")
    AssertSmoke(SmokeResults["browser"] is Map && SmokeResults["browser"]["ok"], "browser worker")
    FileAppend("PASS compiled persistent workers`r`n", outputPath, "UTF-8")
} catch as caughtError {
    failed := true
    FileAppend("FAIL " caughtError.Message "`r`n", outputPath, "UTF-8")
} finally {
    manager.Stop()
}
ExitApp(failed ? 1 : 0)

WaitForRole(manager, role, count, timeoutMs := 10000) {
    started := A_TickCount
    while manager.Status()[role]["ready"] < count && A_TickCount - started < timeoutMs {
        manager.Poll()
        Sleep(25)
    }
    if manager.Status()[role]["ready"] < count
        throw Error(role " worker handshake timed out")
}

WaitForResponses(manager, timeoutMs := 10000) {
    global SmokeResults
    started := A_TickCount
    while A_TickCount - started < timeoutMs {
        manager.Poll()
        if SmokeResults["send"] is Map && SmokeResults["native"] is Map && SmokeResults["browser"] is Map
            return
        Sleep(25)
    }
    throw Error("compiled worker responses timed out")
}

AssertSmoke(condition, component) {
    if !condition
        throw Error(component " smoke test failed")
}
