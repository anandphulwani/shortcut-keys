#Requires AutoHotkey v2.0.30
#SingleInstance Off
#NoTrayIcon
#Warn All, OutputDebug

#Include Includes\Jxon.ahk
#Include Includes\App.ahk
#Include Includes\Logger.ahk
#Include Includes\PipeIpc.ahk

class AutofillWorker {
    __New() {
        this.Logger := AppLogger("autofill-worker")
    }

    Run() {
        PersistentWorkerHost("native", ObjBindMethod(this, "HandleJob"), this.Logger).Run()
    }

    HandleJob(job) {
        PipeProtocol.ValidateJob(job, "autofill")
        snapshot := ""
        try {
            payload := job["payload"]
            hwnd := Integer(MapGet(payload, "targetHwnd", 0))
            rule := RequireMap(MapGet(payload, "rule", 0), "autofill rule")
            if !hwnd || !WinExist("ahk_id " hwnd)
                throw AppError("The target window no longer exists", "TARGET_GONE")
            this.AssertMatch(hwnd, RequireMap(rule["match"], "autofill match"))
            presentation := MapGet(rule, "presentation", 0)
            if presentation is Map && MapGet(presentation, "mode", "normal") == "offscreen"
                snapshot := this.MoveOffscreen(hwnd, presentation)
            else if rule.Has("move") {
                move := RequireMap(rule["move"], "window move")
                WinMove(Integer(move["x"]), Integer(move["y"]),,, "ahk_id " hwnd)
            }
            completed := Map()
            for step in RequireArray(rule["steps"], "autofill steps") {
                stepId := String(step["id"])
                if step.Has("dependsOn") && !completed.Has(String(step["dependsOn"]))
                    continue
                this.AssertMatch(hwnd, rule["match"])
                this.ExecuteStep(hwnd, step)
                completed[stepId] := true
            }
            this.Logger.Info("Autofill completed", Map("targetHwnd", hwnd, "ruleId", MapGet(rule, "id"), "stepCount", completed.Count))
            return WorkerReply(job, true)
        } finally {
            if snapshot is Map
                this.RestoreWindow(hwnd, snapshot)
        }
    }

    MoveOffscreen(hwnd, presentation) {
        WinGetPos(&x, &y, &width, &height, "ahk_id " hwnd)
        state := WinGetMinMax("ahk_id " hwnd)
        snapshot := Map("x", x, "y", y, "width", width, "height", height, "state", state)
        if state != 0
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
            offX := virtualX - width - margin, offY := virtualY
        else if edge == "right"
            offX := virtualX + virtualWidth + margin, offY := virtualY
        else
            offX := virtualX, offY := virtualY - height - margin
        WinMove(offX, offY, width, height, "ahk_id " hwnd)
        return snapshot
    }

    RestoreWindow(hwnd, snapshot) {
        if !WinExist("ahk_id " hwnd)
            return
        try {
            WinRestore("ahk_id " hwnd)
            WinMove(snapshot["x"], snapshot["y"], snapshot["width"], snapshot["height"], "ahk_id " hwnd)
            if snapshot["state"] == 1
                WinMaximize("ahk_id " hwnd)
            else if snapshot["state"] == -1
                WinMinimize("ahk_id " hwnd)
        }
    }

    AssertMatch(hwnd, match) {
        if !WinExist("ahk_id " hwnd)
            throw AppError("The target window no longer exists", "TARGET_GONE")
        if match.Has("class") && WinGetClass("ahk_id " hwnd) != match["class"]
            throw AppError("The target window class changed", "TARGET_CHANGED")
        if match.Has("titleRegex") && !RegExMatch(WinGetTitle("ahk_id " hwnd), match["titleRegex"])
            throw AppError("The target window title changed", "TARGET_CHANGED")
        if match.Has("process") && StrLower(WinGetProcessName("ahk_id " hwnd)) != StrLower(match["process"])
            throw AppError("The target window process changed", "TARGET_CHANGED")
    }

    ExecuteStep(hwnd, step) {
        control := String(step["control"])
        action := String(step["action"])
        timeoutMs := Max(100, Min(60000, Integer(MapGet(step, "timeoutMs", AppInfo.DefaultControlTimeoutMs))))
        retryMs := Max(10, Min(1000, Integer(MapGet(step, "retryMs", AppInfo.DefaultRetryMs))))
        this.WaitForControl(hwnd, control, timeoutMs, retryMs)
        if action == "setText" {
            value := String(MapGet(step, "value"))
            this.RetryUntil((*) => this.SetAndVerifyText(hwnd, control, value, MapGet(step, "verify", "controlExists")), timeoutMs, retryMs, "SET_TEXT_FAILED")
        } else if action == "setChecked" {
            desired := !!MapGet(step, "value", false)
            this.RetryUntil((*) => this.SetAndVerifyChecked(hwnd, control, desired, MapGet(step, "verify", "checkedEquals")), timeoutMs, retryMs, "SET_CHECKED_FAILED")
        } else if action == "click" {
            ControlClick(control, "ahk_id " hwnd)
            if MapGet(step, "verify") == "windowClosed"
                this.RetryUntil((*) => !WinExist("ahk_id " hwnd), timeoutMs, retryMs, "WINDOW_CLOSE_TIMEOUT")
        }
    }

    WaitForControl(hwnd, control, timeoutMs, retryMs) {
        this.RetryUntil((*) => this.ControlExists(hwnd, control), timeoutMs, retryMs, "CONTROL_TIMEOUT")
    }

    ControlExists(hwnd, control) {
        try return !!ControlGetHwnd(control, "ahk_id " hwnd)
        catch
            return false
    }

    SetAndVerifyText(hwnd, control, value, verification) {
        try ControlSetText(value, control, "ahk_id " hwnd)
        catch
            return false
        if verification == "none"
            return true
        if verification == "textEquals" {
            try return ControlGetText(control, "ahk_id " hwnd) == value
            catch
                return false
        }
        return this.ControlExists(hwnd, control)
    }

    SetAndVerifyChecked(hwnd, control, desired, verification) {
        try current := !!ControlGetChecked(control, "ahk_id " hwnd)
        catch
            return false
        if current != desired {
            try ControlClick(control, "ahk_id " hwnd)
            catch
                return false
        }
        if verification == "none"
            return true
        if verification == "controlExists"
            return this.ControlExists(hwnd, control)
        try return !!ControlGetChecked(control, "ahk_id " hwnd) == desired
        catch
            return false
    }

    RetryUntil(predicate, timeoutMs, retryMs, code) {
        started := A_TickCount
        loop {
            if predicate.Call()
                return true
            if A_TickCount - started >= timeoutMs
                throw AppError("An autofill step timed out", code)
            Sleep(retryMs)
        }
    }
}

if !HasOption(A_Args, "--persistent-worker")
    ExitApp(64)
AutofillWorker().Run()
ExitApp()
