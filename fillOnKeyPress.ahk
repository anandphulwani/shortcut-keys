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
    {
    }
    Else
    {
    }
return
