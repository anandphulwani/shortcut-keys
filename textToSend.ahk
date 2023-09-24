^F8:: ; Ctrl+F8 hotkey.
    if WinExist("ShortcutKeys-Text To Send")
    {
        WinActivate
        return
    }
    WinGet, currentWindowId, ID, A
    toolTip2Mesg := 
    ToolTip

    Run, %A_ScriptDir%\CtrlF8.exe %currentWindowId%
    AddMessageAndDisplayTooltip("", -5000)
Return
