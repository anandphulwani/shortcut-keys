fillOnKeyPress(isSlow, additionalModifier)
{
    global toolTip2Mesg, parsedCredentialsJSON
    sleepTime := 20
    WinGetTitle, CurrTitle, A
    Loop, 3
    {
        toolTip2Mesg .= "Doing entry in " . (3 - (A_INDEX - 1)) . " deci - seconds on " . CurrTitle . "`r`n"
        ToolTip, % toolTip2Mesg
        Sleep, % sleepTime
    }

    mode := "send"
    If (mode == "send")
    {
        Send, % parsedCredentialsJSON["passwords"]["password" . (additionalModifier != "" ? "_" . additionalModifier: "")]
    }
    Else If (mode == "controlsend")
    {
        ; ControlSend, ahk_parent, % parsedCredentialsJSON.password.password, A
    }

    toolTip2Mesg .= "Entry done on " . CurrTitle . "`r`n"
    ToolTip, % toolTip2Mesg
}
