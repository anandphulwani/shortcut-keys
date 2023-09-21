F8:: ; F8 hotkey.
+F8:: ; Shift + F8 hotkey.
!F8:: ; Alt + F8 hotkey.
    global toolTip2Mesg, parsedCredentialsJSON
    toolTip2Mesg := 
    ToolTip

    additionalModifier :=
    mainKey := A_ThisHotkey
    If (InStr(A_ThisHotkey, "+") == 1)
    {
        additionalModifier := "Shift"
        mainKey := SubStr(mainKey, 2)
    }
    Else If (InStr(A_ThisHotkey, "!") == 1)
    {
        additionalModifier := "Alt"
        mainKey := SubStr(mainKey, 2)
    }
    StartTime := A_TickCount
    longPress := false

    while (GetKeyState(mainKey) && (additionalModifier == "" || GetKeyState(additionalModifier)))
    {
        if (A_TickCount - StartTime >= 200 && !longPress)
        {
            longPress := true
            SoundBeep, 1000, 120
            toolTip2Mesg .= StartTime . ": Long press Activated (" . A_ThisHotkey . ") `r`n"
            ToolTip, % toolTip2Mesg
        }
        Sleep 5
    }
    If (longPress)
    {
        toolTip2Mesg .= StartTime . ": Long press Block (" . A_ThisHotkey . ") `r`n"
        fillOnKeyPress(true, additionalModifier)
    }
    Else
    {
        toolTip2Mesg .= StartTime . ": Short press Block (" . A_ThisHotkey . ") `r`n"
        fillOnKeyPress(false, additionalModifier)
    }

    ToolTip, % toolTip2Mesg
    SetTimer, RemoveToolTip, -5000
return
