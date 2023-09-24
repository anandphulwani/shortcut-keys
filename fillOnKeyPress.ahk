F8:: ; F8 hotkey.
+F8:: ; Shift + F8 hotkey.
!F8:: ; Alt + F8 hotkey.
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

    while (GetKeyState(mainKey) || (additionalModifier != "" && GetKeyState(additionalModifier)))
    {
        if (A_TickCount - StartTime >= 1000 && !longPress)
        {
            longPress := true
            SoundBeep, 1000, 120
            AddMessageAndDisplayTooltip(StartTime . ": Long press Activated (" . A_ThisHotkey . ")")
            AddMessageAndDisplayTooltip(StartTime . ": Waiting for key to be released.....")
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
