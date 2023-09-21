F8:: ; F8 hotkey.
+F8:: ; Shift + F8 hotkey.
!F8:: ; Alt + F8 hotkey.
    global toolTip2Mesg, parsedCredentialsJSON
    toolTip2Mesg := 
    ToolTip
    {
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
return
