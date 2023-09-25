F8:: ; F8 hotkey.
+F8:: ; Shift + F8 hotkey.
!F8:: ; Alt + F8 hotkey.
    WinGet, currentWindowId, ID, A
    toolTip2Mesg := 
    ToolTip

    additionalModifier :=
    mainKey := A_ThisHotkey
    If (InStr(A_ThisHotkey, "+") == 1)
    {
        toolTip2Mesg .= "Shift modifier is activated." . "`r`n"
        additionalModifier := "Shift"
        mainKey := SubStr(mainKey, 2)
    }
    Else If (InStr(A_ThisHotkey, "!") == 1)
    {
        toolTip2Mesg .= "Alt modifier is activated." . "`r`n"
        additionalModifier := "Alt"
        mainKey := SubStr(mainKey, 2)
    }
    StartTime := A_TickCount
    longPress := false

    while (GetKeyState(mainKey)) ; || (additionalModifier != "" && GetKeyState(additionalModifier)))
    {
        if (A_TickCount - StartTime >= 500 && !longPress)
        {
            longPress := true
            SoundBeep, 1000, 120
            AddMessageAndDisplayTooltip(StartTime . ": Long press Activated (" . A_ThisHotkey . ")")
            ; AddMessageAndDisplayTooltip(StartTime . ": Waiting for key to be released.....")
        }
        Sleep 5
    }
    textToEnter := parsedCredentialsJSON["passwords"]["password" . (additionalModifier != "" ? "_" . additionalModifier: "")]
    Run, %A_ScriptDir%\F8ShiftF8AltF8.exe %currentWindowId% %longPress% %textToEnter%
    AddMessageAndDisplayTooltip("", -5000)
return
