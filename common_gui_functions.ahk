^ENTER::
^NUMPADENTER::
    global toolTip2Mesg, parsedCredentialsJSON
    WinGet, currentWindowId, ID, A
    WinGetActiveTitle, currentTitle
    If (currentTitle == "ShortcutKeys-Text To Send" || currentTitle == "Select Re-enable password auto fill mode")
    {
        while((WinExist("ShortcutKeys-Text To Send") || WinExist("Select Re-enable password auto fill mode")) && A_INDEX < 20) {
            If(WinExist("ShortcutKeys-Text To Send"))
            {
                ControlClick, Button1, % "ShortcutKeys-Text To Send"
            }
            Else If(WinExist("Select Re-enable password auto fill mode"))
            {
                ControlClick, Button1, % "Select Re-enable password auto fill mode"
            }
            AddMessageAndDisplayTooltip("Got in the " . A_ThisHotkey . " section, to submit the form : " . A_INDEX)
            Sleep, 150
            if (A_INDEX == 19)
            {
                MsgBox, % "Unable to `Button` click `OK` loop, 19 times."
                ExitApp
            }
        }
    }
    Else
    {
        modifierKey := SubStr(A_ThisHotkey, 1, 1)
        if (modifierKey != "^")
        {
            MsgBox, Illegar modifier key used
        }
        mainKey := SubStr(A_ThisHotkey, 2)
        mainKey := "{" . mainKey . "}"
        Suspend, On
        SendInput, % modifierKey . mainKey
        Sleep, 20
        Suspend, Off
    }
    AddMessageAndDisplayTooltip("", -5000)
Return
