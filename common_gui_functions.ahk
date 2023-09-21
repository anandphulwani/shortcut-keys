^ENTER::
^NUMPADENTER::
    WinGet, currentWindowId, ID, A
    WinGet, currentProcessName, ProcessName, A
    If (currentProcessName != "AutoHotkey.exe")
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
    Else
    {
        while(WinExist("ahk_id " currentWindowId) && A_INDEX < 20) {
            ControlClick, Button1, % "ahk_id " currentWindowId
            tooltipMesg .= "Got in the " . A_ThisHotkey . " section, to submit the form : " . A_INDEX . "`r`n"
            ToolTip, % tooltipMesg
            Sleep, 150
            if (A_INDEX == 19)
            {
                MsgBox, % "Unable to `Button` click `OK` loop, 19 times."
                ExitApp
            }
        }
    }
Return
