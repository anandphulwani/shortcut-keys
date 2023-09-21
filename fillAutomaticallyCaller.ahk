#Include %A_ScriptDir%\Includes\EWinHook.ahk

hHook := EWinHook_SetWinEventHook("EVENT_OBJECT_CREATE", "EVENT_OBJECT_CREATE", 0, "WinProcCallback", 0, 0, "WINEVENT_OUTOFCONTEXT")
OnExit("ExitFunc")
ExitFunc(ExitReason, ExitCode)
{
    EWinHook_UnhookWinEvent(hHook)
}

WinProcCallback(hWinEventHook, event, hwnd, idObject, idChild, dwEventThread, dwmsEventTime) 
{
    DetectHiddenWindows, On
    WinGetClass, sClass, ahk_id %hwnd%
    WinGetTitle, sTitle, ahk_id %hwnd%
    If ( sClass == "#32770" && sTitle == "Radmin Security" && event == "32768")
    {
        ; MsgBox, % "Hooks Got this: " . A_TICKCOUNT
        Run, %A_ScriptDir%\fillAutomatically.exe "Radmin security" %hwnd%
    }
}
