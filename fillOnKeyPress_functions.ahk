fillOnKeyPress(isSlow, additionalModifier)
{
    global toolTip2Mesg, parsedCredentialsJSON
    sleepTime := 20
    SetKeyDelay, 10, 10
    if(isSlow)
    {
        ; Increase the delay
        sleepTime := 100
        SetKeyDelay, 100, 50
        SetControlDelay, 250
    }
    WinGetTitle, CurrTitle, A
    Loop, 3
    {
        AddMessageAndDisplayTooltip("Doing entry in " . (3 - (A_INDEX - 1)) . " deci - seconds on " . CurrTitle)
        Sleep, % sleepTime
    }

    mode := "send"
    If (mode == "send")
    {
        passwordToSend := parsedCredentialsJSON["passwords"]["password" . (additionalModifier != "" ? "_" . additionalModifier: "")]
        Send, {Blind}{Text}%passwordToSend%
        AddMessageAndDisplayTooltip("Password sent is: " . passwordToSend)
    }
    Else If (mode == "controlsend")
    {
        ; ControlSend, ahk_parent, % parsedCredentialsJSON.password.password, A
    }

    if(isSlow)
    {
        ; Bring back to normal
        SetKeyDelay, 10, 10
        SetControlDelay, 20
    }
    AddMessageAndDisplayTooltip("Entry done on " . CurrTitle, -5000)
}
