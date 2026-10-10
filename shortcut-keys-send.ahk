#Requires AutoHotkey v2.0.30
#SingleInstance Off
#NoTrayIcon
#Warn All, OutputDebug

#Include Includes\Jxon.ahk
#Include Includes\App.ahk
#Include Includes\Logger.ahk
#Include Includes\PipeIpc.ahk

class ScopedInputGuard {
    __New(targetHwnd) {
        this.TargetHwnd := targetHwnd
        this.Cancelled := false
        this.KeyboardHook := 0
        this.MouseHook := 0
        this.KeyboardCallback := CallbackCreate(ObjBindMethod(this, "KeyboardProc"), "Fast", 3)
        this.MouseCallback := CallbackCreate(ObjBindMethod(this, "MouseProc"), "Fast", 3)
    }

    Start() {
        this.KeyboardHook := DllCall("SetWindowsHookExW", "Int", 13, "Ptr", this.KeyboardCallback, "Ptr", DllCall("GetModuleHandleW", "Ptr", 0, "Ptr"), "UInt", 0, "Ptr")
        this.MouseHook := DllCall("SetWindowsHookExW", "Int", 14, "Ptr", this.MouseCallback, "Ptr", DllCall("GetModuleHandleW", "Ptr", 0, "Ptr"), "UInt", 0, "Ptr")
        if !this.KeyboardHook || !this.MouseHook {
            this.Stop()
            throw AppError("Unable to install the scoped input guard", "GUARD_INSTALL_FAILED")
        }
    }

    IsTargetActive() {
        return WinExist("A") == this.TargetHwnd
    }

    KeyboardProc(nCode, wParam, lParam) {
        if nCode < 0 || !this.IsTargetActive()
            return DllCall("CallNextHookEx", "Ptr", this.KeyboardHook, "Int", nCode, "UPtr", wParam, "Ptr", lParam, "Ptr")
        flags := NumGet(lParam, 8, "UInt")
        if flags & 0x10
            return DllCall("CallNextHookEx", "Ptr", this.KeyboardHook, "Int", nCode, "UPtr", wParam, "Ptr", lParam, "Ptr")
        virtualKey := NumGet(lParam, 0, "UInt")
        if virtualKey == 0x1B && GetKeyState("Ctrl", "P") && GetKeyState("Alt", "P") {
            this.Cancelled := true
            return 1
        }
        return 1
    }

    MouseProc(nCode, wParam, lParam) {
        if nCode < 0 || wParam == 0x200
            return DllCall("CallNextHookEx", "Ptr", this.MouseHook, "Int", nCode, "UPtr", wParam, "Ptr", lParam, "Ptr")
        flags := NumGet(lParam, 12, "UInt")
        if flags & 0x1
            return DllCall("CallNextHookEx", "Ptr", this.MouseHook, "Int", nCode, "UPtr", wParam, "Ptr", lParam, "Ptr")
        MouseGetPos(,, &windowUnderCursor)
        if this.IsTargetActive() && windowUnderCursor == this.TargetHwnd
            return 1
        return DllCall("CallNextHookEx", "Ptr", this.MouseHook, "Int", nCode, "UPtr", wParam, "Ptr", lParam, "Ptr")
    }

    Stop() {
        if this.KeyboardHook {
            DllCall("UnhookWindowsHookEx", "Ptr", this.KeyboardHook)
            this.KeyboardHook := 0
        }
        if this.MouseHook {
            DllCall("UnhookWindowsHookEx", "Ptr", this.MouseHook)
            this.MouseHook := 0
        }
    }

    __Delete() {
        this.Stop()
        if this.KeyboardCallback
            CallbackFree(this.KeyboardCallback)
        if this.MouseCallback
            CallbackFree(this.MouseCallback)
    }
}

class SendWorker {
    __New() {
        this.Logger := AppLogger("send-worker")
        this.Guard := ""
        OnExit(ObjBindMethod(this, "OnExit"))
    }

    Run() {
        PersistentWorkerHost("send", ObjBindMethod(this, "HandleJob"), this.Logger).Run()
    }

    HandleJob(job) {
        PipeProtocol.ValidateJob(job, "send")
        try {
            payload := job["payload"]
            hwnd := Integer(MapGet(payload, "targetHwnd", 0))
            targetControl := String(MapGet(payload, "targetControl"))
            text := String(MapGet(payload, "text"))
            delayMs := Max(0, Min(1000, Integer(MapGet(payload, "delayMs", 0))))
            useGuard := !!MapGet(payload, "guard", false)
            if !hwnd || !WinExist("ahk_id " hwnd)
                throw AppError("The target window no longer exists", "TARGET_GONE")
            this.WaitForModifiers(3000)
            if useGuard {
                this.Guard := ScopedInputGuard(hwnd)
                this.Guard.Start()
            }
            started := A_TickCount
            parts := []
            if delayMs {
                position := 1
                while position := RegExMatch(text, "\X", &grapheme, position) {
                    parts.Push(grapheme[0])
                    position += grapheme.Len
                }
            } else {
                parts.Push(text)
            }
            for part in parts {
                if !WinExist("ahk_id " hwnd)
                    throw AppError("The target window closed during input", "TARGET_GONE")
                if this.Guard is ScopedInputGuard {
                    if this.Guard.Cancelled
                        throw AppError("Input was canceled with Ctrl+Alt+Esc", "CANCELED")
                    if !this.Guard.IsTargetActive()
                        this.Guard.Stop()
                }
                if A_TickCount - started > 60000
                    throw AppError("Text entry exceeded the safety timeout", "SEND_TIMEOUT")
                ControlSendText(part, targetControl, "ahk_id " hwnd)
                if delayMs
                    Sleep(delayMs)
            }
            this.Logger.Info("Text entry completed", Map("targetHwnd", hwnd, "characterCount", StrLen(text), "guard", useGuard))
            return WorkerReply(job, true)
        } finally {
            if this.Guard is ScopedInputGuard
                this.Guard.Stop()
            this.Guard := ""
        }
    }

    WaitForModifiers(timeoutMs) {
        started := A_TickCount
        while GetKeyState("Ctrl", "P") || GetKeyState("Shift", "P") || GetKeyState("Alt", "P") {
            if A_TickCount - started > timeoutMs
                throw AppError("Modifier keys were not released", "MODIFIERS_HELD")
            Sleep(10)
        }
    }

    OnExit(reason, code) {
        if this.Guard is ScopedInputGuard
            this.Guard.Stop()
    }
}

if !HasOption(A_Args, "--persistent-worker")
    ExitApp(64)
SendWorker().Run()
ExitApp()
