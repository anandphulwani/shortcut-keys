#Requires AutoHotkey v2.0.30
#SingleInstance Off
#NoTrayIcon
#Warn All, OutputDebug

#Include Includes\Jxon.ahk
#Include Includes\App.ahk
#Include Includes\Logger.ahk
#Include Includes\PipeIpc.ahk

class BrowserBridgeWorker {
    __New() {
        this.Logger := AppLogger("browser-worker")
    }

    Run() {
        PersistentWorkerHost("browser", ObjBindMethod(this, "HandleJob"), this.Logger).Run()
    }

    HandleJob(job) {
        PipeProtocol.ValidateJob(job, "browser")
        action := String(MapGet(job["payload"], "action", "dispatch"))
        if action == "status"
            return WorkerReply(job, true, "READY", "Browser bridge is ready; no extension is connected")
        throw AppError("Browser page automation requires the ShortcutKeys browser extension", "BROWSER_EXTENSION_REQUIRED")
    }
}

if !HasOption(A_Args, "--persistent-worker")
    ExitApp(64)
BrowserBridgeWorker().Run()
ExitApp()
