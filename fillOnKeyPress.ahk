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
            AddMessageAndDisplayTooltip(StartTime . ": Long press Activated (" . A_ThisHotkey . ")")
        }
        Sleep 5
    }
    If (longPress)
    {
        AddMessageAndDisplayTooltip(StartTime . ": Long press Block (" . A_ThisHotkey . ")")
        fillOnKeyPress(true, additionalModifier)
    }
    Else
    {
        AddMessageAndDisplayTooltip(StartTime . ": Short press Block (" . A_ThisHotkey . ")")
        fillOnKeyPress(false, additionalModifier)
    }
return
