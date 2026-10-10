class WindowEventMonitor {
    __New(handler) {
        this.Handler := handler
        this.Callback := CallbackCreate(ObjBindMethod(this, "OnEvent"), "Fast", 7)
        this.Hook := 0
    }

    Start() {
        if this.Hook
            return
        this.Hook := DllCall("SetWinEventHook"
            , "UInt", 0x8000, "UInt", 0x8002
            , "Ptr", 0, "Ptr", this.Callback
            , "UInt", 0, "UInt", 0, "UInt", 0
            , "Ptr")
        if !this.Hook
            throw OSError(A_LastError, -1, "SetWinEventHook failed")
    }

    OnEvent(hook, event, hwnd, idObject, idChild, threadId, eventTime) {
        if !hwnd || idObject != 0
            return
        if event != 0x8001 && DllCall("GetAncestor", "Ptr", hwnd, "UInt", 2, "Ptr") != hwnd
            return
        try this.Handler.Call(event, hwnd)
    }

    Stop() {
        if this.Hook {
            DllCall("UnhookWinEvent", "Ptr", this.Hook)
            this.Hook := 0
        }
    }

    __Delete() {
        this.Stop()
        if this.Callback
            CallbackFree(this.Callback)
    }
}
