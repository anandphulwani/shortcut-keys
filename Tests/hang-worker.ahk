#Requires AutoHotkey v2.0.30
#SingleInstance Off
#NoTrayIcon

#Include ..\Includes\Jxon.ahk
#Include ..\Includes\App.ahk
#Include ..\Includes\Logger.ahk
#Include ..\Includes\PipeIpc.ahk

HandleHangJob(job) {
    PipeProtocol.ValidateJob(job, "hang")
    Sleep(5000)
    return WorkerReply(job, true)
}

PersistentWorkerHost("hang", HandleHangJob, AppLogger("hang-test-worker")).Run()
ExitApp()
